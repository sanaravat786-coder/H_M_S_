/*
# [Definitive Function and Trigger Fix]
This migration script provides a comprehensive fix for all custom database functions and their dependencies. It resolves recurring migration errors and security advisories related to function definitions and search paths.

## Query Description: [This operation will safely drop and recreate all custom functions and their associated triggers. It ensures every function is hardened against security vulnerabilities by setting a secure search_path and defining security context. This is a safe but structural change that should not affect application data.]

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["Medium"]
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Drops and recreates all custom functions:
  - `handle_new_user`
  - `get_unallocated_students`
  - `allocate_room`
  - `update_room_occupancy`
  - `update_room_occupancy_for_room`
  - `bulk_mark_attendance`
  - `get_or_create_session`
  - `student_attendance_calendar`
  - `universal_search`
- Drops and recreates the `on_auth_user_created` trigger.

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [No]
- Auth Requirements: [Admin privileges to run migrations]
- This script resolves the "Function Search Path Mutable" security advisory by explicitly setting `search_path = 'public'` for all functions.

## Performance Impact:
- Indexes: [No change]
- Triggers: [Recreated]
- Estimated Impact: [Negligible performance impact. A brief moment of function unavailability during the transaction.]
*/

-- Step 1: Drop all custom functions and dependent objects.
-- Using CASCADE for handle_new_user to also drop the dependent trigger.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.update_room_occupancy_for_room(uuid);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);


-- Step 2: Recreate all functions with security hardening.

-- Function to create a user profile and student record from auth trigger.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- Create a record in public.profiles
  INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.email,
    NEW.raw_user_meta_data->>'role',
    NEW.raw_user_meta_data->>'mobile_number'
  );
  -- If the user is a student, also create a record in public.students
  IF NEW.raw_user_meta_data->>'role' = 'Student' THEN
    INSERT INTO public.students (id, full_name, email, contact)
    VALUES (
      NEW.id,
      NEW.raw_user_meta_data->>'full_name',
      NEW.email,
      NEW.raw_user_meta_data->>'mobile_number'
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Function to get students who are not currently allocated to a room.
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course
  FROM public.students s
  LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = TRUE
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
END;
$$;

-- Function to allocate a student to a room.
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_room_occupants integer;
  v_room_capacity integer;
BEGIN
  SELECT occupants, 
    CASE "type"
      WHEN 'Single' THEN 1
      WHEN 'Double' THEN 2
      WHEN 'Triple' THEN 3
      ELSE 0
    END
  INTO v_room_occupants, v_room_capacity
  FROM public.rooms
  WHERE id = p_room_id;

  IF v_room_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'Room is already at full capacity';
  END IF;

  INSERT INTO public.room_allocations (student_id, room_id, start_date)
  VALUES (p_student_id, p_room_id, now());
END;
$$;

-- Helper function for the room_allocations trigger.
CREATE OR REPLACE FUNCTION public.update_room_occupancy_for_room(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_current_occupants integer;
BEGIN
    SELECT count(*) INTO v_current_occupants
    FROM public.room_allocations
    WHERE room_id = p_room_id AND is_active = true;

    UPDATE public.rooms
    SET
        occupants = v_current_occupants,
        status = CASE
            WHEN status = 'Maintenance' THEN 'Maintenance'
            WHEN v_current_occupants > 0 THEN 'Occupied'
            ELSE 'Vacant'
        END
    WHERE id = p_room_id;
END;
$$;

-- Trigger function to update room occupancy counts.
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.update_room_occupancy_for_room(NEW.room_id);
    ELSIF TG_OP = 'UPDATE' THEN
        PERFORM public.update_room_occupancy_for_room(COALESCE(NEW.room_id, OLD.room_id));
        IF NEW.room_id IS DISTINCT FROM OLD.room_id THEN
            PERFORM public.update_room_occupancy_for_room(OLD.room_id);
        END IF;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM public.update_room_occupancy_for_room(OLD.room_id);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Function to bulk insert or update attendance records.
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  record jsonb;
BEGIN
  FOR record IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
    VALUES (
      p_session_id,
      (record->>'student_id')::uuid,
      (record->>'status')::attendance_status,
      record->>'note',
      (record->>'late_minutes')::integer
    )
    ON CONFLICT (session_id, student_id)
    DO UPDATE SET
      status = EXCLUDED.status,
      note = EXCLUDED.note,
      late_minutes = EXCLUDED.late_minutes;
  END LOOP;
END;
$$;

-- Function to get an existing attendance session or create a new one.
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  SELECT id INTO v_session_id
  FROM public.attendance_sessions
  WHERE attendance_date = p_date
    AND session_type = p_type
    AND (course IS NULL OR course = p_course)
    AND (year IS NULL OR year = p_year)
  LIMIT 1;

  IF v_session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (attendance_date, session_type, course, year)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

-- Function to get a student's attendance for a specific month.
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ar.created_at::date as day,
    ar.status
  FROM public.attendance_records ar
  JOIN public.attendance_sessions asess ON ar.session_id = asess.id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM asess.attendance_date) = p_month
    AND EXTRACT(YEAR FROM asess.attendance_date) = p_year
  ORDER BY day;
END;
$$;

-- Function for global search across students and rooms.
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_results json;
BEGIN
  WITH students_search AS (
    SELECT
      'students' as type,
      json_agg(json_build_object(
        'id', s.id,
        'label', s.full_name,
        'path', '/students/' || s.id::text
      )) as results
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
  ),
  rooms_search AS (
    SELECT
      'rooms' as type,
      json_agg(json_build_object(
        'id', r.id,
        'label', 'Room ' || r.room_number,
        'path', '/rooms/' || r.id::text
      )) as results
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%'
  )
  SELECT
    json_object_agg(COALESCE(type, 'default'), results) INTO v_results
  FROM (
    SELECT * FROM students_search WHERE results IS NOT NULL
    UNION ALL
    SELECT * FROM rooms_search WHERE results IS NOT NULL
  ) as search_results;

  RETURN COALESCE(v_results, '{}'::json);
END;
$$;


-- Step 3: Recreate the trigger that depends on handle_new_user.
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();
