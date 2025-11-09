/*
# [Fix] Correct `get_monthly_attendance_for_student` Return Type
This migration corrects a type mismatch in the `get_monthly_attendance_for_student` function. The function was incorrectly returning a `text` value for days without an attendance entry, while its definition requires an `attendance_status` enum type. This caused a "structure of query does not match function result type" error (code: 42804) when calling the function from the client.

## Query Description: This operation will safely replace the existing function definition. It corrects the `SELECT` statement within the function to return `NULL` instead of a text string for dates with no attendance record. This change is non-destructive and resolves the client-side error without affecting existing data.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Function modified: `get_monthly_attendance_for_student(p_student_id uuid, p_month integer, p_year integer)`

## Security Implications:
- RLS Status: N/A
- Policy Changes: No
- Auth Requirements: The function's security definer and search path are preserved.

## Performance Impact:
- Indexes: N/A
- Triggers: N/A
- Estimated Impact: Negligible. The function logic is slightly simplified.
*/
CREATE OR REPLACE FUNCTION public.get_monthly_attendance_for_student(p_student_id uuid, p_month integer, p_year integer)
 RETURNS TABLE(day date, status public.attendance_status)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_start_date date;
    v_end_date date;
BEGIN
    v_start_date := make_date(p_year, p_month, 1);
    v_end_date := v_start_date + interval '1 month' - interval '1 day';

    RETURN QUERY
    SELECT
        d.day::date,
        ar.status
    FROM
        generate_series(v_start_date, v_end_date, '1 day'::interval) AS d(day)
    LEFT JOIN
        attendance_sessions AS "as" ON "as".date = d.day::date
    LEFT JOIN
        attendance_records AS ar ON ar.session_id = "as".id AND ar.student_id = p_student_id
    ORDER BY
        d.day;
END;
$function$;
