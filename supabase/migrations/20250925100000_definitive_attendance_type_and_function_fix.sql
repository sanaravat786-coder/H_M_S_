/*
# [Definitive Fix] Create `session_type` and Recreate Attendance Functions
This migration fixes a critical error where the `session_type` custom data type was missing, causing attendance-related functions to fail.

## Query Description:
This script performs the following actions to create a stable attendance module:
1.  **Creates `session_type`:** A new ENUM type (`'morning'`, `'evening'`) is created, which is essential for the attendance system.
2.  **Recreates `get_or_create_session`:** This function is rebuilt to correctly use the new `session_type` and is hardened for security.
3.  **Recreates `get_monthly_attendance_for_student`:** This function is also rebuilt for correctness and security, ensuring it returns the proper data types.
This operation is safe and will not result in data loss. It corrects the database schema to match the application's requirements.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: false

## Structure Details:
- **Types Created:** `public.session_type`
- **Functions Dropped:** `get_or_create_session`, `get_monthly_attendance_for_student`
- **Functions Created:** `get_or_create_session`, `get_monthly_attendance_for_student`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None
- **Security Hardening:** Both functions have their `search_path` explicitly set to `public` to mitigate search path vulnerabilities, addressing the "Function Search Path Mutable" security advisory.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Low. Function recreation is a fast, metadata-only operation.
*/

-- Drop existing functions if they exist to ensure a clean slate
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.session_type);
DROP FUNCTION IF EXISTS public.get_monthly_attendance_for_student(uuid, integer, integer);

-- Drop the type if it exists, for idempotency
DROP TYPE IF EXISTS public.session_type;

-- Create the required ENUM type for session
CREATE TYPE public.session_type AS ENUM ('morning', 'evening');

-- Recreate the function to get or create an attendance session
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_session_type public.session_type
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session_id uuid;
BEGIN
    -- Attempt to find an existing session
    SELECT id INTO v_session_id
    FROM attendance_sessions
    WHERE date = p_date AND session_type = p_session_type;

    -- If not found, create a new one
    IF v_session_id IS NULL THEN
        INSERT INTO attendance_sessions (date, session_type)
        VALUES (p_date, p_session_type)
        RETURNING id INTO v_session_id;
    END IF;

    RETURN v_session_id;
END;
$$;

-- Recreate the function to get monthly attendance for a student
CREATE OR REPLACE FUNCTION public.get_monthly_attendance_for_student(
    p_student_id uuid,
    p_month integer,
    p_year integer
)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Ensure the calling user is either the student themselves or an admin/staff
    IF (
        auth.uid() <> p_student_id AND
        NOT (
            SELECT is_admin OR is_staff FROM public.get_user_roles(auth.uid())
        )
    ) THEN
        RAISE EXCEPTION 'User does not have permission to view this attendance.';
    END IF;

    RETURN QUERY
    SELECT
        s.date,
        ar.status
    FROM
        attendance_sessions s
    LEFT JOIN
        attendance_records ar ON s.id = ar.session_id AND ar.student_id = p_student_id
    WHERE
        EXTRACT(MONTH FROM s.date) = p_month
        AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY
        s.date;
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.session_type) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_monthly_attendance_for_student(uuid, integer, integer) TO authenticated;
