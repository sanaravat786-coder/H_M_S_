-- =============================================
-- Harden All Function Search Paths
--
-- Description:
-- This script recreates all existing database
-- functions to include `SET search_path = public`.
-- This is a critical security measure to prevent
-- privilege escalation attacks by ensuring that
-- functions only resolve objects (tables, types, etc.)
-- from trusted schemas.
--
-- This migration addresses the "Function Search
-- Path Mutable" security advisory.
-- =============================================

-- 1. Harden `handle_new_user` function
/*
  # [Function] handle_new_user
  [Trigger function to create a user profile after a new user signs up in `auth.users`.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality. It prevents potential privilege escalation vulnerabilities.]
  
  ## Metadata:
  - Schema-Category: ["Security"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'role','student');
  v_full_name text := coalesce(new.raw_user_meta_data->>'full_name','');
begin
  if v_role not in ('admin','staff','student') then
    v_role := 'student';
  end if;

  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, v_full_name, v_role)
  on conflict (id) do nothing;

  return new;
end;
$$;


-- 2. Harden `get_unallocated_students` function
/*
  # [Function] get_unallocated_students
  [Fetches all students who do not have an active room allocation.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality.]
  
  ## Metadata:
  - Schema-Category: ["Security"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.get_unallocated_students()
returns table (
  id uuid,
  full_name text,
  email text,
  course text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select s.id, s.full_name, s.email, s.course
  from public.students s
  where not exists (
    select 1
    from public.room_allocations ra
    where ra.student_id = s.id and ra.is_active = true
  )
  order by s.full_name;
end;
$$;


-- 3. Harden `update_room_occupancy` function
/*
  # [Function] update_room_occupancy
  [Internal helper function to recalculate and update the `occupants` count for a specific room.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality.]
  
  ## Metadata:
  - Schema-Category: ["Security", "Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.update_room_occupancy(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  occupant_count int;
begin
  select count(*)
  into occupant_count
  from public.room_allocations
  where room_id = p_room_id and is_active = true;

  update public.rooms
  set
    occupants = occupant_count,
    status = case
      when occupant_count > 0 then 'Occupied'::public.room_status
      else 'Vacant'::public.room_status
    end
  where id = p_room_id and status != 'Maintenance'::public.room_status;
end;
$$;


-- 4. Harden `allocate_room` function
/*
  # [Function] allocate_room
  [Allocates a student to a room, creating an active allocation record.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality.]
  
  ## Metadata:
  - Schema-Category: ["Security", "Data"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.allocate_room(p_student_id uuid, p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Deactivate any previous active allocations for the student
  update public.room_allocations
  set is_active = false, end_date = now()
  where student_id = p_student_id and is_active = true;

  -- Insert new active allocation
  insert into public.room_allocations (student_id, room_id, start_date, is_active)
  values (p_student_id, p_room_id, now(), true);

  -- Update room occupancy
  perform public.update_room_occupancy(p_room_id);
end;
$$;


-- 5. Harden `get_or_create_session` function
/*
  # [Function] get_or_create_session
  [Finds an existing attendance session for a given day/type or creates a new one.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality.]
  
  ## Metadata:
  - Schema-Category: ["Security", "Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.get_or_create_session(
  p_date date,
  p_type public.attendance_session_type,
  p_course text default null,
  p_year int default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  session_id uuid;
begin
  select id into session_id
  from public.attendance_sessions
  where session_date = p_date
    and session_type = p_type
    and (p_course is null or course = p_course)
    and (p_year is null or year = p_year);

  if session_id is null then
    insert into public.attendance_sessions (session_date, session_type, course, year, created_by)
    values (p_date, p_type, p_course, p_year, auth.uid())
    returning id into session_id;
  end if;

  return session_id;
end;
$$;


-- 6. Harden `bulk_mark_attendance` function
/*
  # [Function] bulk_mark_attendance
  [Inserts or updates multiple attendance records for a session in a single transaction.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality.]
  
  ## Metadata:
  - Schema-Category: ["Security", "Data"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  rec jsonb;
begin
  for rec in select * from jsonb_array_elements(p_records)
  loop
    insert into public.attendance_records(session_id, student_id, status, note, late_minutes)
    values (
      p_session_id,
      (rec->>'student_id')::uuid,
      (rec->>'status')::public.attendance_status,
      rec->>'note',
      (rec->>'late_minutes')::int
    )
    on conflict (session_id, student_id) do update
    set
      status = excluded.status,
      note = excluded.note,
      late_minutes = excluded.late_minutes,
      updated_at = now();
  end loop;
end;
$$;


-- 7. Harden `student_attendance_calendar` function
/*
  # [Function] student_attendance_calendar
  [Fetches a student's attendance status for each day of a given month and year.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality.]
  
  ## Metadata:
  - Schema-Category: ["Security"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.student_attendance_calendar(
  p_student_id uuid,
  p_month int,
  p_year int
)
returns table (day date, status public.attendance_status)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    d.day::date,
    coalesce(ar.status, 'Unmarked'::public.attendance_status) as status
  from
    generate_series(
      make_date(p_year, p_month, 1),
      make_date(p_year, p_month, 1) + interval '1 month' - interval '1 day',
      '1 day'
    ) as d(day)
  left join public.attendance_records ar
    on ar.student_id = p_student_id
    and date_trunc('day', ar.created_at) = d.day
  order by d.day;
end;
$$;


-- 8. Harden `universal_search` function
/*
  # [Function] universal_search
  [Performs a global search across students and rooms.]

  ## Query Description: [This operation redefines the function to explicitly set the `search_path`. This is a security enhancement with no impact on existing data or application functionality.]
  
  ## Metadata:
  - Schema-Category: ["Security"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
create or replace function public.universal_search(p_search_term text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_results jsonb;
begin
  select jsonb_build_object(
    'students', (
      select coalesce(jsonb_agg(t), '[]'::jsonb)
      from (
        select id, full_name as label, '/students/' || id::text as path
        from public.students
        where full_name ilike '%' || p_search_term || '%'
           or email ilike '%' || p_search_term || '%'
        limit 5
      ) t
    ),
    'rooms', (
      select coalesce(jsonb_agg(t), '[]'::jsonb)
      from (
        select id, 'Room ' || room_number as label, '/rooms/' || id::text as path
        from public.rooms
        where room_number ilike '%' || p_search_term || '%'
        limit 5
      ) t
    )
  ) into v_results;

  return v_results;
end;
$$;
