/*
# [Function Security Hardening]
Updates the `handle_new_user` function to explicitly set the `search_path`. This is a security best practice that prevents potential context-switching vulnerabilities by ensuring the function always operates within the intended `public` schema.

## Query Description: This operation modifies a database function to enhance security. It is a non-destructive change and has no impact on existing data. By setting a fixed search path, it mitigates risks associated with malicious schema manipulation.

## Metadata:
- Schema-Category: "Safe"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Function affected: `public.handle_new_user()`

## Security Implications:
- RLS Status: Not applicable
- Policy Changes: No
- Auth Requirements: Admin privileges to alter functions.
- Fixes: Resolves the "Function Search Path Mutable" security warning.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. This is a metadata change for the function definition.
*/
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.raw_user_meta_data ->> 'role'
  );
  RETURN NEW;
END;
$$;
