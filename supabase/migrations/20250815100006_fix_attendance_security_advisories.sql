/*
          # [Security Hardening] Fix View and Function Advisories
          This migration script addresses security advisories by altering the attendance view to use SECURITY INVOKER and hardening all related functions by setting a fixed search_path.

          ## Query Description: 
          - The `v_attendance_daily_summary` view is changed from SECURITY DEFINER to SECURITY INVOKER. This is a critical security fix to ensure that Row Level Security (RLS) policies are enforced based on the user querying the view, not the view's owner. This prevents unauthorized data access.
          - All functions (`is_admin`, `is_staff`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`) are recreated with `SET search_path = public`. This prevents potential hijacking attacks by ensuring the functions do not use a user-modifiable search path.
          - These changes are safe and do not risk data loss. They are essential for a secure production environment.
          
          ## Metadata:
          - Schema-Category: "Security"
          - Impact-Level: "High"
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Modifies: VIEW `v_attendance_daily_summary`
          - Modifies: FUNCTION `is_admin()`
          - Modifies: FUNCTION `is_staff()`
          - Modifies: FUNCTION `get_or_create_session()`
          - Modifies: FUNCTION `bulk_mark_attendance()`
          - Modifies: FUNCTION `student_attendance_calendar()`
          
          ## Security Implications:
          - RLS Status: Correctly enforces RLS on the summary view.
          - Policy Changes: No.
          - Auth Requirements: No change.
          
          ## Performance Impact:
          - Indexes: None.
          - Triggers: None.
          - Estimated Impact: Negligible performance impact; significant security improvement.
          */

-- ========= FIX 1: CHANGE VIEW TO SECURITY INVOKER =========
-- Recreate the view with security_invoker=true to enforce the querier's RLS policies.
CREATE OR REPLACE VIEW v_attendance_daily_summary WITH (security_invoker = true) AS
SELECT
  s.session_date,
  s.session_type,
  s.block,
  s.room_id,
  s.course,
  s.year,
  count(*) FILTER (WHERE r.status = 'Present') AS present_count,
  count(*) FILTER (WHERE r.status = 'Absent') AS absent_count,
  count(*) FILTER (WHERE r.status = 'Late') AS late_count,
  count(*) FILTER (WHERE r.status = 'Excused') AS excused_count,
  count(*) AS total_marked
FROM attendance_sessions s
LEFT JOIN attendance_records r ON r.session_id = s.id
GROUP BY s.session_date, s.session_type, s.block, s.room_id, s.course, s.year;


-- ========= FIX 2: HARDEN ALL RELATED FUNCTIONS WITH SEARCH_PATH =========

-- Harden is_admin function
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_admin_user BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM profiles
    WHERE id = auth.uid() AND role = 'Admin'
  ) INTO is_admin_user;
  RETURN is_admin_user;
END;
$$;

-- Harden is_staff function
CREATE OR REPLACE FUNCTION is_staff()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  is_staff_user BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM profiles
    WHERE id = auth.uid() AND role IN ('Admin', 'Staff')
  ) INTO is_staff_user;
  RETURN is_staff_user;
END;
$$;

-- Harden get_or_create_session function
CREATE OR REPLACE FUNCTION get_or_create_session(
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
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  SELECT id INTO v_session_id FROM attendance_sessions
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

-- Harden bulk_mark_attendance function
CREATE OR REPLACE FUNCTION bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec jsonb;
  v_student_id uuid;
  v_status text;
  v_note text;
  v_late_minutes int;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    v_student_id := (rec->>'student_id')::uuid;
    v_status := rec->>'status';
    v_note := rec->>'note';
    v_late_minutes := coalesce((rec->>'late_minutes')::int, 0);

    INSERT INTO attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    VALUES (p_session_id, v_student_id, v_status, v_note, v_late_minutes, auth.uid())
    ON CONFLICT (session_id, student_id) DO UPDATE
      SET status = excluded.status,
          note = excluded.note,
          late_minutes = excluded.late_minutes,
          marked_at = now(),
          marked_by = auth.uid();
  END LOOP;
END;
$$;

-- Harden student_attendance_calendar function
CREATE OR REPLACE FUNCTION student_attendance_calendar(
  p_student_id uuid,
  p_month int,
  p_year int
)
RETURNS TABLE(day date, status text, session_type text)
LANGUAGE sql
SECURITY DEFINER
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
