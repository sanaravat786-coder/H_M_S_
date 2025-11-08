/*
# [Initial Schema Setup with Fixes]
This script creates the complete database schema for the SmartHostel application. It includes tables for profiles, students, rooms, allocations, fees, payments, visitors, maintenance, notices, and audit logs. It also sets up necessary extensions, indexes, triggers for automatic profile creation, and Row-Level Security (RLS) policies for data protection.

## Query Description: This is a comprehensive setup script. It is designed to be run on a fresh database. It is largely safe but establishes the entire structure and security model. It is not intended to be run on a database with existing, conflicting tables.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: true
- Reversible: false

## Structure Details:
- Tables created: profiles, students, rooms, room_allocations, fees, payments, visitors, maintenance_requests, notices, audit_logs
- Extensions enabled: pg_trgm
- Indexes created: GIN indexes for search, unique index for active room allocations.
- Functions created: handle_new_user, get_my_role
- Triggers created: on_auth_user_created

## Security Implications:
- RLS Status: Enabled for all application tables.
- Policy Changes: Yes, this script defines the base RLS policies for all roles (Admin, Staff, Student).
- Auth Requirements: Policies rely on `auth.uid()` and a custom `get_my_role()` function.

## Performance Impact:
- Indexes: Adds GIN indexes on several text columns to improve search performance.
- Triggers: Adds a trigger on `auth.users` which fires once per user creation. Impact is minimal.
- Estimated Impact: Positive impact on search queries. Negligible impact on write operations.
*/

-- 1. ENABLE EXTENSIONS
create extension if not exists "pg_trgm" with schema "extensions";

-- 2. CREATE TABLES
-- PROFILES (linked to auth.users)
create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null check (role in ('Admin','Staff','Student'))
);
comment on table public.profiles is 'User profile information, linked to authentication users.';

-- STUDENTS
create table if not exists public.students(
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text unique,
  course text,
  contact text,
  created_at timestamptz default now()
);
comment on table public.students is 'Stores student demographic and contact information.';

-- ROOMS
create table if not exists public.rooms(
  id uuid primary key default gen_random_uuid(),
  room_number text unique not null,
  type text not null check (type in ('Single','Double','Triple')),
  status text not null default 'Vacant' check (status in ('Vacant','Occupied','Maintenance')),
  occupants int not null default 0,
  created_at timestamptz default now()
);
comment on table public.rooms is 'Manages hostel room inventory and status.';

-- ROOM ALLOCATIONS
create table if not exists public.room_allocations(
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete restrict,
  start_date date not null default current_date,
  end_date date,
  is_active boolean generated always as (end_date is null) stored
);
comment on table public.room_allocations is 'Historical log of student room assignments.';

-- FEES
create table if not exists public.fees(
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  amount numeric(10,2) not null check (amount > 0),
  due_date date,
  status text not null default 'Due' check (status in ('Paid','Due','Overdue')),
  created_at timestamptz default now()
);
comment on table public.fees is 'Fee records for students.';

-- PAYMENTS
create table if not exists public.payments(
  id uuid primary key default gen_random_uuid(),
  fee_id uuid not null references public.fees(id) on delete cascade,
  amount numeric(10,2) not null check (amount > 0),
  mode text check (mode in ('Cash','UPI','Card','NetBanking')),
  reference text,
  paid_on timestamptz default now(),
  created_by uuid references public.profiles(id)
);
comment on table public.payments is 'Payment records against fees.';

-- VISITORS
create table if not exists public.visitors(
  id uuid primary key default gen_random_uuid(),
  visitor_name text not null,
  student_id uuid not null references public.students(id) on delete cascade,
  check_in_time timestamptz default now(),
  check_out_time timestamptz,
  status text not null default 'In' check (status in ('In','Out'))
);
comment on table public.visitors is 'Log of visitors to the hostel.';

