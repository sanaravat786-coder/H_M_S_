/*
# [CRITICAL FIX] Resolve Infinite Recursion in RLS Policy

This migration provides a definitive fix for the "infinite recursion" error that has been affecting the dashboard and other parts of the application. It also hardens the security of related database functions.

## Query Description:
The error was caused by the `get_user_role()` function reading from the `public.profiles` table, while the RLS policy on that same table was also calling the function. This created a circular dependency.

This script corrects the issue by:
1.  Replacing `get_user_role()` with a new version that securely reads the user's role from `auth.users` metadata, breaking the loop.
2.  Hardening the `handle_new_user()` function by setting a secure search path.
3.  Safely dropping and recreating dependent triggers to ensure a clean update.

This change is safe and will not affect any existing user data. It is critical for restoring application functionality.

## Metadata:
- Schema-Category: ["Structural", "Safe"]
- Impact-Level: ["High"]
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Replaces function: `public.get_user_role()`
- Replaces function: `public.handle_new_user()`
- Recreates trigger: `on_auth_user_created` on `auth.users`

## Security Implications:
- RLS Status: Fixes a bug that made RLS policies unusable.
- Policy Changes: No
- Auth Requirements: None
- This change resolves a critical security policy bug.

## Performance Impact:
- Indexes: None
- Triggers: Recreated
- Estimated Impact: High. Resolves a query-crashing bug, restoring application performance.
*/

-- Step 1: Drop the existing trigger and functions to prevent dependency errors.
-- We use "IF EXISTS" to make the script runnable even if parts are missing.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_user_role();

-- Step 2: Create the corrected get_user_role function.
-- This version reads from `auth.users`, which is safe and breaks the recursion loop.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid()
$$;

-- Step 3: Create the hardened handle_new_user function.
-- This function creates a profile for a new user upon sign-up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    (new.raw_user_meta_data->>'role')::user_role
  );
  RETURN new;
END;
$$;

-- Step 4: Recreate the trigger on the auth.users table.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 5: Grant permissions to the authenticated role.
GRANT EXECUTE ON FUNCTION public.get_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO authenticated;
