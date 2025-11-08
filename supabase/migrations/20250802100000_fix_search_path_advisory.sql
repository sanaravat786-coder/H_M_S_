/*
# [Fix Function Search Path]
This operation secures the `handle_new_user` function by setting a fixed `search_path`. This is a security best practice that prevents potential context-switching attacks (e.g., hijacking) by ensuring the function always looks for objects in the expected schemas.

## Query Description:
This query modifies an existing function to make it more secure. It does not alter any data or table structures. There is no risk to existing data.

## Metadata:
- Schema-Category: ["Safe", "Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Function affected: `public.handle_new_user`

## Security Implications:
- RLS Status: Not applicable
- Policy Changes: No
- Auth Requirements: No
- Mitigates: `Function Search Path Mutable` warning by hardening the function against search path manipulation.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. May provide a minor performance improvement in some cases.
*/

-- Secure the handle_new_user function by setting a fixed search path
ALTER FUNCTION public.handle_new_user()
SET search_path = public;
