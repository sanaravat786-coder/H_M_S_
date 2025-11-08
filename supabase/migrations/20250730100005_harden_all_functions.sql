/*
# [Function Hardening]
This script re-defines all custom database functions to explicitly set the `search_path`. This is a critical security measure to prevent potential SQL injection vectors by ensuring functions do not rely on a mutable search path.

## Query Description:
This operation will replace the existing `handle_new_user` and `get_user_role` functions with updated, more secure versions. There is no risk to existing data as this only affects function definitions. This change is essential for resolving the "Function Search Path Mutable" security advisory.

## Metadata:
- Schema-Category: "Safe"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Modifies `public.handle_new_user()`
- Modifies `public.get_user_role(uuid)`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges to alter functions. This change hardens security by mitigating search_path attacks.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. This is a definition change with no runtime performance impact.
*/

-- Harden handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '';

-- Harden get_user_role function
CREATE OR REPLACE FUNCTION public.get_user_role(user_id uuid)
RETURNS TEXT AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role INTO user_role
  FROM public.profiles
  WHERE id = user_id;
  RETURN user_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = '';
