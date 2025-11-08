/*
# [Operation Name]
Fix Function Recursion and Harden Security

## Query Description: [This operation updates existing database functions to resolve a critical recursion error and improve security. It modifies the `get_user_role` function to prevent an infinite loop by changing how it fetches user roles. It also hardens all custom functions by setting a fixed `search_path`, addressing a security advisory. This change is safe and does not affect any table data.]

## Metadata:
- Schema-Category: ["Safe"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Functions affected: `get_user_role`, `handle_new_user`

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [No]
- Auth Requirements: [None]

## Performance Impact:
- Indexes: [None]
- Triggers: [None]
- Estimated Impact: [Negligible performance impact. This change improves query stability.]
*/

-- Fixes the infinite recursion by getting the role from auth.users metadata instead of public.profiles
-- Also sets the search_path to address the security warning.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT raw_user_meta_data->>'role'
    FROM auth.users
    WHERE id = auth.uid()
  );
END;
$$;

-- Hardens the handle_new_user function by setting the search_path.
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
    new.raw_user_meta_data->>'role'
  );
  RETURN new;
END;
$$;
