/*
  # [Fix] User Profile Creation Trigger
  [This migration fixes a bug in the user profile creation process. The previous function was missing the 'mobile_number' field, causing an error when new users signed up.]

  ## Query Description: [This operation will replace the existing user creation logic. It drops the old trigger and function and replaces them with a corrected version. This is a safe operation and does not affect existing user data, but it is critical for new user registrations to succeed.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["High"]
  - Requires-Backup: [false]
  - Reversible: [false]
  
  ## Structure Details:
  - Drops trigger 'on_auth_user_created' on 'auth.users'.
  - Drops function 'public.create_user_profile()'.
  - Recreates function 'public.create_user_profile()' to correctly handle 'mobile_number'.
  - Recreates trigger 'on_auth_user_created' on 'auth.users'.
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [None]
  
  ## Performance Impact:
  - Indexes: [None]
  - Triggers: [Replaced]
  - Estimated Impact: [Negligible. Affects only new user creation.]
*/

-- Drop the existing trigger and function to avoid conflicts
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.create_user_profile();

-- Create the function to create a user profile
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.email,
    (NEW.raw_user_meta_data->>'role')::user_role,
    NEW.raw_user_meta_data->>'mobile_number'
  );
  RETURN NEW;
END;
$$;

-- Create the trigger to call the function on new user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_user_profile();
