/*
  # [Function Cleanup] Resolve get_or_create_session conflict
  This migration resolves a function overloading conflict by removing an outdated version of the `get_or_create_session` function that incorrectly accepted a `text` parameter for the session type.

  ## Query Description: This operation drops a single, unused function to resolve a critical ambiguity. It is a safe, non-destructive change that will not impact any data. It is essential for fixing the attendance marking feature.
  
  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Low"
  - Requires-Backup: false
  - Reversible: false (The dropped function was incorrect and should not be restored)
  
  ## Structure Details:
  - Drops function: `get_or_create_session(date, text)`
  
  ## Security Implications:
  - RLS Status: Not applicable
  - Policy Changes: No
  - Auth Requirements: None
  
  ## Performance Impact:
  - Indexes: None
  - Triggers: None
  - Estimated Impact: None. Resolves an error, allowing normal function execution.
*/
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text);

/*
  # [Function Hardening] Recreate get_or_create_session
  This re-creates the `get_or_create_session` function to ensure it uses the correct `attendance_session_type` enum and has the proper security settings.

  ## Query Description: This operation ensures the core function for attendance tracking is correctly defined. It is safe to run and will not result in data loss.
  
  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Low"
  - Requires-Backup: false
  - Reversible: true
  
  ## Structure Details:
  - Function: `get_or_create_session(date, attendance_session_type)`
  
  ## Security Implications:
  - RLS Status: Not applicable
  - Policy Changes: No
  - Auth Requirements: `authenticated` role
  
  ## Performance Impact:
  - Indexes: None
  - Triggers: None
  - Estimated Impact: Low.
*/
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
  v_session_id uuid;
BEGIN
  -- Attempt to find an existing session
  SELECT id INTO v_session_id
  FROM attendance_sessions
  WHERE date = p_date AND session_type = p_session_type;

  -- If no session is found, create a new one
  IF v_session_id IS NULL THEN
    INSERT INTO attendance_sessions (date, session_type, created_by)
    VALUES (p_date, p_session_type, auth.uid())
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type) TO authenticated;
