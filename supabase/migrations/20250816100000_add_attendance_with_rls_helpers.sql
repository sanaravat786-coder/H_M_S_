/*
# [Feature] Complete Attendance Module with RLS Fix
This script adds the full attendance module and fixes the previous migration error by defining the required `is_admin()` and `is_staff()` helper functions before creating the RLS policies that depend on them.

## Query Description:
This is a comprehensive script to set up the attendance feature. It creates new tables, views, functions, and security policies. It is designed to be run once. There is no risk to existing data as it only adds new objects.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: false

## Structure Details:
- **Functions Created**: `is_admin`, `is_staff`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`.
- **Tables Created**: `attendance_sessions`, `attendance_records`, `leaves`.
- **Views Created**: `v_attendance_daily_summary`.
- **RLS Policies**: Enables and creates policies for all new tables.

## Security Implications:
- RLS Status: Enabled on new tables.
- Policy Changes: Yes, new policies are created to restrict data access based on user roles (Admin, Staff, Student).
- Auth Requirements: Policies rely on `auth.uid()` and user metadata roles.

## Performance Impact:
- Indexes: Adds indexes on key columns for `attendance_sessions` and `attendance_records` to optimize queries.
- Triggers: None.
- Estimated Impact: Low impact on existing operations; optimized for new attendance queries.
*/

-- =============================================
-- SECTION 1: ROLE-CHECKING HELPER FUNCTIONS
-- =============================================
-- Description: These functions are required for RLS policies to check a user's role.
-- They were missing in the previous migration, causing the error.

create or replace function is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$
  select (auth.jwt()->>'raw_user_meta_data')::jsonb->>'role' = 'Admin'
$$;

create or replace function is_staff()
returns boolean language sql stable security definer
set search_path = public
as $$
  select (auth.jwt()->>'raw_user_meta_data')::jsonb->>'role' = 'Staff'
$$;


-- =============================================
-- SECTION 2: TABLE AND VIEW DEFINITIONS
-- =============================================
-- Description: Core tables for the attendance module.

create table if not exists attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  session_date date not null,
  session_type text not null default 'NightRoll' check (session_type in ('NightRoll','Morning','Evening','Custom')),
  block text,
  room_id uuid references rooms(id) on delete set null,
  course text,
  year text,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz default now()
);
-- Note: The UNIQUE constraint is now handled by a UNIQUE INDEX below to avoid syntax errors.

create table if not exists attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references attendance_sessions(id) on delete cascade,
  student_id uuid not null references students(id) on delete cascade,
  status text not null check (status in ('Present','Absent','Late','Excused')),
  marked_at timestamptz default now(),
  marked_by uuid references profiles(id) on delete set null,
  note text,
  late_minutes int default 0 check (late_minutes >= 0),
  unique (session_id, student_id)
);

create table if not exists leaves (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text,
  approved_by uuid references profiles(id) on delete set null,
  created_at timestamptz default now(),
  check (end_date >= start_date)
);

create or replace view v_attendance_daily_summary as
select
  s.session_date,
  s.session_type,
  s.block,
  s.room_id,
  s.course,
  s.year,
  count(*) filter (where r.status = 'Present') as present_count,
  count(*) filter (where r.status = 'Absent')  as absent_count,
  count(*) filter (where r.status = 'Late')    as late_count,
  count(*) filter (where r.status = 'Excused') as excused_count,
  count(*) as total_marked
from attendance_sessions s
left join attendance_records r on r.session_id = s.id
group by s.session_date, s.session_type, s.block, s.room_id, s.course, s.year;


-- =============================================
-- SECTION 3: INDEXES
-- =============================================
-- Description: Indexes to improve query performance.

-- This unique index replaces the problematic UNIQUE constraint in the table definition.
create unique index if not exists uq_attendance_sessions_key on attendance_sessions(session_date, session_type, coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(block,''), coalesce(course,''), coalesce(year,''));

