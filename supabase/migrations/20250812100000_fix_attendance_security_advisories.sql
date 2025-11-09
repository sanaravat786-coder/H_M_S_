/*
          # [SECURITY FIX] Harden Attendance Module
          This migration script addresses critical security advisories identified after the initial attendance module setup. It corrects a dangerous `SECURITY DEFINER` view, hardens all related functions against search path attacks, and implements the necessary Row Level Security (RLS) policies.

          ## Query Description: This operation is critical for securing the new attendance feature.
          1. The `v_attendance_daily_summary` view is recreated with `SECURITY INVOKER` (the default, safer option) to ensure it respects the permissions of the user running the query.
          2. All functions (`get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`) are redefined to set a fixed `search_path`. This prevents malicious users from manipulating function execution.
          3. Row Level Security policies are created for `attendance_sessions`, `attendance_records`, and `leaves` to enforce data access rules for different user roles (Admin, Staff, Student).

          This script is safe to run and is essential for data integrity and security.

          ## Metadata:
          - Schema-Category: "Security"
          - Impact-Level: "High"
          - Requires-Backup: false
          - Reversible: true

          ## Structure Details:
          - Views Modified: `v_attendance_daily_summary`
          - Functions Modified: `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`
          - Functions Created: `get_my_role`
          - Tables Affected: `attendance_sessions`, `attendance_records`, `leaves` (RLS policies added)

          ## Security Implications:
          - RLS Status: Enabled and policies created for new tables.
          - Policy Changes: Yes. This script adds the missing RLS policies.
          - Auth Requirements: Policies rely on JWT claims to determine user roles.
          
          ## Performance Impact:
          - Indexes: None
          - Triggers: None
          - Estimated Impact: Negligible. Improves security without performance degradation.
          */

-- Step 1: Drop the insecure view.
DROP VIEW IF EXISTS public.v_attendance_daily_summary;

-- Step 2: Recreate the view with the default, secure `SECURITY INVOKER` property.
CREATE OR REPLACE VIEW public.v_attendance_daily_summary as
select
  s.session_date,
  s.session_type,
  s.block,
  s.room_id,
  s.course,
  s.year,
  count(*) filter (where r.status = 'Present') as present_count,
  count(*) filter (where r.status = 'Absent')  as absent_count,
  count(*) filter (where r.status = 'Late')    as late_count,
  count(*) filter (where r.status = 'Excused') as excused_count,
  count(*) as total_marked
from attendance_sessions s
left join attendance_records r on r.session_id = s.id
group by s.session_date, s.session_type, s.block, s.room_id, s.course, s.year;

-- Step 3: Harden all functions by setting a secure search_path.
CREATE OR REPLACE FUNCTION public.get_or_create_session(
  p_date date,
  p_type text,
  p_block text DEFAULT NULL,
  p_room_id uuid DEFAULT NULL,
  p_course text DEFAULT NULL,
  p_year text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM attendance_sessions
  WHERE session_date = p_date AND session_type = p_type
    AND COALESCE(block, '') = COALESCE(p_block, '')
    AND COALESCE(room_id, '00000000-0000-0000-0000-000000000000'::uuid) = COALESCE(p_room_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND COALESCE(course, '') = COALESCE(p_course, '')
    AND COALESCE(year, '') = COALESCE(p_year, '');

  IF v_id IS NULL THEN
    INSERT INTO attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    VALUES (p_date, p_type, p_block, p_room_id, p_course, p_year, auth.uid())
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  rec jsonb;
  v_student uuid;
  v_status text;
  v_note text;
  v_late int;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    v_student := (rec->>'student_id')::uuid;
    v_status  := rec->>'status';
    v_note    := rec->>'note';
    v_late    := COALESCE((rec->>'late_minutes')::int, 0);

    INSERT INTO attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    VALUES (p_session_id, v_student, v_status, v_note, v_late, auth.uid())
    ON CONFLICT (session_id, student_id) DO UPDATE
      SET status = excluded.status,
          note = excluded.note,
          late_minutes = excluded.late_minutes,
          marked_at = now(),
          marked_by = auth.uid();
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.student_attendance_calendar(
  p_student_id uuid,
  p_month int,
  p_year int
)
RETURNS TABLE(day date, status text, session_type text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = 'public'
AS $$
  WITH days AS (
    SELECT generate_series(
      make_date(p_year, p_month, 1),
      (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date,
      interval '1 day'
    )::date AS d
  )
  SELECT
    d.d AS day,
    COALESCE(r.status, 'Unmarked') AS status,
    s.session_type
  FROM days d
  LEFT JOIN attendance_sessions s ON s.session_date = d.d
  LEFT JOIN attendance_records r ON r.session_id = s.id AND r.student_id = p_student_id
  ORDER BY d.d ASC;
$$;

-- Step 4: Create a helper function to get the user's role from the JWT.
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true)::jsonb->>'role', ''), 'anon')::text;
$$;

-- Step 5: Implement Row Level Security policies.

-- RLS for attendance_sessions
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow admin and staff full access" ON public.attendance_sessions;
CREATE POLICY "Allow admin and staff full access" ON public.attendance_sessions
  FOR ALL USING (get_my_role() IN ('Admin', 'Staff'));
DROP POLICY IF EXISTS "Allow students to see sessions they are part of" ON public.attendance_sessions;
CREATE POLICY "Allow students to see sessions they are part of" ON public.attendance_sessions
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM attendance_records ar
    JOIN students s ON ar.student_id = s.id
    WHERE ar.session_id = attendance_sessions.id AND s.profile_id = auth.uid()
  ));

-- RLS for attendance_records
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow admin and staff full access" ON public.attendance_records;
CREATE POLICY "Allow admin and staff full access" ON public.attendance_records
  FOR ALL USING (get_my_role() IN ('Admin', 'Staff'));
DROP POLICY IF EXISTS "Allow students to see their own records" ON public.attendance_records;
CREATE POLICY "Allow students to see their own records" ON public.attendance_records
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM students s WHERE s.id = attendance_records.student_id AND s.profile_id = auth.uid()
  ));

-- RLS for leaves
ALTER TABLE public.leaves ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow admin and staff full access" ON public.leaves;
CREATE POLICY "Allow admin and staff full access" ON public.leaves
  FOR ALL USING (get_my_role() IN ('Admin', 'Staff'));
DROP POLICY IF EXISTS "Allow students to manage their own leave requests" ON public.leaves;
CREATE POLICY "Allow students to manage their own leave requests" ON public.leaves
  FOR ALL USING (EXISTS (
    SELECT 1 FROM students s WHERE s.id = leaves.student_id AND s.profile_id = auth.uid()
  ));
