/*
# [Initial Schema & RLS Setup]
This script sets up the complete database schema for the Hostel Management System, including tables for profiles, students, rooms, fees, visitors, and maintenance. It also configures Row Level Security (RLS) to ensure users can only access data they are permitted to see.

## Query Description: This is a foundational script. If run on a database with existing conflicting tables, it may fail. It's intended for initial setup. It creates tables and enables security policies that are critical for the application's multi-user functionality.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: false (for initial setup)
- Reversible: false (would require manual deletion)

## Structure Details:
- Tables Created: profiles, students, rooms, room_assignments, fees, visitors, maintenance_requests
- Functions Created: get_user_role(), handle_new_user()
- Triggers Created: on_auth_user_created

## Security Implications:
- RLS Status: Enabled on all new tables.
- Policy Changes: Yes, policies are created for Admin, Student, and Staff roles.
- Auth Requirements: Relies on Supabase Auth (auth.uid()).
*/

-- 1. Helper function to get user role from profiles table
create or replace function public.get_user_role()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return 'anon';
  else
    return (select role from public.profiles where id = auth.uid());
  end if;
end;
$$;

-- 2. Profiles table to store user-specific data
create table public.profiles (
  id uuid references auth.users(id) on delete cascade not null primary key,
  full_name text,
  role text not null
);
comment on table public.profiles is 'User profile information linked to authentication.';

-- RLS for profiles table
alter table public.profiles enable row level security;

create policy "Admin can manage all profiles"
on public.profiles for all
using (get_user_role() = 'Admin')
with check (get_user_role() = 'Admin');

create policy "Users can view their own profile"
on public.profiles for select
using (auth.uid() = id);

create policy "Users can update their own profile"
on public.profiles for update
using (auth.uid() = id);


-- 3. Students table
create table public.students (
  id uuid default gen_random_uuid() primary key,
  profile_id uuid references public.profiles(id) on delete cascade not null,
  full_name text,
  email text,
  course text,
  contact text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);
comment on table public.students is 'Stores student-specific details.';

-- RLS for students table
alter table public.students enable row level security;

create policy "Admin can manage all students"
on public.students for all
using (get_user_role() = 'Admin')
with check (get_user_role() = 'Admin');

create policy "Students can view their own student record"
on public.students for select
using ( (get_user_role() = 'Student') AND (auth.uid() = profile_id) );

create policy "Staff can view all students"
on public.students for select
using (get_user_role() = 'Staff');


-- 4. Trigger to create a profile and student record on new user sign-up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Create a profile
  insert into public.profiles (id, full_name, role)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');

  -- If the user is a student, create a student record
  if new.raw_user_meta_data->>'role' = 'Student' then
    insert into public.students (profile_id, full_name, email)
    values (new.id, new.raw_user_meta_data->>'full_name', new.email);
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- 5. Rooms table
create table public.rooms (
    id uuid default gen_random_uuid() primary key,
    room_number integer not null unique,
    type text not null, -- e.g., 'Single', 'Double'
    status text not null default 'Vacant' -- e.g., 'Vacant', 'Occupied', 'Maintenance'
);
comment on table public.rooms is 'Represents individual hostel rooms.';

-- RLS for rooms table
alter table public.rooms enable row level security;
create policy "Authenticated users can view rooms" on public.rooms for select using (auth.role() = 'authenticated');
create policy "Admin can manage rooms" on public.rooms for all using (get_user_role() = 'Admin');


-- 6. Room Assignments table
create table public.room_assignments (
    id uuid default gen_random_uuid() primary key,
    room_id uuid references public.rooms(id) on delete set null,
    student_id uuid references public.students(id) on delete cascade,
    assigned_at timestamp with time zone default timezone('utc'::text, now()) not null
);
comment on table public.room_assignments is 'Links students to their assigned rooms.';

-- RLS for room_assignments
alter table public.room_assignments enable row level security;
create policy "Admin can manage all assignments" on public.room_assignments for all using (get_user_role() = 'Admin');
create policy "Students can view their own assignment" on public.room_assignments for select using (
    (get_user_role() = 'Student') AND (student_id = (select s.id from public.students s where s.profile_id = auth.uid()))
);


-- 7. Fees table
create table public.fees (
    id uuid default gen_random_uuid() primary key,
    student_id uuid references public.students(id) on delete cascade not null,
    amount numeric(10, 2) not null,
    due_date date not null,
    status text not null default 'Due', -- 'Due', 'Paid', 'Overdue'
    paid_at timestamp with time zone
);
comment on table public.fees is 'Tracks student fee payments.';

-- RLS for fees table
alter table public.fees enable row level security;
create policy "Admin can manage all fees" on public.fees for all using (get_user_role() = 'Admin');
create policy "Students can view their own fees" on public.fees for select using (
    (get_user_role() = 'Student') AND (student_id = (select s.id from public.students s where s.profile_id = auth.uid()))
);


-- 8. Visitors table
create table public.visitors (
    id uuid default gen_random_uuid() primary key,
    student_id uuid references public.students(id) on delete cascade not null,
    visitor_name text not null,
    check_in_time timestamp with time zone default timezone('utc'::text, now()) not null,
    check_out_time timestamp with time zone
);
comment on table public.visitors is 'Logs visitor entries and exits.';

-- RLS for visitors table
alter table public.visitors enable row level security;
create policy "Admin and Staff can manage visitor logs" on public.visitors for all using (get_user_role() in ('Admin', 'Staff'));
create policy "Students can view visitors for themselves" on public.visitors for select using (
    (get_user_role() = 'Student') AND (student_id = (select s.id from public.students s where s.profile_id = auth.uid()))
);


-- 9. Maintenance Requests table
create table public.maintenance_requests (
    id uuid default gen_random_uuid() primary key,
    room_id uuid references public.rooms(id) on delete set null,
    reported_by_student_id uuid references public.students(id) on delete set null,
    issue text not null,
    status text not null default 'Pending', -- 'Pending', 'In Progress', 'Resolved'
    created_at timestamp with time zone default timezone('utc'::text, now()) not null
);
comment on table public.maintenance_requests is 'Tracks maintenance issues reported by students.';

-- RLS for maintenance_requests table
alter table public.maintenance_requests enable row level security;
create policy "Admin and Staff can manage all requests" on public.maintenance_requests for all using (get_user_role() in ('Admin', 'Staff'));
create policy "Students can manage their own requests" on public.maintenance_requests for all using (
    (get_user_role() = 'Student') AND (reported_by_student_id = (select s.id from public.students s where s.profile_id = auth.uid()))
);
