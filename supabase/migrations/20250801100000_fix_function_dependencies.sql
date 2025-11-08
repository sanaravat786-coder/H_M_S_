/*
          # [Operation] Drop and Recreate Functions with Dependencies
          This script resolves a dependency conflict by dropping and recreating database functions and their associated triggers. It specifically targets the `handle_new_user` and `search_students` functions.

          ## Query Description: This operation will first drop the trigger that automatically creates user profiles. It will then drop the old database functions. Finally, it will recreate these functions with hardened security settings (explicit `search_path`) and re-establish the trigger. This is a safe operation as it only redefines function logic and does not alter any table data. It is necessary to fix both the migration error and the underlying security warnings.
          
          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Drops Trigger: `on_auth_user_created` on `auth.users`
          - Drops Functions: `public.handle_new_user()`, `public.search_students(text)`
          - Recreates Functions: `public.handle_new_user()`, `public.search_students(text)`
          - Recreates Trigger: `on_auth_user_created` on `auth.users`
          
          ## Security Implications:
          - RLS Status: Not directly affected, but the recreated functions will respect existing RLS.
          - Policy Changes: No.
          - Auth Requirements: None for this script.
          - Fixes `Function Search Path Mutable` warning by setting an explicit `search_path`.
          
          ## Performance Impact:
          - Indexes: None.
          - Triggers: Temporarily drops and recreates one trigger.
          - Estimated Impact: Negligible. A brief moment where new user sign-ups would not create a profile, but this script executes fast enough to make that risk minimal.
          */

-- Step 1: Drop the trigger that depends on the function.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop the functions. This will now succeed as the dependency is removed.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.search_students(text);

-- Step 3: Recreate the handle_new_user function with security best practices.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  RETURN new;
END;
$$;

-- Step 4: Recreate the search_students function with security best practices.
CREATE OR REPLACE FUNCTION public.search_students(search_term text)
RETURNS TABLE(id uuid, full_name text, email text, course text, contact text, created_at timestamptz)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course, s.contact, s.created_at
  FROM public.students s
  WHERE s.full_name ILIKE '%' || search_term || '%';
END;
$$;
ALTER FUNCTION public.search_students(text) SET search_path = public;


-- Step 5: Recreate the trigger on the auth.users table.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
