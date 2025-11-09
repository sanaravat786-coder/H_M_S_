/*
          # [Operation Name]
          Recreate and Harden Attendance Functions

          ## Query Description: [This operation safely drops and recreates two critical database functions related to attendance: `get_or_create_session` and `get_monthly_attendance_for_student`. The new versions include explicit security settings (`SECURITY DEFINER`) and a fixed `search_path` to prevent context-related errors and address security advisories. The `get_monthly_attendance_for_student` function is also simplified to ensure it correctly returns a `NULL` status for dates without an attendance record, fixing the data type mismatch errors that were occurring on the "My Attendance" page. This is a safe, reversible operation that does not affect stored data.]
          
          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Functions being affected:
            - `public.get_or_create_session(date, session_type)`
            - `public.get_monthly_attendance_for_student(uuid, integer, integer)`
          
          ## Security Implications:
          - RLS Status: Not Applicable
          - Policy Changes: No
          - Auth Requirements: Functions are granted to the `authenticated` role.
          - `SECURITY DEFINER` is used to ensure functions run with the owner's permissions, providing consistent behavior.
          - `search_path` is explicitly set to `public, pg_temp` to mitigate search path hijacking vulnerabilities.
          
          ## Performance Impact:
          - Indexes: None
          - Triggers: None
          - Estimated Impact: Negligible. This operation only redefines function logic and should not impact query performance.
          */

-- Drop existing functions if they exist to ensure a clean recreation
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.session_type);
DROP FUNCTION IF EXISTS public.get_monthly_attendance_for_student(uuid, integer, integer);

-- Recreate get_or_create_session function with security hardening
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_session_type public.session_type)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  -- Check if a session already exists for the given date and type
  SELECT id INTO v_session_id
  FROM public.attendance_sessions
  WHERE date = p_date AND session = p_session_type;

  -- If not found, create a new session
  IF v_session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (date, session)
    VALUES (p_date, p_session_type)
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

-- Recreate get_monthly_attendance_for_student function with security hardening and correct return type
CREATE OR REPLACE FUNCTION public.get_monthly_attendance_for_student(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status public.attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.date,
    ar.status
  FROM public.attendance_sessions s
  LEFT JOIN public.attendance_records ar
    ON s.id = ar.session_id AND ar.student_id = p_student_id
  WHERE
    EXTRACT(MONTH FROM s.date) = p_month
    AND EXTRACT(YEAR FROM s.date) = p_year;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.session_type) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_monthly_attendance_for_student(uuid, integer, integer) TO authenticated;
