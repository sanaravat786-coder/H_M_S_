/*
# [Function and Trigger Re-creation]
This script resolves a migration conflict by dropping and re-creating custom database functions. It ensures all functions have a fixed search_path to address security warnings and corrects function definitions to prevent signature mismatch errors.

## Query Description:
This operation will temporarily remove and then restore the `handle_new_user` and `search_students` functions, along with the trigger that automatically creates user profiles. This is a safe procedure designed to fix the database schema without affecting user data. No data loss will occur.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Drops function: `public.handle_new_user()`
- Drops function: `public.search_students(text)`
- Drops trigger: `on_auth_user_created` on `auth.users`
- Re-creates function: `public.handle_new_user()`
- Re-creates function: `public.search_students(text)`
- Re-creates trigger: `on_auth_user_created` on `auth.users`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None
- Fixes "Function Search Path Mutable" security warning by setting a fixed `search_path` for all custom functions.

## Performance Impact:
- Indexes: None
- Triggers: Re-created
- Estimated Impact: Negligible. A brief moment where the functions are unavailable during migration.
*/

-- Step 1: Drop the trigger that depends on the function we are about to drop.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop the existing functions to allow for re-creation with updated definitions.
-- This is necessary to fix signature/return type conflicts and apply security hardening.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.search_students(text);


-- Step 3: Re-create the function to handle new user profile creation.
-- This version includes a fixed search_path to resolve security warnings.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'role'
  );
  RETURN new;
END;
$$;

-- Step 4: Re-create the trigger to call the handle_new_user function after a new user signs up.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- Step 5: Re-create the search function for students.
-- This version also includes a fixed search_path.
CREATE OR REPLACE FUNCTION public.search_students(search_term text)
RETURNS TABLE(id uuid, full_name text, email text, course text, contact text, created_at timestamptz)
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course, s.contact, s.created_at
  FROM public.students s
  WHERE s.full_name ILIKE '%' || search_term || '%'
     OR s.email ILIKE '%' || search_term || '%'
     OR s.course ILIKE '%' || search_term || '%';
END;
$$;
