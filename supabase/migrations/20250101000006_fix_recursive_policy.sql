/*
  # [Function Update] Fix Infinite Recursion in get_user_role
  [This operation updates the get_user_role function to prevent an infinite recursion error caused by RLS policies.]

  ## Query Description: [This script replaces the existing get_user_role function with a corrected version. The original function was reading from the 'profiles' table, which had a security policy that also called the same function, creating a loop. The new version safely reads the user's role directly from the 'auth.users' table metadata, breaking the recursion and fixing the error that caused the dashboard to crash. This change is safe and does not affect existing data.]

  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]

  ## Structure Details:
  - Function: public.get_user_role()

  ## Security Implications:
  - RLS Status: [No Change]
  - Policy Changes: [No]
  - Auth Requirements: [Authenticated User]

  ## Performance Impact:
  - Indexes: [No Change]
  - Triggers: [No Change]
  - Estimated Impact: [Positive. Resolves a query-crashing infinite loop.]
*/
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  select auth.users.raw_user_meta_data->>'role' from auth.users where id = auth.uid()
$$;
