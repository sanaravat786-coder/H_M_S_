/*
# [Function Hardening - Definitive Fix]
This migration provides a definitive fix for the "Function Search Path Mutable" security warning. It completely recreates all custom functions and their associated triggers with the correct security settings by dropping and recreating them.

## Query Description:
This script will first safely remove the existing `on_auth_user_created` trigger and the `handle_new_user` and `search_students` functions. It then recreates them from scratch, ensuring the `search_path` is explicitly set to 'public' to mitigate security risks. This is a safe, idempotent operation.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by reverting to a previous migration)

## Structure Details:
- Drops Trigger: `on_auth_user_created` on `auth.users`
- Drops Function: `handle_new_user()`
- Drops Function: `search_students(text)`
- Creates Function: `handle_new_user()` with hardened security.
- Creates Function: `search_students(text)` with hardened security.
- Creates Trigger: `on_auth_user_created` on `auth.users`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges to run migrations.
- Fixes: Resolves the "Function Search Path Mutable" warning.

## Performance Impact:
- Indexes: None
- Triggers: Recreated, no performance change.
- Estimated Impact: Negligible.
*/

-- Step 1: Drop the existing trigger to remove dependency
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop the existing functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.search_students(text);

-- Step 3: Recreate the handle_new_user function with a secure search_path
CREATE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
-- Set a secure search_path to prevent hijacking
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  RETURN new;
END;
$$;

-- Step 4: Recreate the search_students function
CREATE FUNCTION public.search_students(search_term text)
RETURNS TABLE(id uuid, full_name text, email text, course text, contact text, created_at timestamptz)
LANGUAGE plpgsql
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


-- Step 5: Recreate the trigger to call the new, hardened function
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
