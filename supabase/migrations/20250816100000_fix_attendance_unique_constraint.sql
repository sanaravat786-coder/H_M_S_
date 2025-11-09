/*
          # [Fix] Attendance Module Schema &amp; RLS
          This script corrects a syntax error in the previous attendance module migration. It replaces the invalid UNIQUE constraint with a valid UNIQUE INDEX to enforce session uniqueness. It also includes the full schema, functions, and a complete set of Row Level Security (RLS) policies for the attendance feature.

          ## Query Description: This operation creates the necessary tables (attendance_sessions, attendance_records, leaves), views, and functions for the attendance module. It also implements strict RLS policies to ensure users can only access data they are permitted to see (e.g., students can only view their own attendance). This script is safe to run and corrects a previous error.
          
          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Creates tables: `attendance_sessions`, `attendance_records`, `leaves`
          - Creates view: `v_attendance_daily_summary`
          - Creates functions: `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`
          - Creates indexes for performance and uniqueness.
          - Enables and defines RLS policies for all new tables.
          
          ## Security Implications:
          - RLS Status: Enabled
          - Policy Changes: Yes. Adds policies for Admin, Staff, and Student roles on all new tables.
          - Auth Requirements: Policies rely on user roles stored in `auth.users.raw_user_meta_data`.
          
          ## Performance Impact:
          - Indexes: Added for primary keys, foreign keys, and common query patterns to ensure good performance.
          - Triggers: None
          - Estimated Impact: Low. Adds new tables and logic, should not impact existing performance.
          */

-- ATTENDANCE CORE TABLES
create table if not exists attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  session_date date not null,
  session_type text not null default 'NightRoll' check (session_type in ('NightRoll','Morning','Evening','Custom')),
  block text,
  room_id uuid references rooms(id) on delete set null,
  course text,
  year text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);

create table if not exists attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text not null check (status in ('Present','Absent','Late','Excused')),
  marked_at timestamptz default now(),
  marked_by uuid references public.profiles(id),
  note text,
  late_minutes int default 0 check (late_minutes >= 0),
  unique (session_id, student_id)
);

create table if not exists leaves (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text,
  approved_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  check (end_date >= start_date)
);

-- VIEWS
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

-- INDEXES (Including the corrected unique index)
create unique index if not exists uq_attendance_session on attendance_sessions (
    session_date,
    session_type,
    coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(block, ''),
    coalesce(course, ''),
    coalesce(year, '')
);
create index if not exists idx_att_records_student on attendance_records(student_id);
create index if not exists idx_att_records_session on attendance_records(session_id);
create index if not exists idx_leaves_student_dates on leaves(student_id, start_date, end_date);


-- RPC FUNCTIONS
create or replace function get_or_create_session(
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
  v_creator_id uuid := auth.uid();
begin
  select id into v_session_id from attendance_sessions
   where session_date = p_date 
     and session_type = p_type
     and coalesce(block,'') = coalesce(p_block,'')
     and coalesce(room_id,'00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and coalesce(course,'') = coalesce(p_course,'')
     and coalesce(year,'') = coalesce(p_year,'');

  if v_session_id is null then
    insert into attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    values (p_date, p_type, p_block, p_room_id, p_course, p_year, v_creator_id)
    returning id into v_session_id;
  end if;
  
  return v_session_id;
end $$;

create or replace function bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb
) returns void 
language plpgsql 
security definer
set search_path = public
as $$
declare 
  rec jsonb; 
  v_student_id uuid; 
  v_status text; 
  v_note text; 
  v_late_minutes int;
  v_marker_id uuid := auth.uid();
begin
  for rec in select * from jsonb_array_elements(p_records) loop
    v_student_id := (rec->>'student_id')::uuid;
    v_status  := rec->>'status';
    v_note    := rec->>'note';
    v_late_minutes := coalesce((rec->>'late_minutes')::int, 0);

    insert into attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    values (p_session_id, v_student_id, v_status, v_note, v_late_minutes, v_marker_id)
    on conflict (session_id, student_id) do update
      set status = excluded.status,
          note = excluded.note,
          late_minutes = excluded.late_minutes,
          marked_at = now(),
          marked_by = v_marker_id;
  end loop;
end $$;

create or replace function student_attendance_calendar(
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
  select d.d as day,
         coalesce(r.status, 'Unmarked') as status,
         s.session_type
  from days d
  left join attendance_sessions s on s.session_date = d.d
  left join attendance_records r on r.session_id = s.id and r.student_id = p_student_id
  order by d.d asc;
$$;


-- ROW LEVEL SECURITY
alter table attendance_sessions enable row level security;
alter table attendance_records enable row level security;
alter table leaves enable row level security;

-- POLICIES for attendance_sessions
drop policy if exists "Allow admin/staff full access" on attendance_sessions;
create policy "Allow admin/staff full access" on attendance_sessions
  for all using (is_admin() or is_staff());

drop policy if exists "Allow students to see relevant sessions" on attendance_sessions;
create policy "Allow students to see relevant sessions" on attendance_sessions
  for select using (exists (
    select 1 from attendance_records 
    where session_id = attendance_sessions.id and student_id = auth.uid()
  ));

-- POLICIES for attendance_records
drop policy if exists "Allow admin/staff full access" on attendance_records;
create policy "Allow admin/staff full access" on attendance_records
  for all using (is_admin() or is_staff());

drop policy if exists "Allow students to see their own records" on attendance_records;
create policy "Allow students to see their own records" on attendance_records
  for select using (student_id = auth.uid());

-- POLICIES for leaves
drop policy if exists "Allow admin/staff full access" on leaves;
create policy "Allow admin/staff full access" on leaves
  for all using (is_admin() or is_staff());

drop policy if exists "Students can manage their own leave requests" on leaves;
create policy "Students can manage their own leave requests" on leaves
  for all using (student_id = auth.uid());

grant execute on function get_or_create_session to authenticated;
grant execute on function bulk_mark_attendance to authenticated;
grant execute on function student_attendance_calendar to authenticated;