-- MAINTENANCE REQUESTS
create table if not exists public.maintenance_requests(
  id uuid primary key default gen_random_uuid(),
  issue text not null,
  room_number text,
  reported_by_id uuid references public.profiles(id),
  status text not null default 'Pending' check (status in ('Pending','In Progress','Resolved')),
  created_at timestamptz default now()
);
comment on table public.maintenance_requests is 'Maintenance requests from residents.';

-- NOTICES
create table if not exists public.notices(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  audience text default 'all' check (audience in ('all', 'students', 'staff')),
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);
comment on table public.notices is 'Notice board for announcements.';

-- AUDIT LOGS
create table if not exists public.audit_logs(
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  action text not null,
  entity text not null,
  entity_id uuid,
  at timestamptz default now(),
  details jsonb
);
comment on table public.audit_logs is 'Logs important actions for auditing purposes.';

-- 3. CREATE INDEXES FOR PERFORMANCE AND CONSTRAINTS
-- Search indexes
create index if not exists idx_students_full_name_trgm on public.students using gin (full_name extensions.gin_trgm_ops);
create index if not exists idx_students_email_trgm on public.students using gin (email extensions.gin_trgm_ops);
create index if not exists idx_rooms_room_number_trgm on public.rooms using gin (room_number extensions.gin_trgm_ops);
create index if not exists idx_visitors_name_trgm on public.visitors using gin (visitor_name extensions.gin_trgm_ops);
create index if not exists idx_maint_issue_trgm on public.maintenance_requests using gin (issue extensions.gin_trgm_ops);

-- Partial unique index for room allocations
CREATE UNIQUE INDEX IF NOT EXISTS unique_active_allocation_idx
ON public.room_allocations (student_id)
WHERE (end_date IS NULL);

-- 4. CREATE FUNCTIONS AND TRIGGERS
-- Function to create a profile for a new user
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  return new;
end;
$$;

-- Trigger to run the function when a new user signs up
create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Helper function to get user role
create or replace function public.get_my_role()
returns text
language sql stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- 5. ENABLE ROW-LEVEL SECURITY (RLS)
alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.rooms enable row level security;
alter table public.room_allocations enable row level security;
alter table public.fees enable row level security;
alter table public.payments enable row level security;
alter table public.visitors enable row level security;
alter table public.maintenance_requests enable row level security;
alter table public.notices enable row level security;
alter table public.audit_logs enable row level security;

-- 6. CREATE RLS POLICIES
-- Profiles
create policy "Public profiles are viewable by everyone." on public.profiles for select using (true);
create policy "Users can insert their own profile." on public.profiles for insert with check (auth.uid() = id);
create policy "Users can update their own profile." on public.profiles for update using (auth.uid() = id);

-- Rooms & Students
create policy "Admin and Staff have full access to students." on public.students for all using (get_my_role() in ('Admin', 'Staff'));
create policy "All authenticated users can view students." on public.students for select using (auth.role() = 'authenticated');
create policy "Admin and Staff have full access to rooms." on public.rooms for all using (get_my_role() in ('Admin', 'Staff'));
create policy "All authenticated users can view rooms." on public.rooms for select using (auth.role() = 'authenticated');

-- Notices
create policy "Notices are viewable by everyone." on public.notices for select using (true);
create policy "Admins and Staff can manage notices." on public.notices for all using (get_my_role() in ('Admin', 'Staff'));

-- Role-based access for other tables
create policy "Admin and Staff have full access." on public.fees for all using (get_my_role() in ('Admin', 'Staff'));
create policy "Admin and Staff have full access." on public.payments for all using (get_my_role() in ('Admin', 'Staff'));
create policy "Admin and Staff have full access." on public.room_allocations for all using (get_my_role() in ('Admin', 'Staff'));
create policy "Admin and Staff have full access." on public.visitors for all using (get_my_role() in ('Admin', 'Staff'));
create policy "Admin and Staff have full access." on public.maintenance_requests for all using (get_my_role() in ('Admin', 'Staff'));

-- Audit Logs (Admin read-only)
create policy "Admins can read audit logs." on public.audit_logs for select using (get_my_role() = 'Admin');
