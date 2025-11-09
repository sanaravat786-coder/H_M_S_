/*
          # [Function Re-creation] Fix get_or_create_session function
          [This migration drops and recreates the 'get_or_create_session' function to resolve a 'cannot remove parameter defaults' error. The new function includes security hardening by setting a fixed search_path.]

          ## Query Description: [This operation will temporarily drop the 'get_or_create_session' function and immediately recreate it with a secure configuration. There is a minimal risk of failure if the function is in use during the migration, but it is generally safe. No data will be lost.]
          
          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Drops function: `get_or_create_session(date, text, text, integer)`
          - Creates function: `get_or_create_session(date, text, text, integer)`
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [None]
          - Triggers: [None]
          - Estimated Impact: [Negligible performance impact. This is a metadata change.]
          */

-- Drop the existing function as hinted by the error
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);

-- Recreate the function with the correct signature and security settings
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_type text,
    p_course text DEFAULT NULL,
    p_year integer DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    session_uuid uuid;
BEGIN
    -- Try to find an existing session
    SELECT id INTO session_uuid
    FROM attendance_sessions
    WHERE attendance_date = p_date
      AND session_type = p_type
      AND (get_or_create_session.p_course IS NULL OR attendance_sessions.course = get_or_create_session.p_course)
      AND (get_or_create_session.p_year IS NULL OR attendance_sessions.year = get_or_create_session.p_year)
    LIMIT 1;

    -- If not found, create a new one
    IF session_uuid IS NULL THEN
        INSERT INTO attendance_sessions (attendance_date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_uuid;
    END IF;

    RETURN session_uuid;
END;
$$;
