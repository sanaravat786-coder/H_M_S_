/*
          # [Operation Name]
          Create Attendance Module Schema

          ## Query Description: [This script sets up the complete database schema for the new Attendance Management feature. It creates tables to store attendance sessions and individual records, a table for student leave, and a view for daily summaries. It also adds functions to streamline creating sessions and marking attendance in bulk. Finally, it enables and configures Row Level Security to ensure users can only access the data they are permitted to see. This is a foundational, structural change and is not expected to impact existing data.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [true]
          
          ## Structure Details:
          - Tables Created: attendance_sessions, attendance_records, leaves
          - Views Created: v_attendance_daily_summary
          - Functions Created: get_or_create_session, bulk_mark_attendance, student_attendance_calendar
          - Indexes Created: idx_att_sessions_date, idx_att_records_student, idx_att_records_session
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [Yes]
          - Auth Requirements: [Policies rely on auth.uid() and a custom get_my_claim('role') function to determine user roles (Admin, Staff, Student).]
          
          ## Performance Impact:
          - Indexes: [Added]
          - Triggers: [None]
          - Estimated Impact: [Low performance impact on existing operations. New indexes are added to optimize queries on the new attendance tables.]
          */

-- 1. CORE TABLES
-- Table to store high-level attendance sessions
create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  session_date date not null,
  session_type text not null default 'NightRoll' check (session_type in ('NightRoll','Morning','Evening','Custom')),
  block text,
  room_id uuid references public.rooms(id) on delete set null,
  course text,
  year text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  unique (session_date, session_type, coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(block,''), coalesce(course,''), coalesce(year,''))
);
comment on table public.attendance_sessions is 'Defines a specific attendance-taking event (e.g., Night Roll for Block A on 2025-08-20).';

-- Table for individual student attendance records per session
create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text not null check (status in ('Present','Absent','Late','Excused')),
  marked_at timestamptz default now(),
  marked_by uuid references public.profiles(id) on delete set null,
  note text,
  late_minutes int default 0 check (late_minutes >= 0),
  unique (session_id, student_id)
);
comment on table public.attendance_records is 'Stores the attendance status for a single student within a session.';

-- Optional table for managing student leaves/outpasses
create table if not exists public.leaves (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text,
  approved_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz default now(),
  check (end_date >= start_date)
);
comment on table public.leaves is 'Tracks approved student leave for excused absences.';

-- 2. INDEXES
create index if not exists idx_att_sessions_date on public.attendance_sessions(session_date);
create index if not exists idx_att_records_student on public.attendance_records(student_id);
create index if not exists idx_att_records_session on public.attendance_records(session_id);
create index if not exists idx_leaves_student_dates on public.leaves(student_id, start_date, end_date);


-- 3. VIEWS
create or replace view public.v_attendance_daily_summary as
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
from public.attendance_sessions s
left join public.attendance_records r on r.session_id = s.id
group by s.session_date, s.session_type, s.block, s.room_id, s.course, s.year;
comment on view public.v_attendance_daily_summary is 'Aggregates daily attendance counts for quick reporting.';

-- 4. RPC FUNCTIONS
create or replace function public.get_or_create_session(
  p_date date,
  p_type text,
  p_block text default null,
  p_room_id uuid default null,
  p_course text default null,
  p_year text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
begin
  select id into v_session_id from public.attendance_sessions
   where session_date = p_date
     and session_type = p_type
     and coalesce(block, '') = coalesce(p_block, '')
     and coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and coalesce(course, '') = coalesce(p_course, '')
     and coalesce(year, '') = coalesce(p_year, '');

  if v_session_id is null then
    insert into public.attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    values (p_date, p_type, p_block, p_room_id, p_course, p_year, auth.uid())
    returning id into v_session_id;
  end if;

  return v_session_id;
end $$;
comment on function public.get_or_create_session is 'Creates a new attendance session if one does not exist for the given parameters, otherwise returns the existing session ID.';

create or replace function public.bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec jsonb;
begin
  for rec in select * from jsonb_array_elements(p_records)
  loop
    insert into public.attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
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
comment on function public.bulk_mark_attendance is 'Inserts or updates multiple attendance records for a given session in a single transaction.';

create or replace function public.student_attendance_calendar(
  p_student_id uuid,
  p_month int,
  p_year int
) returns table(day date, status text, session_type text)
language sql
security definer
set search_path = public
as $$
  with days as (
    select generate_series(
      make_date(p_year, p_month, 1),
      (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date,
      interval '1 day'
    )::date as d
  )
  select
    d.d as day,
    coalesce(r.status, 'Unmarked') as status,
    s.session_type
  from days d
  left join public.attendance_sessions s on s.session_date = d.d
  left join public.attendance_records r on r.session_id = s.id and r.student_id = p_student_id
  order by d.d asc;
$$;
comment on function public.student_attendance_calendar is 'Returns a student''s attendance status for each day of a given month.';


-- 5. ROW LEVEL SECURITY
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
alter table public.leaves enable row level security;

-- Policies for attendance_sessions
drop policy if exists "Allow admin/staff full access on sessions" on public.attendance_sessions;
create policy "Allow admin/staff full access on sessions"
  on public.attendance_sessions for all
  using ( is_admin() OR is_staff() );

drop policy if exists "Allow students to see sessions they are part of" on public.attendance_sessions;
create policy "Allow students to see sessions they are part of"
  on public.attendance_sessions for select
  using ( exists (
    select 1 from public.attendance_records ar
    where ar.session_id = id and ar.student_id = auth.uid()
  ));

-- Policies for attendance_records
drop policy if exists "Allow admin/staff full access on records" on public.attendance_records;
create policy "Allow admin/staff full access on records"
  on public.attendance_records for all
  using ( is_admin() OR is_staff() );

drop policy if exists "Allow students to see their own records" on public.attendance_records;
create policy "Allow students to see their own records"
  on public.attendance_records for select
  using ( student_id = auth.uid() );

-- Policies for leaves
drop policy if exists "Allow admin/staff full access on leaves" on public.leaves;
create policy "Allow admin/staff full access on leaves"
  on public.leaves for all
  using ( is_admin() OR is_staff() );

drop policy if exists "Allow students to manage their own leaves" on public.leaves;
create policy "Allow students to manage their own leaves"
  on public.leaves for all
  using ( student_id = auth.uid() );
