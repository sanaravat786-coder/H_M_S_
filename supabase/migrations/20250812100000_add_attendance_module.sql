/*
  # [Feature] Attendance Module Schema

  This script sets up the complete database schema for the new Attendance Management feature.
  It includes tables for sessions and records, supporting views, and RPC functions for core logic.

  ## Query Description:
  This is a structural change that adds new tables, views, and functions to the database. It does not modify or delete existing data in other tables. It is safe to run on a production database, but as always, a backup is recommended before applying new schema changes.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Medium"
  - Requires-Backup: true
  - Reversible: false (requires manual dropping of tables/functions)

  ## Structure Details:
  - Tables Created:
    - attendance_sessions
    - attendance_records
    - leaves
  - Views Created:
    - v_attendance_daily_summary
  - Functions Created:
    - get_or_create_session
    - bulk_mark_attendance
    - student_attendance_calendar
  - Indexes Created:
    - uq_attendance_sessions_scoped
    - idx_att_sessions_date
    - idx_att_records_student
    - idx_att_records_session

  ## Security Implications:
  - RLS Status: Enabled on new tables.
  - Policy Changes: No. Placeholder RLS policies are included as comments and must be implemented according to your application's roles.
  - Auth Requirements: Functions are `SECURITY DEFINER` and rely on `auth.uid()`.

  ## Performance Impact:
  - Indexes: Adds several indexes to optimize lookups for attendance data.
  - Triggers: None.
  - Estimated Impact: Low impact on existing operations. Performance of new attendance queries will be dependent on the new indexes.
*/

-- ATTENDANCE CORE
-- Create the sessions table without the problematic inline UNIQUE constraint.
create table if not exists attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  session_date date not null,
  session_type text not null default 'NightRoll' check (session_type in ('NightRoll','Morning','Evening','Custom')),
  block text,              -- optional grouping (hostel block)
  room_id uuid references rooms(id), -- optional: targeted room session
  course text,             -- optional: filter by course
  year text,               -- optional: filter by year/semester
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

-- Create a separate unique index on expressions to handle NULLs correctly.
-- This enforces that a session is unique for a given date, type, and scope.
create unique index if not exists uq_attendance_sessions_scoped
on attendance_sessions (
  session_date,
  session_type,
  coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(block, ''),
  coalesce(course, ''),
  coalesce(year, '')
);

create table if not exists attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references attendance_sessions(id) on delete cascade,
  student_id uuid not null references students(id),
  status text not null check (status in ('Present','Absent','Late','Excused')),
  marked_at timestamptz default now(),
  marked_by uuid references profiles(id),
  note text,
  late_minutes int default 0 check (late_minutes >= 0),
  unique (session_id, student_id)
);

-- OPTIONAL: Outpass/Leave for excused logic
create table if not exists leaves (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references students(id),
  start_date date not null,
  end_date date not null,
  reason text,
  approved_by uuid references profiles(id),
  created_at timestamptz default now(),
  check (end_date >= start_date)
);

-- VIEWS / MATERIALIZED LOGIC
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

-- INDEXES
create index if not exists idx_att_sessions_date on attendance_sessions(session_date);
create index if not exists idx_att_records_student on attendance_records(student_id);
create index if not exists idx_att_records_session on attendance_records(session_id);

-- RPC FUNCTIONS
-- Create or fetch a session for a date/type/scope
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

-- Bulk mark attendance
create or replace function bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb -- [{student_id, status, note, late_minutes}]
) returns void language plpgsql security definer as $$
declare rec jsonb; v_student uuid; v_status text; v_note text; v_late int;
begin
  for rec in select * from jsonb_array_elements(p_records)
  loop
    v_student := (rec->>'student_id')::uuid;
    v_status  := rec->>'status';
    v_note    := rec->>'note';
    v_late    := coalesce((rec->>'late_minutes')::int,0);

    insert into attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    values (p_session_id, v_student, v_status, v_note, v_late, auth.uid())
    on conflict (session_id, student_id) do update
      set status = excluded.status,
          note = excluded.note,
          late_minutes = excluded.late_minutes,
          marked_at = now(),
          marked_by = auth.uid();
  end loop;
end $$;

-- Student monthly calendar (matrix-friendly)
create or replace function student_attendance_calendar(
  p_student_id uuid,
  p_month int,
  p_year int
) returns table(day date, status text, session_type text) language sql security definer as $$
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

-- RLS POLICIES
-- Enable RLS
alter table attendance_sessions enable row level security;
alter table attendance_records enable row level security;
alter table leaves enable row level security;

-- Example policies (adapt to your auth.role lookups):
-- Admin: full access
-- Staff: read/write sessions and records; create sessions; bulk mark
-- Student: read-only own records, can create leaves for self (optional), cannot write attendance

-- NOTE: The following are placeholder policies. You will need to create specific policies
-- that match your application's `get_role()` function or equivalent logic.

/*
create policy "Admin/Staff can manage sessions"
on attendance_sessions for all
using ( get_role(auth.uid()) in ('Admin', 'Staff') );

create policy "Students can see sessions they are part of"
on attendance_sessions for select
using ( exists (select 1 from attendance_records where session_id = id and student_id = auth.uid()) );

create policy "Admin/Staff can manage records"
on attendance_records for all
using ( get_role(auth.uid()) in ('Admin', 'Staff') );

create policy "Students can see their own records"
on attendance_records for select
using ( student_id = auth.uid() );

create policy "Admin/Staff can manage leaves"
on leaves for all
using ( get_role(auth.uid()) in ('Admin', 'Staff') );

create policy "Students can manage their own leaves"
on leaves for all
using ( student_id = auth.uid() );
*/
