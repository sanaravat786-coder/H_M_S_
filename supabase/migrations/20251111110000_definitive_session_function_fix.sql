/*
          # [Critical Function Fix] Definitive fix for get_or_create_session
          [This migration resolves a persistent database error by removing all conflicting versions of the `get_or_create_session` function and replacing them with a single, type-safe version. This will fix the "operator does not exist: text = attendance_session_type" error.]

          ## Query Description: [This operation will drop and recreate a key database function used for marking attendance. It is designed to be non-destructive to data. The change ensures that data sent from the application is correctly interpreted by the database by accepting a text value and casting it to the correct type internally, preventing future errors.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops all existing versions of the function: `get_or_create_session`.
          - Creates a new, single version of `get_or_create_session` that accepts the session type as `text` and correctly casts it to the `attendance_session_type` enum. It also supports optional parameters for more complex session lookups.
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [No]
          - Auth Requirements: [The function uses `auth.uid()` and is set as `SECURITY DEFINER`.]
          
          ## Performance Impact:
          - Indexes: [No change]
          - Triggers: [No change]
          - Estimated Impact: [Low.]
          */

-- Drop all possible conflicting versions of the function to ensure a clean state.
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, uuid, text, text);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type, text, uuid, text, text);

-- Create the single, definitive version of the function.
-- It accepts the session type as `text` and casts it internally for safety.
-- It also includes optional parameters for more complex session types.
CREATE OR REPLACE FUNCTION public.get_or_create_session(
  p_date date,
  p_session_type text,
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
  v_session_type_enum public.attendance_session_type;
BEGIN
  -- Cast the input text to the ENUM type. This will error if the value is invalid.
  v_session_type_enum := p_session_type::public.attendance_session_type;

  -- Try to find an existing session
  SELECT id INTO v_session_id
  FROM public.attendance_sessions
  WHERE session_date = p_date 
    AND session_type = v_session_type_enum
    AND coalesce(block, '') = coalesce(p_block, '')
    AND coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND coalesce(course, '') = coalesce(p_course, '')
    AND coalesce(year, '') = coalesce(p_year, '');

  -- If no session is found, create a new one
  IF v_session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (session_date, session_type, block, room_id, course, year, created_by)
    VALUES (p_date, v_session_type_enum, p_block, p_room_id, p_course, p_year, auth.uid())
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

-- Grant permissions to the new function
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, text, text, uuid, text, text) TO authenticated;
