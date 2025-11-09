/*
# [Function Fix] Fix get_or_create_session Type Mismatch
[This migration fixes a type mismatch error in the `get_or_create_session` function. The original function failed because it tried to compare a `text` input with an `attendance_session_type` enum column directly. This version correctly casts the text input to the enum type, resolving the "operator does not exist" error.]

## Query Description: [This operation safely drops and recreates a single database function. It modifies the function's internal logic to handle data types correctly, but does not alter any table data or schemas. There is no risk of data loss.]

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [false]

## Structure Details:
- Functions Dropped: public.get_or_create_session(date, text)
- Functions Created: public.get_or_create_session(date, text)

## Security Implications:
- RLS Status: [N/A]
- Policy Changes: [No]
- Auth Requirements: [The function is callable by authenticated users.]

## Performance Impact:
- Indexes: [N/A]
- Triggers: [N/A]
- Estimated Impact: [Negligible performance impact. This is a logic fix.]
*/

-- Drop the old, faulty function if it exists.
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text);

-- Recreate the function with the correct type casting.
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_session_type text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    session_id uuid;
BEGIN
    -- Attempt to find the session for the given date and type.
    -- Explicitly cast the text input to the attendance_session_type enum.
    SELECT id INTO session_id
    FROM attendance_sessions
    WHERE date = p_date AND session_type = p_session_type::public.attendance_session_type;

    -- If the session does not exist, create it.
    IF session_id IS NULL THEN
        INSERT INTO attendance_sessions (date, session_type)
        VALUES (p_date, p_session_type::public.attendance_session_type)
        RETURNING id INTO session_id;
    END IF;

    -- Return the existing or new session ID.
    RETURN session_id;
END;
$$;

-- Grant execute permission to the authenticated role.
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, text) TO authenticated;
