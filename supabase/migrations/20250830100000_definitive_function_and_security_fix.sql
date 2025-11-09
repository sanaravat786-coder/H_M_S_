/*
# [Definitive Function and Security Fix]
This migration script provides a comprehensive fix for all custom database functions and their associated triggers. It resolves persistent dependency errors and "Function Search Path Mutable" security advisories by completely rebuilding the database's procedural logic in the correct order.

## Query Description: [This operation will safely drop and recreate all custom functions and triggers to apply security hardening and fix dependency issues. It is designed to be a definitive solution to the recent series of migration errors and security warnings. No data will be lost, but it is a significant structural change.]

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["Medium"]
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Drops all custom triggers (`on_auth_user_created`, `trg_update_room_occupancy`).
- Drops all custom functions (`handle_new_user`, `update_room_occupancy`, `get_or_create_session`, `universal_search`, `get_unallocated_students`, `allocate_room`, `bulk_mark_attendance`, `student_attendance_calendar`).
- Recreates all functions with `SET search_path = public` and `SECURITY DEFINER` where appropriate.
- Recreates all triggers and links them to the new, secure functions.

## Security Implications:
- RLS Status: [No Change]
- Policy Changes: [No]
- Auth Requirements: [None]
- This script explicitly sets the `search_path` for all custom functions, which is the primary fix for the outstanding security advisories.

## Performance Impact:
- Indexes: [No Change]
- Triggers: [Recreated]
- Estimated Impact: [Negligible. This is a one-time structural change.]
*/

-- Step 1: Drop dependent triggers first to avoid dependency errors.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_update_room_occupancy ON public.room_allocations;

-- Step 2: Drop all custom functions to ensure a clean state.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);

-- Step 3: Recreate all functions with security hardening.

-- Function to handle new user creation and profile insertion.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
  -- If the user is a student, create a corresponding entry in the students table
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

-- Function to update room occupancy count and status.
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_id UUID;
BEGIN
    -- Determine the room_id from either the old or new record
    IF TG_OP = 'DELETE' THEN
        v_room_id := OLD.room_id;
    ELSE
        v_room_id := NEW.room_id;
    END IF;

    -- Update the occupants count and status for the specific room
    UPDATE public.rooms
    SET
        occupants = (
            SELECT COUNT(*)
            FROM public.room_allocations
            WHERE room_id = v_room_id AND is_active = true
        ),
        status = CASE
            WHEN (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = v_room_id AND is_active = true) > 0 THEN 'Occupied'::room_status
            ELSE 'Vacant'::room_status
        END
    WHERE id = v_room_id;

    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$$;

-- Function to get or create an attendance session.
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    session_id uuid;
BEGIN
    -- Attempt to find an existing session
    SELECT id INTO session_id
    FROM public.attendance_sessions
    WHERE date = p_date
      AND type = p_type
      AND (course IS NULL OR course = p_course)
      AND (year IS NULL OR year = p_year)
    LIMIT 1;

    -- If not found, create a new one
    IF session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (date, type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Function for universal search across students and rooms.
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    results jsonb;
BEGIN
    SELECT jsonb_build_object(
        'students', (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'id', s.id,
                    'label', s.full_name,
                    'path', '/students/' || s.id
                )
            ), '[]'::jsonb)
            FROM public.students s
            WHERE s.full_name ILIKE '%' || p_search_term || '%'
        ),
        'rooms', (
            SELECT COALESCE(jsonb_agg(
                jsonb_build_object(
                    'id', r.id,
                    'label', 'Room ' || r.room_number,
                    'path', '/rooms/' || r.id
                )
            ), '[]'::jsonb)
            FROM public.rooms r
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
        )
    ) INTO results;

    RETURN results;
END;
$$;

-- Function to get all students not currently allocated to a room.
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

-- Function to allocate a student to a room.
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.room_allocations (student_id, room_id, start_date)
    VALUES (p_student_id, p_room_id, NOW());
END;
$$;

-- Function to bulk insert or update attendance records.
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

-- Function to retrieve a student's attendance for a given month/year.
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.date::date AS day,
        ar.status
    FROM public.attendance_records ar
    JOIN public.attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY s.date;
END;
$$;

-- Step 4: Recreate the triggers.

-- Trigger to create a profile when a new user signs up.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Trigger to update room occupancy after an allocation change.
CREATE TRIGGER trg_update_room_occupancy
  AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
  FOR EACH ROW
  EXECUTE FUNCTION public.update_room_occupancy();
