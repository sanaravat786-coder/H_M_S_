/*
# [Definitive Function Security Fix]
[This script drops and recreates all custom database functions with the correct security settings (SECURITY DEFINER and SET search_path) to resolve all outstanding 'Function Search Path Mutable' security warnings.]

## Query Description: [This operation will safely drop and recreate all custom functions in the 'public' schema. It is designed to be non-destructive to data and will resolve all remaining security advisories related to function search paths. No data will be lost.]

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Functions affected: handle_new_user, get_unallocated_students, allocate_room, update_room_occupancy, get_or_create_session, bulk_mark_attendance, student_attendance_calendar, universal_search.
- Triggers affected: on_auth_user_created (dropped and recreated).

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges to run migrations.
- This script resolves all known 'Function Search Path Mutable' warnings.

## Performance Impact:
- Indexes: None
- Triggers: Recreated
- Estimated Impact: Negligible. There will be a brief moment where functions are unavailable during the migration.
*/

-- Step 1: Drop dependent objects first to avoid errors.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop all existing custom functions to ensure a clean re-creation.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb[]);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 3: Recreate all functions with security best practices.

-- Function 1: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role)
  VALUES (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.email,
    new.raw_user_meta_data ->> 'role'
  );
  return new;
end;
$$;

-- Function 2: get_unallocated_students
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
SECURITY DEFINER
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

-- Function 3: allocate_room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.room_allocations
  SET is_active = false, end_date = now()
  WHERE student_id = p_student_id AND is_active = true;

  INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, now(), true);

  PERFORM public.update_room_occupancy(p_room_id);
END;
$$;

-- Function 4: update_room_occupancy
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  occupant_count integer;
BEGIN
  SELECT count(*)
  INTO occupant_count
  FROM public.room_allocations
  WHERE room_id = p_room_id AND is_active = true;

  UPDATE public.rooms
  SET occupants = occupant_count,
      status = CASE
                 WHEN occupant_count > 0 THEN 'Occupied'::public.room_status
                 ELSE 'Vacant'::public.room_status
               END
  WHERE id = p_room_id AND status != 'Maintenance'::public.room_status;
END;
$$;

-- Function 5: get_or_create_session
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_type public.attendance_session_type,
    p_course text,
    p_year integer
)
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
    WHERE date = p_date
      AND session_type = p_type
      AND (course = p_course OR p_course IS NULL)
      AND (year = p_year OR p_year IS NULL);

    IF session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Function 6: bulk_mark_attendance
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
            (rec->>'status')::public.attendance_status,
            rec->>'note',
            (rec->>'late_minutes')::integer
        )
        ON CONFLICT (session_id, student_id) DO UPDATE
        SET status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$;

-- Function 7: student_attendance_calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status public.attendance_status, session_type public.attendance_session_type, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.date AS day,
        ar.status,
        s.session_type,
        ar.note
    FROM public.attendance_sessions s
    JOIN public.attendance_records ar ON s.id = ar.session_id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY s.date;
END;
$$;

-- Function 8: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    students_json json;
    rooms_json json;
    result_json json;
BEGIN
    SELECT json_agg(json_build_object(
        'id', s.id,
        'label', s.full_name,
        'path', '/students/' || s.id::text
    ))
    INTO students_json
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%';

    SELECT json_agg(json_build_object(
        'id', r.id,
        'label', 'Room ' || r.room_number,
        'path', '/rooms/' || r.id::text
    ))
    INTO rooms_json
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';

    SELECT json_build_object(
        'students', COALESCE(students_json, '[]'::json),
        'rooms', COALESCE(rooms_json, '[]'::json)
    )
    INTO result_json;

    RETURN result_json;
END;
$$;

-- Step 4: Recreate the trigger on auth.users.
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();
