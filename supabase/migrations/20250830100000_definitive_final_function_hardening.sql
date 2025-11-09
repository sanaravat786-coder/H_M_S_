/*
# [Definitive Final Function Hardening]
This script provides a final, comprehensive hardening of all custom database functions to resolve any remaining 'Function Search Path Mutable' security warnings. It safely drops and recreates all functions and their dependent triggers to ensure their `search_path` is explicitly and securely set.

## Query Description: [This operation will temporarily drop and then recreate all custom application functions and the user creation trigger. It is a safe, non-destructive operation designed to finalize the application's security posture. No data will be lost.]

## Metadata:
- Schema-Category: ["Structural", "Security"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Drops and recreates the trigger: `on_auth_user_created` on `auth.users`.
- Drops and recreates the functions:
  - `handle_new_user()`
  - `get_or_create_session()`
  - `bulk_mark_attendance()`
  - `student_attendance_calendar()`
  - `update_room_occupancy()`
  - `get_unallocated_students()`
  - `allocate_room()`
  - `universal_search()`
- Ensures `attendance_session_type` type exists.

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [No]
- Auth Requirements: [None]
- This script resolves all 'Function Search Path Mutable' warnings by setting a fixed `search_path` for all functions.

## Performance Impact:
- Indexes: [None]
- Triggers: [Recreated]
- Estimated Impact: [Negligible. A brief, one-time operation.]
*/

-- Step 1: Drop the dependent trigger first.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 2: Drop all existing functions to ensure a clean slate.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 3: Ensure custom types exist.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_session_type') THEN
        CREATE TYPE public.attendance_session_type AS ENUM ('NightRoll', 'Morning', 'Evening');
    END IF;
END$$;


-- Step 4: Recreate all functions with security best practices.

-- Function: handle_new_user
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
    new.raw_user_meta_data->>'full_name',
    new.email,
    new.raw_user_meta_data->>'role'
  );
  return new;
END;
$$;

-- Function: get_or_create_session
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type public.attendance_session_type, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session_id uuid;
BEGIN
    -- Attempt to find an existing session
    SELECT id INTO v_session_id
    FROM attendance_sessions
    WHERE date = p_date
      AND type = p_type
      AND (course = p_course OR (course IS NULL AND p_course IS NULL))
      AND (year = p_year OR (year IS NULL AND p_year IS NULL));

    -- If not found, create a new one
    IF v_session_id IS NULL THEN
        INSERT INTO attendance_sessions (date, type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO v_session_id;
    END IF;

    RETURN v_session_id;
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
    record jsonb;
BEGIN
    FOR record IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
        INSERT INTO attendance_records (session_id, student_id, status, note, late_minutes)
        VALUES (
            p_session_id,
            (record->>'student_id')::uuid,
            (record->>'status')::public.attendance_status,
            record->>'note',
            (record->>'late_minutes')::integer
        )
        ON CONFLICT (session_id, student_id) DO UPDATE SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$;

-- Function: student_attendance_calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status public.attendance_status, session_type public.attendance_session_type, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT s.date AS day, ar.status, s.type as session_type, ar.note
    FROM attendance_records ar
    JOIN attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY s.date;
END;
$$;

-- Function: update_room_occupancy
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_occupants INT;
BEGIN
    SELECT count(*)
    INTO active_occupants
    FROM room_allocations
    WHERE room_id = p_room_id AND is_active = true;

    UPDATE rooms
    SET occupants = active_occupants,
        status = CASE
            WHEN status = 'Maintenance' THEN 'Maintenance'
            WHEN active_occupants > 0 THEN 'Occupied'
            ELSE 'Vacant'
        END
    WHERE id = p_room_id;
END;
$$;

-- Function: get_unallocated_students
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.full_name, s.email, s.course
    FROM students s
    LEFT JOIN room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
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
    INSERT INTO room_allocations (student_id, room_id, start_date)
    VALUES (p_student_id, p_room_id, now());

    PERFORM update_room_occupancy(p_room_id);
END;
$$;

-- Function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_search_term text := '%' || p_search_term || '%';
BEGIN
    RETURN json_build_object(
        'students', (
            SELECT json_agg(
                json_build_object(
                    'id', s.id,
                    'label', s.full_name,
                    'path', '/students/' || s.id
                )
            )
            FROM students s
            WHERE s.full_name ILIKE v_search_term OR s.email ILIKE v_search_term
        ),
        'rooms', (
            SELECT json_agg(
                json_build_object(
                    'id', r.id,
                    'label', 'Room ' || r.room_number,
                    'path', '/rooms/' || r.id
                )
            )
            FROM rooms r
            WHERE r.room_number ILIKE v_search_term
        )
    );
END;
$$;

-- Step 5: Recreate the trigger
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 6: Grant permissions
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type, text, integer) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.bulk_mark_attendance(uuid, jsonb) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.student_attendance_calendar(uuid, integer, integer) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.update_room_occupancy(uuid) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_unallocated_students() TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.allocate_room(uuid, uuid) TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO postgres, authenticated, anon;