create index if not exists idx_att_sessions_date on attendance_sessions(session_date);
create index if not exists idx_att_records_student on attendance_records(student_id);
create index if not exists idx_att_records_session on attendance_records(session_id);
create index if not exists idx_leaves_student_dates on leaves(student_id, start_date, end_date);


-- =============================================
-- SECTION 4: ROW LEVEL SECURITY (RLS)
-- =============================================
-- Description: Policies to secure the new tables.

alter table attendance_sessions enable row level security;
alter table attendance_records enable row level security;
alter table leaves enable row level security;

-- Policies for attendance_sessions
drop policy if exists "Admins and Staff can manage all sessions" on attendance_sessions;
create policy "Admins and Staff can manage all sessions"
on attendance_sessions for all
using ( is_admin() or is_staff() )
with check ( is_admin() or is_staff() );

drop policy if exists "Students can view sessions they are part of" on attendance_sessions;
create policy "Students can view sessions they are part of"
on attendance_sessions for select
using ( exists (
  select 1 from attendance_records ar
  where ar.session_id = id and ar.student_id = auth.uid()
) );

-- Policies for attendance_records
drop policy if exists "Admins and Staff can manage all records" on attendance_records;
create policy "Admins and Staff can manage all records"
on attendance_records for all
using ( is_admin() or is_staff() )
with check ( is_admin() or is_staff() );

drop policy if exists "Students can view their own records" on attendance_records;
create policy "Students can view their own records"
on attendance_records for select
using ( student_id = auth.uid() );

-- Policies for leaves
drop policy if exists "Admins and Staff can manage all leaves" on leaves;
create policy "Admins and Staff can manage all leaves"
on leaves for all
using ( is_admin() or is_staff() )
with check ( is_admin() or is_staff() );

drop policy if exists "Students can manage their own leaves" on leaves;
create policy "Students can manage their own leaves"
on leaves for all
using ( student_id = auth.uid() )
with check ( student_id = auth.uid() );


-- =============================================
-- SECTION 5: RPC FUNCTIONS
-- =============================================
-- Description: Functions for the application to call.

create or replace function get_or_create_session(
  p_date date,
  p_type text,
  p_block text default null,
  p_room_id uuid default null,
  p_course text default null,
  p_year text default null
) returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  select id into v_id from attendance_sessions
   where session_date = p_date and session_type = p_type
     and coalesce(block,'') = coalesce(p_block,'')
     and coalesce(room_id,'00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and coalesce(course,'') = coalesce(p_course,'')
     and coalesce(year,'') = coalesce(p_year,'');
  if v_id is null then
    insert into attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    values (p_date, p_type, p_block, p_room_id, p_course, p_year, auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb
) returns void language plpgsql security definer as $$
declare rec jsonb;
begin
  for rec in select * from jsonb_array_elements(p_records)
  loop
    insert into attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    values (
      p_session_id,
      (rec->>'student_id')::uuid,
      rec->>'status',
      rec->>'note',
      coalesce((rec->>'late_minutes')::int, 0),
      auth.uid()
    )
    on conflict (session_id, student_id) do update
      set status = excluded.status,
          note = excluded.note,
          late_minutes = excluded.late_minutes,
          marked_at = now(),
          marked_by = auth.uid();
  end loop;
end $$;

create or replace function student_attendance_calendar(
  p_student_id uuid,
  p_month int,
  p_year int
) returns table(day date, status text, session_type text) language sql stable security definer as $$
  with days as (
    select generate_series(
      make_date(p_year, p_month, 1),
      (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date,
      interval '1 day'
    )::date as d
  )
  select d.d as day,
         coalesce(r.status, 'Unmarked') as status,
         s.session_type
  from days d
  left join attendance_sessions s on s.session_date = d.d
  left join attendance_records r on r.session_id = s.id and r.student_id = p_student_id
  order by d.d asc;
$$;
