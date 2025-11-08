/*
# [RLS Policy Update for HMS]
This migration script establishes a comprehensive set of Row-Level Security (RLS) policies for the Hostel Management System. It ensures that users can only access and modify data according to their assigned role (Admin, Staff, Student), resolving the "violates row-level security policy" error.

## Query Description: [This script will enable RLS on all primary data tables and create specific policies for SELECT, INSERT, UPDATE, and DELETE operations. It grants full access to Admins, provides appropriate permissions for Staff, and restricts Students to viewing/managing only their own related data. This is a critical security enhancement and is safe to apply.]

## Metadata:
- Schema-Category: ["Structural", "Security"]
- Impact-Level: ["Medium"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Tables affected: students, rooms, fees, visitors, maintenance_requests
- Functions created: get_user_role()
- Policies created: Multiple policies for each table to control access based on user roles.

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [Yes]
- Auth Requirements: [All operations will now be checked against the user's role via their JWT.]

## Performance Impact:
- Indexes: [None]
- Triggers: [None]
- Estimated Impact: [Negligible. RLS checks are highly optimized in PostgreSQL.]
*/

-- Helper function to get user role from JWT claims
create or replace function public.get_user_role()
returns text
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'user_metadata', '')::jsonb ->> 'role'
$$;

-- =============================================
-- STUDENTS TABLE
-- =============================================
alter table public.students enable row level security;

drop policy if exists "Allow admin full access on students" on public.students;
create policy "Allow admin full access on students"
on public.students for all
to authenticated
using (get_user_role() = 'Admin')
with check (get_user_role() = 'Admin');

drop policy if exists "Allow staff to view students" on public.students;
create policy "Allow staff to view students"
on public.students for select
to authenticated
using (get_user_role() = 'Staff');

drop policy if exists "Allow students to view and edit their own profile" on public.students;
create policy "Allow students to view and edit their own profile"
on public.students for all
to authenticated
using (id = (select student_id from profiles where id = auth.uid()))
with check (id = (select student_id from profiles where id = auth.uid()));


-- =============================================
-- ROOMS TABLE
-- =============================================
alter table public.rooms enable row level security;

drop policy if exists "Allow admin full access on rooms" on public.rooms;
create policy "Allow admin full access on rooms"
on public.rooms for all
to authenticated
using (get_user_role() = 'Admin')
with check (get_user_role() = 'Admin');

drop policy if exists "Allow authenticated users to view rooms" on public.rooms;
create policy "Allow authenticated users to view rooms"
on public.rooms for select
to authenticated
using (true);

-- =============================================
-- FEES TABLE
-- =============================================
alter table public.fees enable row level security;

drop policy if exists "Allow admin full access on fees" on public.fees;
create policy "Allow admin full access on fees"
on public.fees for all
to authenticated
using (get_user_role() = 'Admin')
with check (get_user_role() = 'Admin');

drop policy if exists "Allow students to view their own fees" on public.fees;
create policy "Allow students to view their own fees"
on public.fees for select
to authenticated
using (
  student_id = (select student_id from profiles where id = auth.uid())
);

-- =============================================
-- VISITORS TABLE
-- =============================================
alter table public.visitors enable row level security;

drop policy if exists "Allow admin full access on visitors" on public.visitors;
create policy "Allow admin full access on visitors"
on public.visitors for all
to authenticated
using (get_user_role() = 'Admin')
with check (get_user_role() = 'Admin');

drop policy if exists "Allow staff to manage visitors" on public.visitors;
create policy "Allow staff to manage visitors"
on public.visitors for all
to authenticated
using (get_user_role() = 'Staff')
with check (get_user_role() = 'Staff');

drop policy if exists "Allow students to view their own visitors" on public.visitors;
create policy "Allow students to view their own visitors"
on public.visitors for select
to authenticated
using (
  student_id = (select student_id from profiles where id = auth.uid())
);

-- =============================================
-- MAINTENANCE REQUESTS TABLE
-- =============================================
alter table public.maintenance_requests enable row level security;

drop policy if exists "Allow admin full access on maintenance_requests" on public.maintenance_requests;
create policy "Allow admin full access on maintenance_requests"
on public.maintenance_requests for all
to authenticated
using (get_user_role() = 'Admin')
with check (get_user_role() = 'Admin');

drop policy if exists "Allow staff to manage maintenance_requests" on public.maintenance_requests;
create policy "Allow staff to manage maintenance_requests"
on public.maintenance_requests for all
to authenticated
using (get_user_role() = 'Staff')
with check (get_user_role() = 'Staff');

drop policy if exists "Allow students to manage their own maintenance_requests" on public.maintenance_requests;
create policy "Allow students to manage their own maintenance_requests"
on public.maintenance_requests for all
to authenticated
using (
  reported_by_id = (select student_id from profiles where id = auth.uid())
)
with check (
  reported_by_id = (select student_id from profiles where id = auth.uid())
);
