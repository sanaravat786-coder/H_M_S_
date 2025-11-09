-- =============================================
-- MASTER SCRIPT: Definitive Function and Security Fix
-- This script drops and recreates all custom functions and triggers
-- to resolve all dependency errors and security advisories.
-- =============================================

-- =============================================
-- Step 1: Drop dependent triggers
-- =============================================
/*
  # [Operation Name]
  Drop Dependent Triggers

  ## Query Description: [This operation safely removes existing database triggers that depend on functions we are about to update. This is a necessary preparatory step to avoid dependency errors. The triggers will be recreated at the end of the script.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [false]
*/
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_update_room_occupancy ON public.room_allocations;

-- =============================================
-- Step 2: Drop all custom functions
-- =============================================
/*
  # [Operation Name]
  Drop All Custom Functions

  ## Query Description: [This operation removes all custom functions from the database. This is required to redefine them with updated security settings. All functions will be recreated in the next steps.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [false]
*/
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, integer);
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(integer, jsonb[]);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);


-- =============================================
-- Step 3: Recreate all functions with security hardening
-- =============================================

-- Function 1: handle_new_user
/*
  # [Operation Name]
  Recreate handle_new_user function

  ## Query Description: [Recreates the function that creates a user profile after signup. It is hardened by setting a specific search_path to prevent security vulnerabilities.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number'
  );
  
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
ALTER FUNCTION public.handle_new_user() SET search_path = 'public';


-- Function 2: get_unallocated_students
/*
  # [Operation Name]
  Recreate get_unallocated_students function

  ## Query Description: [Recreates the function to get students who are not allocated to a room. It is hardened by setting a specific search_path.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
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
ALTER FUNCTION public.get_unallocated_students() SET search_path = 'public';

-- Function 3: update_room_occupancy
/*
  # [Operation Name]
  Recreate update_room_occupancy function

  ## Query Description: [Recreates the trigger function to update room occupancy counts and status. It is hardened by setting a specific search_path.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_id INT;
BEGIN
  IF (TG_OP = 'INSERT') THEN
    v_room_id := NEW.room_id;
  ELSIF (TG_OP = 'UPDATE') THEN
    v_room_id := COALESCE(NEW.room_id, OLD.room_id);
  ELSIF (TG_OP = 'DELETE') THEN
    v_room_id := OLD.room_id;
  END IF;

  IF v_room_id IS NOT NULL THEN
    WITH active_occupants AS (
      SELECT COUNT(*) as count
      FROM public.room_allocations
      WHERE room_id = v_room_id AND is_active = TRUE
    )
    UPDATE public.rooms
    SET 
      occupants = (SELECT count FROM active_occupants),
      status = CASE
        WHEN status = 'Maintenance' THEN 'Maintenance'
        WHEN (SELECT count FROM active_occupants) > 0 THEN 'Occupied'
        ELSE 'Vacant'
      END
    WHERE id = v_room_id;
  END IF;

  IF (TG_OP = 'UPDATE' AND OLD.is_active = FALSE AND NEW.is_active = TRUE) THEN
    v_room_id := NEW.room_id;
    UPDATE public.rooms
    SET occupants = (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = v_room_id AND is_active = TRUE)
    WHERE id = v_room_id;
  END IF;

  IF (TG_OP = 'UPDATE' AND OLD.is_active = TRUE AND NEW.is_active = FALSE) THEN
    v_room_id := OLD.room_id;
    UPDATE public.rooms
    SET occupants = (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = v_room_id AND is_active = TRUE)
    WHERE id = v_room_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;
ALTER FUNCTION public.update_room_occupancy() SET search_path = 'public';


-- Function 4: allocate_room
/*
  # [Operation Name]
  Recreate allocate_room function

  ## Query Description: [Recreates the function to allocate a student to a room. It is hardened by setting a specific search_path.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_capacity INT;
  v_current_occupants INT;
BEGIN
  IF EXISTS (SELECT 1 FROM public.room_allocations WHERE student_id = p_student_id AND is_active = TRUE) THEN
    RAISE EXCEPTION 'Student is already allocated to another room.';
  END IF;

  SELECT occupants, (
    CASE type
      WHEN 'Single' THEN 1
      WHEN 'Double' THEN 2
      WHEN 'Triple' THEN 3
      ELSE 0
    END
  ) INTO v_current_occupants, v_room_capacity
  FROM public.rooms WHERE id = p_room_id;

  IF v_current_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'Room is already at full capacity.';
  END IF;

  UPDATE public.room_allocations
  SET is_active = FALSE, end_date = NOW()
  WHERE student_id = p_student_id AND is_active = TRUE;

  INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, NOW(), TRUE);
END;
$$;
ALTER FUNCTION public.allocate_room(uuid, integer) SET search_path = 'public';


-- Function 5: get_or_create_session
/*
  # [Operation Name]
  Recreate get_or_create_session function

  ## Query Description: [Recreates the function to get or create an attendance session. It is hardened by setting a specific search_path.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text DEFAULT NULL, p_year integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
  v_session_id INT;
BEGIN
  SELECT id INTO v_session_id
  FROM public.attendance_sessions
  WHERE date = p_date
    AND session_type = p_type
    AND (p_course IS NULL OR course = p_course)
    AND (p_year IS NULL OR year = p_year)
  LIMIT 1;

  IF v_session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (date, session_type, course, year)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;
ALTER FUNCTION public.get_or_create_session(date, text, text, integer) SET search_path = 'public';


-- Function 6: bulk_mark_attendance
/*
  # [Operation Name]
  Recreate bulk_mark_attendance function

  ## Query Description: [Recreates the function for bulk-marking attendance records. It is hardened by setting a specific search_path.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id integer, p_records jsonb[])
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  rec jsonb;
BEGIN
  FOREACH rec IN ARRAY p_records
  LOOP
    INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
    VALUES (
      p_session_id,
      (rec->>'student_id')::uuid,
      (rec->>'status')::attendance_status,
      rec->>'note',
      (rec->>'late_minutes')::integer
    )
    ON CONFLICT (session_id, student_id)
    DO UPDATE SET
      status = EXCLUDED.status,
      note = EXCLUDED.note,
      late_minutes = EXCLUDED.late_minutes;
  END LOOP;
END;
$$;
ALTER FUNCTION public.bulk_mark_attendance(integer, jsonb[]) SET search_path = 'public';


-- Function 7: student_attendance_calendar
/*
  # [Operation Name]
  Recreate student_attendance_calendar function

  ## Query Description: [Recreates the function to fetch a student's attendance for a calendar view. It is hardened by setting a specific search_path.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.date AS day,
    ar.status
  FROM public.attendance_records ar
  JOIN public.attendance_sessions s ON ar.session_id = s.id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM s.date) = p_month
    AND EXTRACT(YEAR FROM s.date) = p_year;
END;
$$;
ALTER FUNCTION public.student_attendance_calendar(uuid, integer, integer) SET search_path = 'public';


-- Function 8: universal_search
/*
  # [Operation Name]
  Recreate universal_search function

  ## Query Description: [Recreates the universal search function for the application. It is hardened by setting a specific search_path.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  students_json jsonb;
  rooms_json jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object('id', id, 'label', full_name, 'path', '/students/' || id::text))
  INTO students_json
  FROM public.students
  WHERE full_name ILIKE '%' || p_search_term || '%';

  SELECT jsonb_agg(jsonb_build_object('id', id, 'label', 'Room ' || room_number, 'path', '/rooms/' || id::text))
  INTO rooms_json
  FROM public.rooms
  WHERE room_number ILIKE '%' || p_search_term || '%';

  RETURN jsonb_build_object(
    'students', COALESCE(students_json, '[]'::jsonb),
    'rooms', COALESCE(rooms_json, '[]'::jsonb)
  );
END;
$$;
ALTER FUNCTION public.universal_search(text) SET search_path = 'public';


-- =============================================
-- Step 4: Recreate triggers
-- =============================================
/*
  # [Operation Name]
  Recreate Database Triggers

  ## Query Description: [This operation recreates the database triggers that were removed earlier. They are now linked to the new, secure functions, restoring automated database logic.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
*/
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

CREATE TRIGGER trg_update_room_occupancy
  AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
  FOR EACH ROW EXECUTE PROCEDURE public.update_room_occupancy();
