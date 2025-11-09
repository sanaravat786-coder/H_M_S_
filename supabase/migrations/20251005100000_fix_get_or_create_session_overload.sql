/*
  # [Function Overload Resolution for get_or_create_session]
  This migration resolves a function overloading ambiguity for `get_or_create_session`.

  ## Query Description:
  - This operation DROPS two potentially existing versions of the `get_or_create_session` function to resolve a naming conflict.
  - It then re-creates a single, definitive version of the function that correctly uses the `attendance_session_type` enum.
  - This is a safe, non-destructive operation for your data, but it is critical for fixing the attendance marking feature.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Low"
  - Requires-Backup: false
  - Reversible: false (but the old state was broken)

  ## Structure Details:
  - DROPS function `public.get_or_create_session(date, text)`
  - DROPS function `public.get_or_create_session(date, public.attendance_session_type)`
  - CREATES function `public.get_or_create_session(date, public.attendance_session_type)`

  ## Security Implications:
  - RLS Status: Not applicable
  - Policy Changes: No
  - Auth Requirements: None
  - The new function is hardened with `SECURITY DEFINER` and a fixed `search_path`.

  ## Performance Impact:
  - Indexes: None
  - Triggers: None
  - Estimated Impact: Negligible. Function execution will be very fast.
*/

-- Drop the incorrect version of the function that accepts `text`.
-- This is a primary cause of the error.
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text);

-- Drop the existing enum-based version as well, to ensure a clean re-creation.
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type);

-- Re-create the single, definitive version of the function.
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_session_type public.attendance_session_type
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
-- Hard-code the search path to prevent search path hijacking.
SET search_path = public
AS $$
DECLARE
    v_session_id uuid;
BEGIN
    -- Check if a session already exists for the given date and type.
    SELECT id
    INTO v_session_id
    FROM public.attendance_sessions
    WHERE date = p_date AND session_type = p_session_type;

    -- If no session exists, create a new one.
    IF v_session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (date, session_type)
        VALUES (p_date, p_session_type)
        RETURNING id INTO v_session_id;
    END IF;

    -- Return the ID of the existing or newly created session.
    RETURN v_session_id;
END;
$$;


-- Grant execution rights to authenticated users, which is required for them to call this SECURITY DEFINER function.
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type) TO authenticated;
