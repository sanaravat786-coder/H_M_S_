/*
# [CRITICAL] Schema & Security Hotfix for Attendance Module (v2)

This script addresses the SQL error you encountered and all security advisories.

## The Problem:
1.  **Schema Flaw:** The `students` table was not linked to user accounts (`profiles`), making it impossible to apply user-specific security rules. My previous script incorrectly assumed this link existed, causing the error.
2.  **Security Vulnerabilities:** The advisories pointed out a critical issue with a `SECURITY DEFINER` view and insecure database functions.

## The Fix:
1.  **Adds `profile_id` to `students`:** This links a student record to a user account.
2.  **Links Existing Data:** A one-time script matches existing students to users by email.
3.  **Fixes Security Issues:** Replaces the insecure view, hardens functions, and adds correct Row Level Security (RLS) policies.
*/

-- STEP 1: Add profile_id to students table to link students to users
alter table public.students add column if not exists profile_id uuid references public.profiles(id) on delete set null;
create index if not exists idx_students_profile_id on public.students(profile_id);
-- Add a unique constraint to ensure one student record per profile
alter table public.students add constraint if not exists students_profile_id_key unique (profile_id);

/*
  ## Data Migration: Link Existing Students
  This query attempts to link existing student records to user profiles by matching their email addresses.
*/
update public.students s set profile_id = p.id
from public.profiles p
where s.email = p.email
  and s.profile_id is null;

-- STEP 2: Re-create the attendance view with SECURITY INVOKER to fix critical advisory
drop view if exists public.v_attendance_daily_summary;
create or replace view public.v_attendance_daily_summary
with (security_invoker = true) as
select
  s.session_date, s.session_type, s.block, s.room_id, s.course, s.year,
  count(*) filter (where r.status = 'Present') as present_count,
  count(*) filter (where r.status = 'Absent')  as absent_count,
  count(*) filter (where r.status = 'Late')    as late_count,
  count(*) filter (where r.status = 'Excused') as excused_count,
  count(*) as total_marked
from public.attendance_sessions s
left join public.attendance_records r on r.session_id = s.id
group by s.session_date, s.session_type, s.block, s.room_id, s.course, s.year;

-- STEP 3: Harden all new database functions to fix security warnings
create or replace function public.get_or_create_session(
  p_date date, p_type text, p_block text default null, p_room_id uuid default null, p_course text default null, p_year text default null
) returns uuid
language plpgsql security definer
set search_path = 'public'
as $$
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

create or replace function public.bulk_mark_attendance(
  p_session_id uuid, p_records jsonb
) returns void
language plpgsql security definer
set search_path = 'public'
as $$
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

create or replace function public.student_attendance_calendar(
  p_student_id uuid, p_month int, p_year int
) returns table(day date, status text, session_type text)
language sql security definer
set search_path = 'public'
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

-- STEP 4: Implement correct Row Level Security (RLS) policies
-- First, drop any previous (potentially incorrect) policies
drop policy if exists "Allow full access for admin and staff" on public.attendance_sessions;
drop policy if exists "Allow students to view their sessions" on public.attendance_sessions;
drop policy if exists "Allow full access for admin and staff" on public.attendance_records;
drop policy if exists "Students can view their own records" on public.attendance_records;
drop policy if exists "Allow full access for admin and staff" on public.leaves;
drop policy if exists "Students can manage their own leave requests" on public.leaves;

-- Helper function to get user role from profiles table
create or replace function public.get_user_role()
returns text
language sql
security invoker
stable
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- Policies for attendance_sessions
create policy "Allow full access for admin and staff" on public.attendance_sessions
  for all using (public.get_user_role() in ('Admin', 'Staff'));

create policy "Allow students to view their sessions" on public.attendance_sessions
  for select using (
    public.get_user_role() = 'Student' and
    exists (
      select 1 from public.attendance_records ar
      join public.students s on ar.student_id = s.id
      where ar.session_id = attendance_sessions.id
        and s.profile_id = auth.uid()
    )
  );

-- Policies for attendance_records
create policy "Allow full access for admin and staff" on public.attendance_records
  for all using (public.get_user_role() in ('Admin', 'Staff'));

create policy "Students can view their own records" on public.attendance_records
  for select using (
    public.get_user_role() = 'Student' and
    exists (
        select 1 from public.students s
        where s.id = attendance_records.student_id and s.profile_id = auth.uid()
    )
  );

-- Policies for leaves
create policy "Allow full access for admin and staff" on public.leaves
  for all using (public.get_user_role() in ('Admin', 'Staff'));

create policy "Students can manage their own leave requests" on public.leaves
  for all using (
    public.get_user_role() = 'Student' and
    exists (
        select 1 from public.students s
        where s.id = leaves.student_id and s.profile_id = auth.uid()
    )
  );
