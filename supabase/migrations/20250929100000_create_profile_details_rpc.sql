/*
# [Function] Create `get_user_profile_details` RPC

This migration creates the `get_user_profile_details` function, which was missing and causing errors on the Profile page. This function securely fetches all necessary profile information, including room and course details, in a single call.

## Query Description:
This script creates a new SQL function `get_user_profile_details`. It is a non-destructive operation and is safe to run. It also hardens the function's security by setting a fixed `search_path`, addressing a security advisory.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (the function can be dropped)

## Structure Details:
- Creates function: `public.get_user_profile_details(uuid)`

## Security Implications:
- RLS Status: The function uses `SECURITY DEFINER` to read across tables but is scoped to the provided user ID, making it safe.
- Policy Changes: No
- Auth Requirements: `anon` and `authenticated` roles are granted execute permissions.

## Performance Impact:
- Indexes: Relies on existing primary key indexes for joins.
- Triggers: No
- Estimated Impact: Low. Improves performance by consolidating multiple frontend queries into one database call.
*/

-- Drop the function if it exists to ensure a clean recreation
drop function if exists public.get_user_profile_details(uuid);

-- Create the function to get all profile details in one call
create or replace function public.get_user_profile_details(p_user_id uuid)
returns table (
  id uuid,
  full_name text,
  email text,
  role text,
  contact text,
  course text,
  created_at timestamptz,
  room_number text
)
language sql
security definer
stable
-- Harden the function by setting a secure search path
set search_path = public
as $$
  select
    p.id,
    p.full_name,
    p.email,
    p.role,
    p.contact,
    s.course,
    p.created_at,
    r.room_number
  from profiles p
  -- The student record might not exist for admins/staff, so LEFT JOIN is crucial
  left join students s on s.email = p.email
  -- The room allocation might not exist, so LEFT JOIN is crucial
  left join room_allocations ra on ra.student_id = s.id and ra.is_active = true
  left join rooms r on r.id = ra.room_id
  where p.id = p_user_id
  limit 1;
$$;

-- Grant execute permission to authenticated users and anon role
grant execute on function public.get_user_profile_details(uuid) to authenticated;
grant execute on function public.get_user_profile_details(uuid) to anon;
