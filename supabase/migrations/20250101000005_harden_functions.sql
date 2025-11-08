/*
# [Security Hardening] Set Function Search Path
This migration hardens the security of the database functions by setting a fixed `search_path`. This prevents potential security vulnerabilities related to schema search path manipulation and addresses the "Function Search Path Mutable" security advisory.

## Query Description:
This operation modifies the configuration of existing database functions (`get_user_role` and `handle_new_user`). It does not alter any table structures or data. It is a safe and recommended security improvement.

## Metadata:
- Schema-Category: ["Safe", "Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Functions affected:
  - `get_user_role()`
  - `handle_new_user()`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges to alter functions.
- Fixes: Addresses the "Function Search Path Mutable" warning by restricting the function's schema search path to 'public', preventing potential hijacking.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. May slightly improve performance by providing a more direct path for schema object resolution.
*/

ALTER FUNCTION public.get_user_role()
SET search_path = public;

ALTER FUNCTION public.handle_new_user()
SET search_path = public;
