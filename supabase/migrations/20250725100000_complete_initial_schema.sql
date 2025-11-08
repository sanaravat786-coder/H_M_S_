/*
# [Full Initial Schema Setup]
This script establishes the complete database schema for the SmartHostel application. It creates all required tables, sets up search optimizations, and configures core business logic and security policies.

## Query Description: [This script is foundational and will create the entire database structure from scratch. It is designed to be run on a new or empty project. It does not delete any existing data but will fail if these tables already exist. Ensure your database is ready for this initial setup.]

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["High"]
- Requires-Backup: [false]
- Reversible: [false]

## Structure Details:
- Tables Created: profiles, students, rooms, room_allocations, fees, payments, visitors, maintenance_requests, notices, audit_logs
- Extensions: pg_trgm
- Indexes: GIN indexes on searchable text fields.

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [Yes]
- Auth Requirements: [Policies rely on Supabase Auth roles.]

## Performance Impact:
- Indexes: [Added]
- Triggers: [Added]
- Estimated Impact: [Positive impact on search query performance. Negligible impact on write operations.]
*/

-- 1. TABLES
-- PROFILES (linked to auth.users)
create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null check (role in ('Admin','Staff','Student'))
);

-- STUDENTS
create table if not exists public.students(
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text unique,
  course text,
  contact text,
  created_at timestamptz default now()
);

-- ROOMS
create table if not exists public.rooms(
  id uuid primary key default gen_random_uuid(),
  room_number text unique not null,
  type text not null check (type in ('Single','Double','Triple')),
  status text not null default 'Vacant' check (status in ('Vacant','Occupied','Maintenance')),
  occupants int not null default 0,
  created_at timestamptz default now()
);

-- ROOM ALLOCATIONS
create table if not exists public.room_allocations(
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  room_id uuid not null references public.rooms(id) on delete restrict,
  start_date date not null default current_date,
  end_date date,
  is_active boolean generated always as (end_date is null) stored,
  constraint unique_active_allocation unique (student_id) where (end_date is null)
);

-- FEES
create table if not exists public.fees(
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  amount numeric(10,2) not null check (amount > 0),
  due_date date,
  status text not null default 'Due' check (status in ('Paid','Due','Overdue')),
  created_at timestamptz default now()
);

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

-- VISITORS
create table if not exists public.visitors(
  id uuid primary key default gen_random_uuid(),
  visitor_name text not null,
  student_id uuid not null references public.students(id) on delete cascade,
  check_in_time timestamptz default now(),
  check_out_time timestamptz,
  status text not null default 'In' check (status in ('In','Out'))
);

-- MAINTENANCE REQUESTS
create table if not exists public.maintenance_requests(
  id uuid primary key default gen_random_uuid(),
  issue text not null,
  room_number text,
  reported_by_id uuid references public.profiles(id),
  status text not null default 'Pending' check (status in ('Pending','In Progress','Resolved')),
  created_at timestamptz default now()
);

-- NOTICES
create table if not exists public.notices(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  audience text default 'all' check (audience in ('all', 'students', 'staff')),
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

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

-- 2. SEARCH INDEXES
create extension if not exists pg_trgm;
create index if not exists idx_students_full_name_trgm on public.students using gin (full_name gin_trgm_ops);
create index if not exists idx_students_email_trgm on public.students using gin (email gin_trgm_ops);
create index if not exists idx_rooms_room_number_trgm on public.rooms using gin (room_number gin_trgm_ops);
create index if not exists idx_visitors_name_trgm on public.visitors using gin (visitor_name gin_trgm_ops);
create index if not exists idx_maint_issue_trgm on public.maintenance_requests using gin (issue gin_trgm_ops);

-- 3. FUNCTIONS & TRIGGERS
-- Auto-create profile on new user sign-up
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

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Atomic room allocation function
create or replace function public.allocate_room(p_student_id uuid, p_room_id uuid)
returns void language plpgsql security definer as $$
declare
  v_prev uuid;
begin
  -- close existing allocation
  update public.room_allocations
     set end_date = now()
   where student_id = p_student_id and end_date is null;

  -- create new allocation
  insert into public.room_allocations(student_id, room_id) values (p_student_id, p_room_id);

  -- recalc occupants per room
  update public.rooms r
     set occupants = sub.cnt,
         status = case when sub.cnt > 0 then 'Occupied' else 'Vacant' end
    from (
      select ra.room_id, count(*)::int as cnt
      from public.room_allocations ra
      where ra.end_date is null
      group by ra.room_id
    ) sub
    where r.id = sub.room_id;

  -- audit log
  insert into public.audit_logs(actor_id, action, entity, entity_id, details)
  values (auth.uid(), 'ALLOCATE', 'room_allocations', p_room_id,
          jsonb_build_object('student_id', p_student_id, 'room_id', p_room_id));
end $$;

-- 4. RLS POLICIES
-- Helper function to get user role
create or replace function public.get_my_role()
returns text
language sql stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- Enable RLS on all tables
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

-- Audit Logs
create policy "Admins can read audit logs." on public.audit_logs for select using (get_my_role() = 'Admin');
