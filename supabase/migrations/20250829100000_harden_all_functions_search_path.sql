/*
          # [Harden All Functions]
          This migration script recreates all custom functions in the database to include a fixed `search_path`. This is a critical security enhancement that resolves the "Function Search Path Mutable" advisory by preventing potential hijacking of function execution by malicious actors.

          ## Query Description: [This operation will safely drop and recreate all existing custom functions. It ensures that each function operates within a secure and predictable schema context, mitigating security risks. There is no risk of data loss, as only function definitions are being replaced.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Security"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Recreates function: `create_user_profile()`
          - Recreates function: `update_room_occupancy(uuid)`
          - Recreates function: `get_unallocated_students()`
          - Recreates function: `allocate_room(uuid, uuid)`
          - Recreates function: `get_or_create_session(date, text, text, integer)`
          - Recreates function: `bulk_mark_attendance(uuid, jsonb)`
          - Recreates function: `student_attendance_calendar(uuid, integer, integer)`
          - Recreates function: `universal_search(text)`
          
          ## Security Implications:
          - RLS Status: [Not Changed]
          - Policy Changes: [No]
          - Auth Requirements: [Functions will execute with the privileges of their invoker or definer, as originally set.]
          
          ## Performance Impact:
          - Indexes: [Not Changed]
          - Triggers: [Not Changed]
          - Estimated Impact: [Negligible performance impact. This is primarily a security and stability improvement.]
          */

-- =============================================
-- Function: create_user_profile
-- Description: Trigger function to create a profile entry when a new user is created in auth.users.
-- =============================================
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'role',
    NEW.raw_user_meta_data->>'mobile_number'
  );
  
  -- If the role is 'Student', also create an entry in the students table
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
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public';

-- =============================================
-- Function: update_room_occupancy
-- Description: Updates the occupants count for a given room.
-- =============================================
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE public.rooms
  SET occupants = (
    SELECT COUNT(*)
    FROM public.room_allocations
    WHERE room_id = p_room_id AND is_active = TRUE
  )
  WHERE id = p_room_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public';

-- =============================================
-- Function: get_unallocated_students
-- Description: Retrieves students who do not have an active room allocation.
-- =============================================
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text) AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course
  FROM public.students s
  LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = TRUE
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
END;
$$ LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = 'public';

-- =============================================
-- Function: allocate_room
-- Description: Allocates a student to a room and updates the room status.
-- =============================================
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void AS $$
DECLARE
  v_room_capacity int;
  v_current_occupants int;
BEGIN
  -- Check room capacity
  SELECT occupants, (SELECT COUNT(*) FROM room_allocations WHERE room_id = p_room_id AND is_active = TRUE)
  INTO v_room_capacity, v_current_occupants
  FROM rooms WHERE id = p_room_id;

  IF v_current_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'Room is already full';
  END IF;

  -- Deactivate any previous allocation for the student
  UPDATE public.room_allocations
  SET is_active = FALSE, end_date = NOW()
  WHERE student_id = p_student_id AND is_active = TRUE;

  -- Create new allocation
  INSERT INTO public.room_allocations (student_id, room_id, start_date)
  VALUES (p_student_id, p_room_id, NOW());

  -- Update room status and occupancy count
  PERFORM public.update_room_occupancy(p_room_id);
  UPDATE public.rooms SET status = 'Occupied' WHERE id = p_room_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public';


-- =============================================
-- Function: get_or_create_session
-- Description: Gets an existing attendance session or creates a new one.
-- =============================================
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid AS $$
DECLARE
  session_id uuid;
BEGIN
  SELECT id INTO session_id
  FROM public.attendance_sessions
  WHERE session_date = p_date
    AND session_type = p_type
    AND (course IS NULL OR course = p_course)
    AND (year IS NULL OR year = p_year);

  IF session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (session_date, session_type, course, year)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO session_id;
  END IF;

  RETURN session_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public';

-- =============================================
-- Function: bulk_mark_attendance
-- Description: Inserts or updates attendance records for a session in bulk.
-- =============================================
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void AS $$
BEGIN
  INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
  SELECT
    p_session_id,
    (value->>'student_id')::uuid,
    (value->>'status')::attendance_status,
    value->>'note',
    (value->>'late_minutes')::integer
  FROM jsonb_array_elements(p_records)
  ON CONFLICT (session_id, student_id)
  DO UPDATE SET
    status = EXCLUDED.status,
    note = EXCLUDED.note,
    late_minutes = EXCLUDED.late_minutes;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public';

-- =============================================
-- Function: student_attendance_calendar
-- Description: Retrieves all attendance records for a student for a given month and year.
-- =============================================
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ar.created_at::date as day,
    ar.status
  FROM public.attendance_records ar
  JOIN public.attendance_sessions s ON ar.session_id = s.id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM s.session_date) = p_month
    AND EXTRACT(YEAR FROM s.session_date) = p_year
  ORDER BY day;
END;
$$ LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = 'public';

-- =============================================
-- Function: universal_search
-- Description: Performs a global search across students and rooms.
-- =============================================
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb AS $$
DECLARE
  students_json jsonb;
  rooms_json jsonb;
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

  RETURN jsonb_build_object(
    'students', COALESCE(students_json, '[]'::jsonb),
    'rooms', COALESCE(rooms_json, '[]'::jsonb)
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = 'public';
