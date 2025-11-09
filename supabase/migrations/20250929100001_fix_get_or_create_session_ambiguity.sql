/*
  # [Function Fix] Resolve get_or_create_session Ambiguity
  This migration resolves a function overloading conflict by removing duplicate definitions of `get_or_create_session` and recreating a single, secure version.

  ## Query Description:
  - This operation drops two potentially conflicting versions of the `get_or_create_session` function.
  - It then creates a single, definitive version that correctly handles finding or creating an attendance session.
  - This is a safe operation as it only affects function definitions and does not alter any table data. It is crucial for fixing the "Could not choose the best candidate function" error.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Low"
  - Requires-Backup: false
  - Reversible: false

  ## Structure Details:
  - Drops: `get_or_create_session(date, public.attendance_session_type)`, `get_or_create_session(date, public.session_type)`
  - Creates: `get_or_create_session(p_date date, p_session_type public.attendance_session_type)`

  ## Security Implications:
  - RLS Status: Not applicable
  - Policy Changes: No
  - Auth Requirements: None
  - The new function is defined with `SECURITY DEFINER` and a fixed `search_path` to address security warnings.

  ## Performance Impact:
  - Indexes: None
  - Triggers: None
  - Estimated Impact: Negligible. Function execution may be slightly faster due to resolved ambiguity.
*/

-- Drop the conflicting functions to resolve ambiguity.
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.session_type);

-- Recreate the function with a definitive signature and security settings.
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_session_type public.attendance_session_type
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    session_id uuid;
BEGIN
    -- Attempt to find an existing session for the given date and type
    SELECT id INTO session_id
    FROM attendance_sessions
    WHERE date = p_date AND session_type = p_session_type;

    -- If no session is found, create a new one
    IF session_id IS NULL THEN
        INSERT INTO attendance_sessions (date, session_type)
        VALUES (p_date, p_session_type)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;
