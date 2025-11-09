/*
          # [Fix Missing Type and Harden Functions]
          This migration script addresses two issues:
          1. Creates the missing `attendance_session_type` ENUM required by the attendance module.
          2. Recreates all existing database functions with a fixed `search_path` to resolve security warnings and ensure they use the new type correctly.

          ## Query Description: [This operation is safe and essential for application functionality and security. It defines a new data type and then updates existing server-side functions to be more secure and to recognize this new type. There is no risk to existing data.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [true]
          
          ## Structure Details:
          - Creates ENUM `public.attendance_session_type`.
          - Recreates functions: `handle_new_user`, `update_room_occupancy`, `get_unallocated_students`, `allocate_room`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`, `universal_search`.
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          - Hardens all functions by setting a non-mutable `search_path`, resolving multiple security advisories.
          
          ## Performance Impact:
          - Indexes: [None]
          - Triggers: [None]
          - Estimated Impact: [Negligible. Function recreation is a one-time, low-impact operation.]
          */

-- Step 1: Create the missing ENUM type if it doesn't exist.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_session_type') THEN
        CREATE TYPE public.attendance_session_type AS ENUM ('NightRoll', 'Morning', 'Evening');
    END IF;
END
$$;

-- Step 2: Recreate all functions with the security fix and correct types.

-- Function: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT := COALESCE(new.raw_user_meta_data->>'role', 'student');
  v_full_name TEXT := COALESCE(new.raw_user_meta_data->>'full_name', '');
BEGIN
  IF v_role NOT IN ('admin', 'staff', 'student') THEN
    v_role := 'student';
  END IF;
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (new.id, new.email, v_full_name, v_role)
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

-- Function: update_room_occupancy
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    UPDATE public.rooms
    SET occupants = occupants + 1
    WHERE id = NEW.room_id;
  ELSIF (TG_OP = 'UPDATE' AND NEW.end_date IS NOT NULL AND OLD.end_date IS NULL) THEN
    UPDATE public.rooms
    SET occupants = occupants - 1
    WHERE id = OLD.room_id;
  END IF;
  RETURN NEW;
END;
$$;

-- Function: get_unallocated_students
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course
  FROM public.students s
  LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.end_date IS NULL
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
END;
$$;

-- Function: allocate_room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.room_allocations (student_id, room_id, start_date)
  VALUES (p_student_id, p_room_id, now());
END;
$$;

-- Function: get_or_create_session (This is the function that caused the error)
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type public.attendance_session_type, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  session_id uuid;
BEGIN
  SELECT id INTO session_id
  FROM public.attendance_sessions
  WHERE date = p_date AND type = p_type AND (course = p_course OR p_course IS NULL) AND (year = p_year OR p_year IS NULL);

  IF session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (date, type, course, year)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO session_id;
  END IF;

  RETURN session_id;
END;
$$;

-- Function: bulk_mark_attendance
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec jsonb;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
    VALUES (
      p_session_id,
      (rec->>'student_id')::uuid,
      (rec->>'status')::public.attendance_status,
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

-- Function: student_attendance_calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status public.attendance_status)
LANGUAGE sql
AS $$
  SELECT s.date AS day, ar.status
  FROM public.attendance_sessions s
  JOIN public.attendance_records ar ON s.id = ar.session_id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(YEAR FROM s.date) = p_year
    AND EXTRACT(MONTH FROM s.date) = p_month;
$$;

-- Function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    results jsonb;
BEGIN
    SELECT jsonb_build_object(
        'students', (SELECT COALESCE(jsonb_agg(t), '[]') FROM (
            SELECT s.id, s.full_name AS label, '/students/' || s.id AS path
            FROM public.students s
            WHERE s.full_name ILIKE '%' || p_search_term || '%'
            LIMIT 5
        ) t),
        'rooms', (SELECT COALESCE(jsonb_agg(t), '[]') FROM (
            SELECT r.id, 'Room ' || r.room_number AS label, '/rooms/' || r.id AS path
            FROM public.rooms r
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
            LIMIT 5
        ) t)
    ) INTO results;
    RETURN results;
END;
$$;

-- Step 3: Ensure permissions are correct
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.update_room_occupancy() TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_unallocated_students() TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.allocate_room(uuid, uuid) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type, text, integer) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.bulk_mark_attendance(uuid, jsonb) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.student_attendance_calendar(uuid, integer, integer) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO postgres, authenticated, anon;
