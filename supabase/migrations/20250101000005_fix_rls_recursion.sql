/*
# [Fix] RLS Infinite Recursion
This migration fixes an infinite recursion bug in the Row-Level Security (RLS) policies for the `profiles` table.

## Query Description: [This operation updates a database function to prevent a critical error. The `get_user_role()` function was causing an infinite loop by querying the `profiles` table, which in turn triggered its own security policy, leading to a crash. The function is now modified to read the user's role directly from the `auth.users` table, which is a safer source and breaks the recursive loop. This change is safe and does not affect any user data.]

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Modifies the function: `public.get_user_role()`

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [No]
- Auth Requirements: [None]
- Description: This change fixes a bug in the RLS implementation, making it more stable and secure. It does not alter the intended security rules.

## Performance Impact:
- Indexes: [None]
- Triggers: [None]
- Estimated Impact: [Positive. Prevents a database error that was crashing queries. The new function may be slightly faster as it queries the `auth` schema directly.]
*/

-- Recreate the function to get the user's role from auth.users metadata to avoid recursion
CREATE OR REPLACE FUNCTION get_user_role()
RETURNS TEXT AS $$
DECLARE
  user_role TEXT;
BEGIN
  -- This query is run as the 'postgres' user and will bypass RLS.
  -- It fetches the role from the user's metadata in the auth.users table.
  -- This avoids the recursive loop that occurred when this function queried the 'profiles' table.
  SELECT raw_user_meta_data->>'role' INTO user_role
  FROM auth.users
  WHERE id = auth.uid();
  RETURN user_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
