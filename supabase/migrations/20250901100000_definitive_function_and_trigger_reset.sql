/*
          # [DEFINITIVE] Complete Function and Trigger Reset
          This migration provides a comprehensive fix for all function-related security advisories and dependency errors. It safely drops all custom functions and triggers and then recreates them from scratch with the required security hardening (`SET search_path = public`). This ensures the database logic is clean, secure, and stable.

          ## Query Description: This operation will temporarily remove and then restore all custom application logic within the database (functions and triggers). This is a safe reset procedure designed to fix persistent migration and security issues. No user or application data will be lost.
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Drops all custom functions: `handle_new_user`, `update_room_occupancy`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`, `universal_search`, `get_unallocated_students`, `allocate_room`.
          - Drops all custom triggers: `on_auth_user_created`, `trg_update_room_occupancy`.
          - Recreates all dropped functions with `SET search_path = public` to fix security warnings.
          - Recreates all dropped triggers and links them to the new secure functions.
          
          ## Security Implications:
          - RLS Status: Unchanged
          - Policy Changes: No
          - Auth Requirements: Admin privileges to run migrations.
          
          ## Performance Impact:
          - Indexes: Unchanged
          - Triggers: Recreated
          - Estimated Impact: Negligible. A brief moment where functions are unavailable during migration, which is handled by the migration tool.
          */

-- Step 1: Drop existing triggers and functions to prevent dependency errors.
-- Using CASCADE to also drop dependent triggers automatically.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.update_room_occupancy() CASCADE;

-- Drop remaining functions that don't have triggers.
DROP FUNCTION IF EXISTS public.get_or_create_session(date,text,text,integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid,jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid,integer,integer);
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid,uuid);


-- Step 2: Recreate all functions with proper security settings.

-- Function to create a profile and student record for a new user.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Create a profile
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number'
  );

  -- If the user is a student, create a student record
  IF new.raw_user_meta_data->>'role' = 'Student' THEN
    INSERT INTO public.students (id, full_name, email, contact)
    VALUES (
        new.id,
        new.raw_user_meta_data->>'full_name',
        new.email,
        new.raw_user_meta_data->>'mobile_number'
    );
  END IF;
  
  RETURN new;
END;
$$;

-- Function to update room occupancy counts and status.
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_room_id UUID;
  v_occupant_count INT;
BEGIN
  IF (TG_OP = 'DELETE') THEN
    v_room_id := OLD.room_id;
  ELSE
    v_room_id := NEW.room_id;
  END IF;

  SELECT COUNT(*) INTO v_occupant_count
  FROM public.room_allocations
  WHERE room_id = v_room_id AND is_active = true;

  UPDATE public.rooms
  SET 
    occupants = v_occupant_count,
    status = CASE
      WHEN v_occupant_count > 0 THEN 'Occupied'::room_status
      ELSE 'Vacant'::room_status
    END
  WHERE id = v_room_id AND status != 'Maintenance'::room_status;

  RETURN NULL;
END;
$$;

-- Function to get or create an attendance session.
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    session_id uuid;
BEGIN
    SELECT id INTO session_id
    FROM public.attendance_sessions
    WHERE date = p_date
      AND session_type = p_type
      AND (course IS NULL OR course = p_course)
      AND (year IS NULL OR year = p_year);

    IF session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Function for bulk marking attendance.
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
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

-- Function to get a student's monthly attendance calendar.
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status text)
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    WITH session_dates AS (
        SELECT generate_series(
            date_trunc('month', make_date(p_year, p_month, 1)),
            date_trunc('month', make_date(p_year, p_month, 1)) + interval '1 month' - interval '1 day',
            '1 day'::interval
        )::date as day
    )
    SELECT
        d.day,
        COALESCE(ar.status::text, 'Unmarked') as status
    FROM session_dates d
    LEFT JOIN attendance_records ar ON ar.student_id = p_student_id AND date_trunc('day', ar.created_at) = d.day
    ORDER BY d.day;
END;
$$;

-- Function for universal search across students and rooms.
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
    students_json jsonb;
    rooms_json jsonb;
    result_json jsonb;
BEGIN
    SELECT jsonb_agg(jsonb_build_object(
        'id', s.id,
        'label', s.full_name,
        'path', '/students/' || s.id::text
    ))
    INTO students_json
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%';

    SELECT jsonb_agg(jsonb_build_object(
        'id', r.id,
        'label', 'Room ' || r.room_number,
        'path', '/rooms/' || r.id::text
    ))
    INTO rooms_json
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';

    result_json := jsonb_build_object(
        'students', COALESCE(students_json, '[]'::jsonb),
        'rooms', COALESCE(rooms_json, '[]'::jsonb)
    );

    RETURN result_json;
END;
$$;

-- Function to get all students who are not allocated to a room.
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
SET search_path = public
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

-- Function to allocate a student to a room.
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.room_allocations (student_id, room_id, start_date)
    VALUES (p_student_id, p_room_id, now());
END;
$$;


-- Step 3: Recreate the triggers.

-- Trigger to create a profile when a new user signs up.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Trigger to update room occupancy after allocation changes.
CREATE TRIGGER trg_update_room_occupancy
  AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
  FOR EACH ROW EXECUTE PROCEDURE public.update_room_occupancy();
