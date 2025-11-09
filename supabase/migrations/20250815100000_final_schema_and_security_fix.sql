--
-- [SmartHostel] Final Consolidated Schema &amp; Security Migration
--
-- This single, idempotent script resolves all previous errors and implements the new Attendance module.
--
-- Fixes Included:
-- 1. Corrects SQL syntax for adding constraints (removes invalid `IF NOT EXISTS`).
-- 2. Adds `mobile_number` to `profiles` to fix the sign-up error.
-- 3. Replaces the faulty `handle_new_user` trigger with a robust version.
-- 4. Adds the missing `profile_id` to the `students` table to link them to user accounts.
-- 5. Includes a one-time data migration to link existing students to profiles.
-- 6. Fixes all security advisories (Security Definer View, Function Search Path).
-- 7. Creates the complete schema for the Attendance Module with correct RLS policies.
--
-- =================================================================
-- STEP 1: Fix `profiles` and `students` tables for Sign-Up &amp; RLS
-- =================================================================
/*
          # [Operation Name]
          Fix Core User Schema
          ## Query Description: This operation corrects the fundamental user schema. It adds `mobile_number` to the `profiles` table to fix the sign-up error. It also adds a `profile_id` to the `students` table to correctly link student records to user accounts, which is essential for security. A one-time data migration links existing records.
          ## Metadata:
          - Schema-Category: ["Structural", "Data"]
          - Impact-Level: ["High"]
          - Requires-Backup: true
          - Reversible: false
*/
-- Add mobile_number to profiles to match sign-up form
alter table public.profiles add column if not exists mobile_number text;
-- Add profile_id to students to link to user accounts
alter table public.students add column if not exists profile_id uuid;
-- Drop and recreate constraints using the correct idempotent pattern
alter table public.students drop constraint if exists students_profile_id_fkey;
alter table public.students add constraint students_profile_id_fkey
  foreign key (profile_id) references public.profiles(id) on delete set null;
alter table public.students drop constraint if exists students_profile_id_key;
alter table public.students add constraint students_profile_id_key
  unique (profile_id);
-- One-time data migration: Link existing students to their profiles via email
update public.students s
set profile_id = p.id
from public.profiles p
where s.email = p.email and s.profile_id is null;
-- =================================================================
-- STEP 2: Recreate the `handle_new_user` trigger
-- =================================================================
/*
          # [Operation Name]
          Recreate New User Trigger
          ## Query Description: This operation replaces the database trigger that runs after user sign-up. The new version is simplified and secure. It correctly populates the `profiles` table with all required data from the sign-up form (including `mobile_number`) and removes flawed logic that caused errors.
          ## Metadata:
          - Schema-Category: ["Structural", "Security"]
          - Impact-Level: ["High"]
          - Requires-Backup: false
          - Reversible: false
*/
-- Drop existing trigger and function to ensure a clean slate
drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();
-- Create a new, simplified function to populate the profiles table
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, role, mobile_number)
  values (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number'
  );
  return new;
end;
$$;
-- Recreate the trigger to call the new function
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
-- =================================================================
-- STEP 3: Create Attendance Module Schema
-- =================================================================
/*
          # [Operation Name]
          Create Attendance Module Tables
          ## Query Description: This operation creates the core tables for the attendance module: `attendance_sessions`, `attendance_records`, and `leaves`. It defines the structure for tracking daily roll-calls, individual student statuses, and leave requests. A unique index is created to prevent duplicate attendance sessions.
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: false
          - Reversible: true (by dropping tables)
*/
create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  session_date date not null,
  session_type text not null default 'NightRoll' check (session_type in ('NightRoll','Morning','Evening','Custom')),
  block text,
  room_id uuid references public.rooms(id),
  course text,
  year text,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now()
);
-- Use a unique index to handle COALESCE, which is not allowed in a table constraint
drop index if exists uix_attendance_session_uniqueness;
create unique index uix_attendance_session_uniqueness on public.attendance_sessions (session_date, session_type, coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(block,''), coalesce(course,''), coalesce(year,''));
create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.students(id),
  status text not null check (status in ('Present','Absent','Late','Excused')),
  marked_at timestamptz default now(),
  marked_by uuid references public.profiles(id),
  note text,
  late_minutes int default 0 check (late_minutes >= 0),
  unique (session_id, student_id)
);
create table if not exists public.leaves (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id),
  start_date date not null,
  end_date date not null,
  reason text,
  approved_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  check (end_date >= start_date)
);
-- Indexes
create index if not exists idx_att_sessions_date on public.attendance_sessions(session_date);
create index if not exists idx_att_records_student on public.attendance_records(student_id);
create index if not exists idx_att_records_session on public.attendance_records(session_id);
-- =================================================================
-- STEP 4: Harden Functions and Views for Attendance Module
-- =================================================================
/*
          # [Operation Name]
          Harden Database Functions and Views
          ## Query Description: This operation creates or replaces all functions and views for the attendance module to fix security advisories. It sets a strict `search_path` on all functions and replaces the insecure `SECURITY DEFINER` view with a safe `SECURITY INVOKER` function.
          ## Metadata:
          - Schema-Category: ["Security", "Structural"]
          - Impact-Level: ["High"]
          - Requires-Backup: false
          - Reversible: false
*/
-- Drop the insecure view if it exists
drop view if exists public.v_attendance_daily_summary;
-- Replace with a SECURITY INVOKER function for safety
create or replace function public.get_attendance_daily_summary()
returns table (
  session_date date, session_type text, block text, room_id uuid, course text, year text,
  present_count bigint, absent_count bigint, late_count bigint, excused_count bigint, total_marked bigint
) language sql security invoker set search_path = '' as $$
  select
    s.session_date, s.session_type, s.block, s.room_id, s.course, s.year,
    count(*) filter (where r.status = 'Present') as present_count,
    count(*) filter (where r.status = 'Absent')  as absent_count,
    count(*) filter (where r.status = 'Late')    as late_count,
    count(*) filter (where r.status = 'Excused') as excused_count,
    count(*) as total_marked
  from public.attendance_sessions s
  left join public.attendance_records r on r.session_id = s.id
  group by s.id;
