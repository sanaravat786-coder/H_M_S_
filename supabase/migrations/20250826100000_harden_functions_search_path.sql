/*
# [Function Security Hardening]
This migration hardens all existing database functions by explicitly setting the `search_path`. This is a critical security measure to prevent privilege escalation attacks and ensures that functions resolve objects (tables, types, etc.) from the intended `public` schema.

## Query Description: This operation is safe and non-destructive. It replaces existing function definitions with more secure versions. No data will be altered. This directly addresses the "Function Search Path Mutable" security advisory.

## Metadata:
- Schema-Category: "Security"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by reverting to previous function definitions)

## Structure Details:
- Functions being updated:
  - handle_new_user()
  - update_room_occupancy(uuid)
  - get_unallocated_students()
  - allocate_room(uuid, uuid)
  - universal_search(text)
  - get_or_create_session(date, text, text, integer)
  - bulk_mark_attendance(uuid, jsonb)
  - student_attendance_calendar(uuid, integer, integer)

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges to alter functions.
- Fixes: Mitigates "Function Search Path Mutable" vulnerability.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible performance impact. Improves security posture.
*/

-- 1. Harden handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'role',
    NEW.raw_user_meta_data->>'mobile_number'
  );
  RETURN NEW;
END;
$$;

-- 2. Harden update_room_occupancy function
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  UPDATE rooms
  SET occupants = (
    SELECT COUNT(*)
    FROM room_allocations
    WHERE room_id = p_room_id AND end_date IS NULL
  )
  WHERE id = p_room_id;
END;
$$;

-- 3. Harden get_unallocated_students function
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course
  FROM students s
  LEFT JOIN room_allocations ra ON s.id = ra.student_id AND ra.end_date IS NULL
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
END;
$$;

-- 4. Harden allocate_room function
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_room_capacity int;
  v_current_occupants int;
BEGIN
  -- Check room capacity
  SELECT r.occupants, (SELECT COUNT(*) FROM room_allocations WHERE room_id = p_room_id AND end_date IS NULL)
  INTO v_room_capacity, v_current_occupants
  FROM rooms r
  WHERE r.id = p_room_id;

  IF v_current_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'Room is already full.';
  END IF;

  -- Deactivate any previous active allocation for the student
  UPDATE room_allocations
  SET end_date = now()
  WHERE student_id = p_student_id AND end_date IS NULL;

  -- Create new allocation
  INSERT INTO room_allocations (student_id, room_id, start_date)
  VALUES (p_student_id, p_room_id, now());
END;
$$;

-- 5. Harden universal_search function
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(group_name text, id uuid, label text, path text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
    p_search_term := '%' || p_search_term || '%';

    RETURN QUERY
    -- Search Students
    SELECT 'Students' as group_name, s.id, s.full_name as label, '/students/' || s.id::text as path
    FROM students s
    WHERE s.full_name ILIKE p_search_term
       OR s.email ILIKE p_search_term
    LIMIT 5

    UNION ALL

    -- Search Rooms
    SELECT 'Rooms' as group_name, r.id, 'Room ' || r.room_number as label, '/rooms/' || r.id::text as path
    FROM rooms r
    WHERE r.room_number ILIKE p_search_term
    LIMIT 5;
END;
$$;

-- 6. Harden get_or_create_session function
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  session_id uuid;
BEGIN
  -- Try to find an existing session
  SELECT id INTO session_id
  FROM attendance_sessions
  WHERE date = p_date
    AND type = p_type
    AND (course IS NULL OR course = p_course)
    AND (year IS NULL OR year = p_year)
  LIMIT 1;

  -- If not found, create a new one
  IF session_id IS NULL THEN
    INSERT INTO attendance_sessions (date, type, course, year)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO session_id;
  END IF;

  RETURN session_id;
END;
$$;

-- 7. Harden bulk_mark_attendance function
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
    INSERT INTO attendance_records (session_id, student_id, status, note, late_minutes)
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
      late_minutes = EXCLUDED.late_minutes,
      updated_at = now();
  END LOOP;
END;
$$;

-- 8. Harden student_attendance_calendar function
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.date,
    COALESCE(ar.status::text, 'Unmarked') as status
  FROM
    attendance_sessions s
  LEFT JOIN
    attendance_records ar ON s.id = ar.session_id AND ar.student_id = p_student_id
  WHERE
    EXTRACT(MONTH FROM s.date) = p_month
    AND EXTRACT(YEAR FROM s.date) = p_year
  ORDER BY s.date;
END;
$$;
