/*
  # [Function] Create get_user_roles function
  This migration creates a new function `get_user_roles` which is required by other parts of the application's database logic. This function retrieves a user's role from the `profiles` table based on their user ID.

  ## Query Description:
  - This operation creates a new PostgreSQL function `get_user_roles(uuid)`.
  - It is a safe, non-destructive operation that adds new functionality.
  - It depends on the `profiles` table having an `id` (uuid) and `role` (text) column.
  - The function is defined with `SECURITY DEFINER` to allow it to be used within other functions that may have elevated privileges, but it only performs a read operation on the `profiles` table.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Low"
  - Requires-Backup: false
  - Reversible: true (the function can be dropped)

  ## Structure Details:
  - Creates function: `public.get_user_roles(p_user_id uuid)`

  ## Security Implications:
  - RLS Status: Not applicable to function creation itself.
  - Policy Changes: No
  - Auth Requirements: The function is `SECURITY DEFINER`, which means it runs with the permissions of the user who defined it (typically `postgres`). It's important that this function only performs safe, read-only operations.
  - This also hardens the function by setting the search_path.

  ## Performance Impact:
  - Indexes: None
  - Triggers: None
  - Estimated Impact: Negligible. The function performs a simple primary key lookup.
*/
CREATE OR REPLACE FUNCTION public.get_user_roles(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
-- Hardens the function by setting a secure search path
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  -- Fetches the role from the user's profile
  SELECT "role"
  INTO v_role
  FROM public.profiles
  WHERE id = p_user_id;

  RETURN v_role;
END;
$$;