$$;
-- Harden all RPC functions
create or replace function public.get_or_create_session(
  p_date date, p_type text, p_block text default null, p_room_id uuid default null, p_course text default null, p_year text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  select id into v_id from public.attendance_sessions
   where session_date = p_date and session_type = p_type
     and coalesce(block,'') = coalesce(p_block,'')
     and coalesce(room_id,'00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and coalesce(course,'') = coalesce(p_course,'')
     and coalesce(year,'') = coalesce(p_year,'');
  if v_id is null then
    insert into public.attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    values (p_date, p_type, p_block, p_room_id, p_course, p_year, auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end $$;
create or replace function public.bulk_mark_attendance(
  p_session_id uuid, p_records jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare rec jsonb; v_student uuid; v_status text; v_note text; v_late int;
begin
  for rec in select * from jsonb_array_elements(p_records) loop
    v_student := (rec->>'student_id')::uuid; v_status  := rec->>'status'; v_note := rec->>'note'; v_late := coalesce((rec->>'late_minutes')::int,0);
    insert into public.attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    values (p_session_id, v_student, v_status, v_note, v_late, auth.uid())
    on conflict (session_id, student_id) do update
      set status = excluded.status, note = excluded.note, late_minutes = excluded.late_minutes, marked_at = now(), marked_by = auth.uid();
  end loop;
end $$;
create or replace function public.student_attendance_calendar(
  p_student_id uuid, p_month int, p_year int
) returns table(day date, status text, session_type text) language sql security definer set search_path = '' as $$
  with days as (select generate_series(make_date(p_year, p_month, 1), (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date, interval '1 day')::date as d)
  select d.d as day, coalesce(r.status, 'Unmarked') as status, s.session_type
  from days d
  left join public.attendance_sessions s on s.session_date = d.d
  left join public.attendance_records r on r.session_id = s.id and r.student_id = p_student_id
  order by d.d asc;
$$;
-- =================================================================
-- STEP 5: Implement Row Level Security for Attendance Module
-- =================================================================
/*
          # [Operation Name]
          Implement Row Level Security for Attendance
          ## Query Description: This operation enables and creates RLS policies for the new attendance tables. These policies are critical for security, ensuring students can only view their own records, while staff and admins have appropriate management permissions.
          ## Metadata:
          - Schema-Category: ["Security"]
          - Impact-Level: ["High"]
          - Requires-Backup: false
          - Reversible: false
*/
-- Enable RLS
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
alter table public.leaves enable row level security;
-- Policies for attendance_sessions
drop policy if exists "Allow staff/admin full access on sessions" on public.attendance_sessions;
create policy "Allow staff/admin full access on sessions" on public.attendance_sessions for all
  using (get_user_role(auth.uid()) in ('Admin', 'Staff'));
drop policy if exists "Allow student to see relevant sessions" on public.attendance_sessions;
create policy "Allow student to see relevant sessions" on public.attendance_sessions for select
  using (get_user_role(auth.uid()) = 'Student' and exists (
    select 1 from public.attendance_records ar join public.students s on ar.student_id = s.id
    where ar.session_id = public.attendance_sessions.id and s.profile_id = auth.uid()
  ));
-- Policies for attendance_records
drop policy if exists "Allow staff/admin full access on records" on public.attendance_records;
create policy "Allow staff/admin full access on records" on public.attendance_records for all
  using (get_user_role(auth.uid()) in ('Admin', 'Staff'));
drop policy if exists "Allow student to see own records" on public.attendance_records;
create policy "Allow student to see own records" on public.attendance_records for select
  using (get_user_role(auth.uid()) = 'Student' and exists (
    select 1 from public.students s where s.id = student_id and s.profile_id = auth.uid()
  ));
-- Policies for leaves
drop policy if exists "Allow staff/admin full access on leaves" on public.leaves;
create policy "Allow staff/admin full access on leaves" on public.leaves for all
  using (get_user_role(auth.uid()) in ('Admin', 'Staff'));
drop policy if exists "Allow student to manage own leaves" on public.leaves;
create policy "Allow student to manage own leaves" on public.leaves for all
  using (get_user_role(auth.uid()) = 'Student' and exists (
    select 1 from public.students s where s.id = student_id and s.profile_id = auth.uid()
  ));
