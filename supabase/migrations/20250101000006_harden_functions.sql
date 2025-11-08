/*
# [Function Security Hardening]
[This operation hardens the security of existing database functions by setting a fixed search_path. This prevents potential hijacking attacks in multi-schema environments and resolves the "Function Search Path Mutable" security advisory.]

## Query Description: [This operation updates the `get_user_role` and `handle_new_user` functions to explicitly set their `search_path` to 'public'. This is a non-destructive security enhancement and has no impact on existing data or application functionality. It is a recommended best practice for PostgreSQL functions.]

## Metadata:
- Schema-Category: ["Safe", "Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Functions affected: `get_user_role()`, `handle_new_user()`

## Security Implications:
- RLS Status: [No Change]
- Policy Changes: [No]
- Auth Requirements: [Admin privileges to alter functions]
- Mitigates: Potential for search_path manipulation attacks.

## Performance Impact:
- Indexes: [No Change]
- Triggers: [No Change]
- Estimated Impact: [None. This is a metadata change on the function definition.]
*/

ALTER FUNCTION public.get_user_role() SET search_path = 'public';

ALTER FUNCTION public.handle_new_user() SET search_path = 'public';
