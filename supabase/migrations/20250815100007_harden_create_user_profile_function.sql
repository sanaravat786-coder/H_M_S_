/*
# [Function Hardening] Fix Mutable Search Path for User Profile Creation

## Query Description: This operation will recreate the `create_user_profile_if_not_exists` function to explicitly set its `search_path`. This is a critical security measure that prevents potential hijacking of the function by malicious actors who might create objects with the same name in other schemas. This change is non-destructive and enhances the security of the automatic user profile creation process.

## Metadata:
- Schema-Category: ["Security", "Safe"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Function `create_user_profile_if_not_exists()` will be dropped and recreated.

## Security Implications:
- RLS Status: Not applicable
- Policy Changes: No
- Auth Requirements: None
- Mitigates: Search Path Hijacking vulnerability.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible.
*/

-- Drop the existing function to recreate it safely
DROP FUNCTION IF EXISTS public.create_user_profile_if_not_exists();

-- Recreate the function with a secure search path
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
  v_email text;
BEGIN
  -- Check if profile already exists to prevent duplicates
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = v_user_id) THEN
    RETURN;
  END IF;

  -- Get all required data from auth.users in one go for efficiency
  SELECT
    raw_user_meta_data->>'full_name',
    raw_user_meta_data->>'mobile_number',
    raw_user_meta_data->>'role',
    email
  INTO v_full_name, v_mobile_number, v_user_role, v_email
  FROM auth.users
  WHERE id = v_user_id;

  -- Insert into public.profiles
  INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
  VALUES (
    v_user_id,
    v_full_name,
    v_email,
    v_user_role,
    v_mobile_number
  );

  -- If the user is a student, also create an entry in the public.students table
  IF v_user_role = 'Student' THEN
    INSERT INTO public.students (id, full_name, email, contact)
    VALUES (
      v_user_id,
      v_full_name,
      v_email,
      v_mobile_number
    );
  END IF;

END;
$$;
