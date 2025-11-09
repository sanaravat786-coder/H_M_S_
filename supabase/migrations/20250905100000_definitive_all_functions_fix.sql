/*
  # [DEFINITIVE FUNCTION FIX]
  This script provides a definitive fix for all function-related migration errors and security advisories.

  ## Query Description:
  - **Problem:** Previous migrations failed due to attempts to change function return types (e.g., universal_search) and left some functions without a secure search_path.
  - **Solution:** This script safely DROPS all custom application functions and then RECREATES them with the correct, secure definitions.
  - **Impact:** This is a safe, non-destructive operation. It only affects the function definitions, not your data. It will resolve the "cannot change return type" error and all "Function Search Path Mutable" security warnings.

  ## Metadata:
  - Schema-Category: "Structural"
  - Impact-Level: "Low"
  - Requires-Backup: false
  - Reversible: true (by restoring previous function versions)
*/

-- Step 1: Drop all existing custom functions to prevent signature conflicts.
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb[]);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);

-- Step 2: Recreate all functions with hardened security (SET search_path) and correct definitions.

-- Function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_results json;
BEGIN
  SELECT json_build_object(
    'students', (
      SELECT json_agg(
        json_build_object('id', s.id, 'label', s.full_name, 'path', '/students/' || s.id::text)
      )
      FROM students s
      WHERE s.full_name ILIKE '%' || p_search_term || '%'
      LIMIT 5
    ),
    'rooms', (
      SELECT json_agg(
        json_build_object('id', r.id, 'label', 'Room ' || r.room_number, 'path', '/rooms/' || r.id::text)
      )
      FROM rooms r
      WHERE r.room_number ILIKE '%' || p_search_term || '%'
      LIMIT 5
    )
  ) INTO v_results;

  RETURN v_results;
END;
$$;

-- Function: get_unallocated_students
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
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

-- Function: update_room_occupancy
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_occupant_count int;
BEGIN
  SELECT count(*)
  INTO v_occupant_count
  FROM public.room_allocations
  WHERE room_id = p_room_id AND is_active = true;

  UPDATE public.rooms
  SET 
    occupants = v_occupant_count,
    status = CASE
               WHEN status = 'Maintenance' THEN 'Maintenance'
               WHEN v_occupant_count >= occupants THEN 'Occupied'
               ELSE 'Vacant'
             END
  WHERE id = p_room_id;
END;
$$;

-- Function: allocate_room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_capacity int;
  v_current_occupants int;
BEGIN
  -- Check if student is already allocated
  IF EXISTS (SELECT 1 FROM public.room_allocations WHERE student_id = p_student_id AND is_active = true) THEN
    RAISE EXCEPTION 'Student is already allocated to a room.';
  END IF;

  -- Check room capacity
  SELECT occupants, (SELECT count(*) FROM public.room_allocations WHERE room_id = p_room_id AND is_active = true)
  INTO v_room_capacity, v_current_occupants
  FROM public.rooms
  WHERE id = p_room_id;

  IF v_current_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'Room is already full.';
  END IF;

  -- Deactivate any previous allocations for the student
  UPDATE public.room_allocations
  SET is_active = false, end_date = now()
  WHERE student_id = p_student_id;

  -- Create new allocation
  INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, now(), true);

  -- Update room occupancy
  PERFORM public.update_room_occupancy(p_room_id);
END;
$$;

-- Function: get_or_create_session
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  -- Try to find an existing session
  SELECT id INTO v_session_id
  FROM public.attendance_sessions
  WHERE date = p_date
    AND type = p_type
    AND (p_course IS NULL OR course = p_course)
    AND (p_year IS NULL OR year = p_year)
  LIMIT 1;

  -- If not found, create a new one
  IF v_session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (date, type, course, year)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

-- Function: bulk_mark_attendance
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb[])
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  record jsonb;
BEGIN
  FOREACH record IN ARRAY p_records
  LOOP
    INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
    VALUES (
      p_session_id,
      (record->>'student_id')::uuid,
      (record->>'status')::public.attendance_status,
      record->>'note',
      (record->>'late_minutes')::integer
    )
    ON CONFLICT (session_id, student_id) DO UPDATE
    SET
      status = EXCLUDED.status,
      note = EXCLUDED.note,
      late_minutes = EXCLUDED.late_minutes;
  END LOOP;
END;
$$;

-- Function: student_attendance_calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status public.attendance_status)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT s.date AS day, ar.status
  FROM public.attendance_sessions s
  JOIN public.attendance_records ar ON s.id = ar.session_id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM s.date) = p_month
    AND EXTRACT(YEAR FROM s.date) = p_year;
END;
$$;

-- Finally, ensure the user creation trigger function is also secure and robust.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := coalesce(new.raw_user_meta_data->>'role','student');
  v_full_name text := coalesce(new.raw_user_meta_data->>'full_name','');
BEGIN
  -- Normalize/validate role
  if v_role not in ('admin','staff','student') then
    v_role := 'student';
  end if;

  -- Insert corresponding profile row
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (new.id, new.email, v_full_name, v_role)
  ON CONFLICT (id) DO NOTHING;

  -- Also create a corresponding student row if the role is 'Student'
  IF v_role = 'student' THEN
    INSERT INTO public.students (id, full_name, email)
    VALUES (new.id, v_full_name, new.email)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  return new;
end;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_unallocated_students() TO authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_room(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_room_occupancy(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, text, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_mark_attendance(uuid, jsonb[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_attendance_calendar(uuid, integer, integer) TO authenticated;
