/*
  # [Function] get_user_profile_details
  Creates a secure RPC function to fetch comprehensive details for a single user, intended for the "My Profile" page.

  ## Query Description:
  This migration creates a `v_user_profile_details` view and a `get_user_profile_details` function. The function queries the view to get a user's full name, email, role, contact info, course, creation date, and their currently assigned room number. This is a safe, read-only operation and does not modify any data.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Low"
  - Requires-Backup: false
  - Reversible: true (the function and view can be dropped)

  ## Structure Details:
  - Creates View: `v_user_profile_details`
  - Creates Function: `get_user_profile_details(p_user_id uuid)`

  ## Security Implications:
  - RLS Status: Not directly affected.
  - Policy Changes: No.
  - Auth Requirements: The function is `SECURITY DEFINER` and safely queries data based on the provided user ID. It is granted `EXECUTE` permission for `authenticated` users only.
  - Search Path: The function's `search_path` is explicitly set to `public` to mitigate search path hijacking vulnerabilities, addressing a security advisory.

  ## Performance Impact:
  - Indexes: Relies on existing indexes on `profiles.id`, `room_allocations.student_id`, and `rooms.id`.
  - Triggers: None.
  - Estimated Impact: Low. The query is efficient for fetching a single user's details.
*/

-- Step 1: Create a view to simplify joining user profile data with room data.
-- This makes the main function cleaner and more maintainable.
CREATE OR REPLACE VIEW public.v_user_profile_details AS
SELECT
  p.id,
  p.full_name,
  p.email,
  p.role,
  p.contact,
  p.course,
  p.created_at,
  r.room_number
FROM
  public.profiles p
LEFT JOIN public.room_allocations ra ON p.id = ra.student_id AND ra.is_active = true
LEFT JOIN public.rooms r ON ra.room_id = r.id;

-- Step 2: Create the RPC function that the frontend will call.
-- It is defined with SECURITY DEFINER to bypass RLS, but is scoped to the user ID, making it secure.
DROP FUNCTION IF EXISTS public.get_user_profile_details(uuid);
CREATE OR REPLACE FUNCTION public.get_user_profile_details(p_user_id uuid)
RETURNS TABLE (
  id uuid,
  full_name text,
  email text,
  role text,
  contact text,
  course text,
  created_at timestamptz,
  room_number text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    v.id,
    v.full_name,
    v.email,
    v.role,
    v.contact,
    v.course,
    v.created_at,
    v.room_number
  FROM
    public.v_user_profile_details v
  WHERE
    v.id = p_user_id
  LIMIT 1;
$$;

-- Step 3: Grant permission for authenticated users to call this function.
GRANT EXECUTE ON FUNCTION public.get_user_profile_details(uuid) TO authenticated;
