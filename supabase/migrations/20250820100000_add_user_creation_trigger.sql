/*
          # [OPERATION] Create User Profile Trigger
          This script creates an automated trigger to populate the `profiles` and `students` tables after a new user signs up through Supabase Auth.

          ## Query Description:
          This operation is safe and essential for the application's functionality. It ensures that every new user in `auth.users` gets a corresponding record in `public.profiles`. If the user's role is 'Student', it also creates a record in `public.students`. This fixes the "Database error saving new user" bug by ensuring profile data exists when the application needs it. There is no risk to existing data.

          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true (by dropping the trigger and function)

          ## Structure Details:
          - Creates function: `public.handle_new_user()`
          - Creates trigger: `on_auth_user_created` on `auth.users` table

          ## Security Implications:
          - RLS Status: Not changed.
          - Policy Changes: No.
          - Auth Requirements: The function is `SECURITY DEFINER` to allow writing to public tables on behalf of the user. The `search_path` is set to `public` to prevent security vulnerabilities.

          ## Performance Impact:
          - Indexes: None.
          - Triggers: Adds one `AFTER INSERT` trigger to `auth.users`. The performance impact is negligible as it's a lightweight insert operation that only runs on new user creation.
          - Estimated Impact: Low.
          */

-- 1. Create the function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Create a profile for every new user
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'role',
    NEW.raw_user_meta_data->>'mobile_number'
  );

  -- If the new user is a student, also create an entry in the students table
  IF (NEW.raw_user_meta_data->>'role' = 'Student') THEN
    INSERT INTO public.students (id, full_name, email, contact)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data->>'full_name',
        NEW.email,
        NEW.raw_user_meta_data->>'mobile_number'
    );
  END IF;
  
  RETURN NEW;
END;
$$;

-- 2. Create the trigger to execute the function after a new user is created in auth.users
-- Drop the trigger first if it exists to ensure a clean setup
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- 3. Add a comment to confirm the trigger is in place
COMMENT ON TRIGGER on_auth_user_created ON auth.users IS 'Ensures new users have a corresponding profile and student record created.';
