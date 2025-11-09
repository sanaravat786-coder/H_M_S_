/*
# [Definitive Function Security Fix]
This migration re-creates all custom database functions to be fully secure, resolving all 'Function Search Path Mutable' warnings. It ensures every function has its search_path explicitly set, which is a critical security best practice.

## Query Description:
This script safely replaces all existing custom functions with hardened versions. It does not alter any table data. This is a non-destructive operation designed to enhance application security.

## Metadata:
- Schema-Category: "Security"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by re-running a previous migration)
*/

-- Ensure required types exist before creating functions that use them
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_session_type') THEN
        CREATE TYPE public.attendance_session_type AS ENUM ('NightRoll', 'Morning', 'Evening');
    END IF;
END
$$;

-- 1. Harden user creation trigger function
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

-- 2. Harden student attendance calendar function
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT s.date::date AS day, ar.status::text
  FROM attendance_sessions s
  JOIN attendance_records ar ON s.id = ar.session_id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM s.date) = p_month
    AND EXTRACT(YEAR FROM s.date) = p_year;
END;
$$;

-- 3. Harden room occupancy update function
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_room_id UUID;
BEGIN
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    v_room_id := NEW.room_id;
  ELSIF (TG_OP = 'DELETE') THEN
    v_room_id := OLD.room_id;
  END IF;

  UPDATE rooms
  SET occupants = (SELECT COUNT(*) FROM room_allocations WHERE room_id = v_room_id AND end_date IS NULL)
  WHERE id = v_room_id;

  UPDATE rooms
  SET status = CASE
    WHEN occupants > 0 THEN 'Occupied'
    ELSE 'Vacant'
  END
  WHERE id = v_room_id AND status != 'Maintenance';
  
  RETURN NULL;
END;
$$;

-- 4. Harden universal search function
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(
  id uuid,
  label text,
  type text,
  path text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name AS label, 'students' AS type, '/students/' || s.id::text AS path
  FROM public.students s
  WHERE s.full_name ILIKE '%' || p_search_term || '%'
  LIMIT 5;

  RETURN QUERY
  SELECT r.id, 'Room ' || r.room_number AS label, 'rooms' AS type, '/rooms/' || r.id::text AS path
  FROM public.rooms r
  WHERE r.room_number ILIKE '%' || p_search_term || '%'
  LIMIT 5;
END;
$$;

-- 5. Harden attendance session creation function
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
  WHERE date = p_date AND type = p_type;

  IF session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (date, type, course_filter, year_filter)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO session_id;
  END IF;

  RETURN session_id;
END;
$$;

-- 6. Harden bulk attendance marking function
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN SELECT * FROM jsonb_to_recordset(p_records) AS x(student_id uuid, status text, note text, late_minutes integer)
  LOOP
    INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
    VALUES (p_session_id, rec.student_id, rec.status::attendance_status, rec.note, rec.late_minutes)
    ON CONFLICT (session_id, student_id)
    DO UPDATE SET
      status = EXCLUDED.status,
      note = EXCLUDED.note,
      late_minutes = EXCLUDED.late_minutes;
  END LOOP;
END;
$$;

-- 7. Harden room allocation function
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Deactivate any previous active allocation for the student
  UPDATE public.room_allocations
  SET end_date = NOW()
  WHERE student_id = p_student_id AND end_date IS NULL;

  -- Create new allocation
  INSERT INTO public.room_allocations (student_id, room_id, start_date)
  VALUES (p_student_id, p_room_id, NOW());
END;
$$;

-- 8. Harden unallocated students fetch function
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE (
  id uuid,
  full_name text,
  email text,
  course text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name, p.email, s.course
  FROM public.profiles p
  JOIN public.students s ON p.id = s.id
  WHERE p.role = 'student' AND NOT EXISTS (
    SELECT 1
    FROM public.room_allocations ra
    WHERE ra.student_id = p.id AND ra.end_date IS NULL
  )
  ORDER BY p.full_name;
END;
$$;

-- Grant permissions on all functions
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.student_attendance_calendar(uuid, integer, integer) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.update_room_occupancy() TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type, text, integer) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_mark_attendance(uuid, jsonb) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_room(uuid, uuid) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.get_unallocated_students() TO postgres, authenticated;
