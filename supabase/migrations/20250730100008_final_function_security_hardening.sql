/*
# [SECURITY HARDENING] Final Function Security Update

This migration script provides a definitive fix for the persistent 'Function Search Path Mutable' security warning. It operates by completely removing all custom functions and their dependencies, and then recreating them from a clean slate with the required security configurations. This ensures all potential vulnerabilities related to this warning are addressed.

## Query Description:
This operation will temporarily drop and then recreate the user profile creation trigger and all associated database functions. There is a very minimal risk of a new user signing up in the few milliseconds between the trigger being dropped and recreated, which might result in their profile not being created automatically. This is highly unlikely in a development environment. No existing data will be lost.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: false

## Structure Details:
- **Dropped Objects:**
  - TRIGGER: `on_auth_user_created` on `auth.users`
  - FUNCTION: `public.handle_new_user()`
  - FUNCTION: `public.search_students(text)`
- **Recreated Objects:**
  - FUNCTION: `public.handle_new_user()` (with `SET search_path`)
  - FUNCTION: `public.search_students(text)` (with `SET search_path`)
  - TRIGGER: `on_auth_user_created` on `auth.users`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: This script hardens security by setting a fixed `search_path` for all custom functions, mitigating potential SQL injection vectors as flagged by the security advisory.

## Performance Impact:
- Indexes: None
- Triggers: The user creation trigger is temporarily removed and re-added.
- Estimated Impact: Negligible performance impact.
*/

-- Step 1: Drop the trigger that depends on the function. This is critical to avoid dependency errors.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop all custom functions to ensure a clean slate.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.search_students(p_search_term text);

-- Step 3: Recreate the function to handle new user profile creation, with security hardening.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
-- Set a fixed, safe search path to address the security warning.
SET search_path = 'public'
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

-- Step 4: Recreate the student search function, with security hardening.
CREATE OR REPLACE FUNCTION public.search_students(p_search_term TEXT)
RETURNS TABLE(id UUID, full_name TEXT, email TEXT, course TEXT, contact TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
-- Set a fixed, safe search path.
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course, s.contact, s.created_at
  FROM public.students s
  WHERE s.full_name ILIKE '%' || p_search_term || '%'
     OR s.email ILIKE '%' || p_search_term || '%';
END;
$$;

-- Step 5: Recreate the trigger and link it to the new, hardened function.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();
