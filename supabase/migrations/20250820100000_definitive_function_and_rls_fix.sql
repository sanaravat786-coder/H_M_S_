/*
          # [Definitive Function and RLS Fix]
          This script provides a comprehensive fix for all previously encountered migration errors related to function dependencies and security advisories. It safely drops all custom functions and their dependent Row Level Security (RLS) policies using CASCADE, and then recreates them from scratch with hardened security settings (e.g., `SET search_path`). This ensures a clean, consistent, and secure state for all database functions and policies.

          ## Query Description: [This operation will temporarily drop and then recreate several functions and RLS policies. It is designed to be safe and non-destructive to your data, but it's always wise to ensure you have a recent database backup before running significant schema changes. This will resolve the "cannot drop function" and "search_path" errors.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Security"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [true]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops and recreates functions: `is_admin`, `is_staff`, `get_user_role`, `get_unallocated_students`, `allocate_room`, `update_room_occupancy`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`, `universal_search`.
          - Drops and recreates RLS policies on tables: `attendance_sessions`, `attendance_records`, `leaves`.
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [Yes]
          - Auth Requirements: [Relies on `auth.uid()` and `profiles` table for role checks.]
          
          ## Performance Impact:
          - Indexes: [No change]
          - Triggers: [No change]
          - Estimated Impact: [Minimal performance impact. This is primarily a structural and security update.]
          */

-- Step 1: Drop all conflicting functions and their dependent objects (like RLS policies)
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;
DROP FUNCTION IF EXISTS public.is_staff() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_role(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_unallocated_students() CASCADE;
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, uuid, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.universal_search(text) CASCADE;

-- Step 2: Recreate all functions with security hardening (SET search_path)

-- Function: is_admin()
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM profiles
    WHERE id = auth.uid() AND role = 'Admin'
  );
END;
$$;

-- Function: is_staff()
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM profiles
    WHERE id = auth.uid() AND (role = 'Admin' OR role = 'Staff')
  );
END;
$$;

-- Function: get_user_role(uuid)
CREATE OR REPLACE FUNCTION public.get_user_role(p_user_id uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = p_user_id;
$$;

-- Function: get_unallocated_students()
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT s.id, s.full_name, s.email, s.course
  FROM students s
  WHERE NOT EXISTS (
    SELECT 1
    FROM room_allocations ra
    WHERE ra.student_id = s.id AND ra.is_active = true
  )
  ORDER BY s.full_name;
$$;

-- Function: allocate_room(uuid, uuid)
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE room_allocations
  SET is_active = false, end_date = now()
  WHERE student_id = p_student_id AND is_active = true;

  INSERT INTO room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, now(), true);
END;
$$;

-- Function: update_room_occupancy(uuid)
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_occupant_count int;
BEGIN
  SELECT count(*) INTO v_occupant_count
  FROM room_allocations
  WHERE room_id = p_room_id AND is_active = true;

  UPDATE rooms
  SET
    occupants = v_occupant_count,
    status = CASE
      WHEN status = 'Maintenance' THEN 'Maintenance'
      WHEN v_occupant_count > 0 THEN 'Occupied'
      ELSE 'Vacant'
    END
  WHERE id = p_room_id;
END;
$$;

-- Function: get_or_create_session
CREATE OR REPLACE FUNCTION public.get_or_create_session(
  p_date date,
  p_type text,
  p_block text DEFAULT NULL,
  p_room_id uuid DEFAULT NULL,
  p_course text DEFAULT NULL,
  p_year text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  SELECT id INTO v_session_id
  FROM attendance_sessions
  WHERE session_date = p_date
    AND session_type = p_type
    AND coalesce(block, '') = coalesce(p_block, '')
    AND coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND coalesce(course, '') = coalesce(p_course, '')
    AND coalesce(year, '') = coalesce(p_year, '');

  IF v_session_id IS NULL THEN
    INSERT INTO attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    VALUES (p_date, p_type, p_block, p_room_id, p_course, p_year, auth.uid())
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

-- Function: bulk_mark_attendance
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec jsonb;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    INSERT INTO attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    VALUES (
      p_session_id,
      (rec->>'student_id')::uuid,
      rec->>'status',
      rec->>'note',
      coalesce((rec->>'late_minutes')::int, 0),
      auth.uid()
    )
    ON CONFLICT (session_id, student_id) DO UPDATE
      SET status = excluded.status,
          note = excluded.note,
          late_minutes = excluded.late_minutes,
          marked_at = now(),
          marked_by = auth.uid();
  END LOOP;
END;
$$;

-- Function: student_attendance_calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status text, session_type text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
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
    coalesce(r.status, 'Unmarked') AS status,
    s.session_type
  FROM days d
  LEFT JOIN attendance_sessions s ON s.session_date = d.d
  LEFT JOIN attendance_records r ON r.session_id = s.id AND r.student_id = p_student_id
  ORDER BY d.d ASC;
$$;

-- Function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(id uuid, label text, path text, type text)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT s.id, s.full_name AS label, '/students/' || s.id::text AS path, 'Student' AS type
    FROM students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
    LIMIT 5

    UNION ALL

    SELECT r.id, 'Room ' || r.room_number AS label, '/rooms/' || r.id::text AS path, 'Room' AS type
    FROM rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%'
    LIMIT 5;
END;
$$;


-- Step 3: Recreate the RLS policies that were dropped by CASCADE

-- Policies for attendance_sessions
CREATE POLICY "Admins and Staff can manage all sessions" ON public.attendance_sessions
  FOR ALL USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Students can view sessions they are part of" ON public.attendance_sessions
  FOR SELECT USING (EXISTS (
    SELECT 1 FROM attendance_records ar WHERE ar.session_id = attendance_sessions.id AND ar.student_id = auth.uid()
  ));

-- Policies for attendance_records
CREATE POLICY "Admins and Staff can manage all records" ON public.attendance_records
  FOR ALL USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Students can view their own records" ON public.attendance_records
  FOR SELECT USING (student_id = auth.uid());

-- Policies for leaves
CREATE POLICY "Admins and Staff can manage all leaves" ON public.leaves
  FOR ALL USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Students can manage their own leaves" ON public.leaves
  FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());
