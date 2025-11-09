/*
# [DEFINITIVE SECURITY FIX] Recreate All Custom Functions & Triggers
This script provides a comprehensive fix for all "Function Search Path Mutable" security advisories and resolves dependency errors by dropping and recreating all custom functions and triggers in the correct order.

## Query Description:
This is a safe but structural operation. It will temporarily remove all custom functions and their associated triggers, then recreate them with hardened security settings. This ensures that all functions explicitly set a safe `search_path`, preventing potential security vulnerabilities. There is no risk of data loss, but it is a significant structural change to the database's procedural logic.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: false (Reverting would require re-running a previous migration version)

## Structure Details:
- Drops Triggers: `on_auth_user_created`, `trg_update_room_occupancy`
- Drops Functions: `handle_new_user`, `update_room_occupancy`, `allocate_room`, `get_unallocated_students`, `bulk_mark_attendance`, `get_or_create_session`, `student_attendance_calendar`, `universal_search`
- Recreates all dropped functions with `SET search_path = public`.
- Recreates all dropped triggers.

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges required to run.
- **Fixes all "Function Search Path Mutable" warnings.**

## Performance Impact:
- Indexes: None
- Triggers: Recreated
- Estimated Impact: Negligible. A brief moment where functions are unavailable during script execution.
*/

-- Step 1: Drop dependent triggers first to avoid dependency errors.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_update_room_occupancy ON public.room_allocations;

-- Step 2: Drop all existing custom functions.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, integer);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(integer, jsonb);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 3: Recreate all functions with security hardening.

-- Function to create a user profile from auth data
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.email,
    NEW.raw_user_meta_data ->> 'role',
    NEW.raw_user_meta_data ->> 'mobile_number'
  );
  RETURN NEW;
END;
$$;
ALTER FUNCTION public.handle_new_user() SET search_path = public;

-- Function to update room occupancy counts
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_id INT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_room_id := NEW.room_id;
  ELSIF TG_OP = 'DELETE' THEN
    v_room_id := OLD.room_id;
  ELSIF TG_OP = 'UPDATE' AND NEW.room_id IS DISTINCT FROM OLD.room_id THEN
    -- Update count for old room
    UPDATE public.rooms
    SET occupants = (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = OLD.room_id AND is_active = true)
    WHERE id = OLD.room_id;
    -- Update count for new room
    v_room_id := NEW.room_id;
  ELSE
    v_room_id := NEW.room_id;
  END IF;

  UPDATE public.rooms
  SET 
    occupants = (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = v_room_id AND is_active = true),
    status = CASE 
               WHEN (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = v_room_id AND is_active = true) > 0 THEN 'Occupied'::room_status
               ELSE 'Vacant'::room_status
             END
  WHERE id = v_room_id;
  
  RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$$;
ALTER FUNCTION public.update_room_occupancy() SET search_path = public;

-- Function to allocate a student to a room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.room_allocations (student_id, room_id, start_date)
  VALUES (p_student_id, p_room_id, now());
END;
$$;
ALTER FUNCTION public.allocate_room(uuid, integer) SET search_path = public;

-- Function to get students who are not allocated to any room
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course
  FROM public.students s
  LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
END;
$$;
ALTER FUNCTION public.get_unallocated_students() SET search_path = public;

-- Function for bulk attendance marking
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id integer, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
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
ALTER FUNCTION public.bulk_mark_attendance(integer, jsonb) SET search_path = public;

-- Function to get or create an attendance session
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session_id integer;
BEGIN
    SELECT id INTO v_session_id
    FROM public.attendance_sessions
    WHERE session_date = p_date AND session_type = p_type;

    IF v_session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (session_date, session_type, course_filter, year_filter)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO v_session_id;
    END IF;

    RETURN v_session_id;
END;
$$;
ALTER FUNCTION public.get_or_create_session(date, text, text, integer) SET search_path = public;

-- Function for student's attendance calendar view
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ar.created_at::date as day,
    ar.status
  FROM public.attendance_records ar
  JOIN public.attendance_sessions as2 ON ar.session_id = as2.id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM as2.session_date) = p_month
    AND EXTRACT(YEAR FROM as2.session_date) = p_year
  GROUP BY ar.created_at::date, ar.status
  ORDER BY day;
END;
$$;
ALTER FUNCTION public.student_attendance_calendar(uuid, integer, integer) SET search_path = public;

-- Function for universal search across multiple tables
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    students_json json;
    rooms_json json;
    result_json json;
BEGIN
    SELECT json_agg(
        json_build_object(
            'id', s.id,
            'label', s.full_name,
            'path', '/students/' || s.id::text
        )
    )
    INTO students_json
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%';

    SELECT json_agg(
        json_build_object(
            'id', r.id,
            'label', 'Room ' || r.room_number,
            'path', '/rooms/' || r.id::text
        )
    )
    INTO rooms_json
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';

    result_json := json_build_object(
        'students', COALESCE(students_json, '[]'::json),
        'rooms', COALESCE(rooms_json, '[]'::json)
    );

    RETURN result_json;
END;
$$;
ALTER FUNCTION public.universal_search(text) SET search_path = public;


-- Step 4: Recreate the triggers.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER trg_update_room_occupancy
  AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
  FOR EACH ROW
  EXECUTE FUNCTION public.update_room_occupancy();
