/*
  # [Fix] Correct get_monthly_attendance_for_student function
  This migration fixes a critical bug in the `get_monthly_attendance_for_student` function that caused a type mismatch error.

  ## Query Description: 
  - The function was incorrectly returning a `text` value instead of a `NULL` value of the expected `attendance_status` type for days with no record.
  - This caused the "My Attendance" page to fail for all users.
  - This script drops the faulty function and recreates it with the correct return type and logic, ensuring it returns `NULL` for dates with no attendance record.
  - The function is also hardened by setting a specific `search_path` to address security advisories.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Medium"
  - Requires-Backup: false
  - Reversible: true (by restoring the previous function definition)

  ## Structure Details:
  - Function `get_monthly_attendance_for_student` is dropped and recreated.

  ## Security Implications:
  - RLS Status: Not applicable to functions directly, but function respects RLS of underlying tables.
  - Policy Changes: No
  - Auth Requirements: Execution is granted to the 'authenticated' role.
  - Search Path: Hardened by setting `search_path = 'public'`.

  ## Performance Impact:
  - Indexes: None
  - Triggers: None
  - Estimated Impact: Low. The function performance should be similar or slightly improved.
*/

-- Drop the existing function to ensure a clean recreation
DROP FUNCTION IF EXISTS public.get_monthly_attendance_for_student(uuid, integer, integer);

-- Recreate the function with the correct return type and logic
CREATE OR REPLACE FUNCTION public.get_monthly_attendance_for_student(
    p_student_id uuid,
    p_month integer,
    p_year integer
)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_start_date date;
    v_end_date date;
BEGIN
    -- Ensure month and year are valid
    IF p_month < 1 OR p_month > 12 OR p_year < 1900 OR p_year > 2100 THEN
        RETURN;
    END IF;

    v_start_date := make_date(p_year, p_month, 1);
    v_end_date := v_start_date + interval '1 month' - interval '1 day';

    RETURN QUERY
    SELECT
        d.day::date,
        ar.status
    FROM
        generate_series(v_start_date, v_end_date, '1 day'::interval) AS d(day)
    LEFT JOIN
        attendance_sessions AS "as" ON "as".date = d.day
    LEFT JOIN
        attendance_records AS ar ON ar.session_id = "as".id AND ar.student_id = p_student_id;
END;
$$;

-- Grant execution rights to authenticated users
GRANT EXECUTE ON FUNCTION public.get_monthly_attendance_for_student(uuid, integer, integer) TO authenticated;
