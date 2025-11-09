/*
          # [Function Hardening]
          This operation secures the `create_user_profile_if_not_exists` function by setting a fixed, empty `search_path`.

          ## Query Description: [This is a non-destructive security enhancement. It prevents the function from being manipulated by malicious actors who might alter the session's search path. It has no impact on existing data and is safe to apply.]
          
          ## Metadata:
          - Schema-Category: "Security"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Function `create_user_profile_if_not_exists` is modified.
          
          ## Security Implications:
          - RLS Status: Not changed
          - Policy Changes: No
          - Auth Requirements: None
          
          ## Performance Impact:
          - Indexes: None
          - Triggers: None
          - Estimated Impact: Negligible.
          */

CREATE OR REPLACE FUNCTION public.create_user_profile_if_not_exists()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_role text;
  v_full_name text;
  v_mobile_number text;
BEGIN
  -- Check if a profile already exists for the new user
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id) THEN
    -- Get user metadata from auth.users
    SELECT
      raw_user_meta_data ->> 'role',
      raw_user_meta_data ->> 'full_name',
      raw_user_meta_data ->> 'mobile_number'
    INTO v_user_role, v_full_name, v_mobile_number
    FROM auth.users
    WHERE id = v_user_id;

    -- Insert into public.profiles
    INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
    VALUES (
      v_user_id,
      v_full_name,
      (SELECT email FROM auth.users WHERE id = v_user_id),
      v_user_role,
      v_mobile_number
    );

    -- If the user is a student, also insert into public.students
    IF v_user_role = 'Student' THEN
      INSERT INTO public.students (id, full_name, email, contact)
      VALUES (
        v_user_id,
        v_full_name,
        (SELECT email FROM auth.users WHERE id = v_user_id),
        v_mobile_number
      );
    END IF;
  END IF;
END;
$$;
