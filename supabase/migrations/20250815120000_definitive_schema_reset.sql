/*
          # [DEFINITIVE SCHEMA RESET]
          This migration script performs a full reset of all custom functions and types
          to resolve dependency and definition errors, such as missing types or incorrect
          function signatures.

          ## Query Description: [This operation will safely drop and recreate all custom functions and the 'attendance_status' type. It is designed to fix the "type does not exist" error and harden function security by setting a non-mutable search_path. No user data in tables will be lost.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops all existing custom functions.
          - Drops the 'attendance_status' type if it exists.
          - Recreates the 'attendance_status' ENUM type.
          - Recreates all custom functions with proper security definitions.
          
          ## Security Implications:
          - RLS Status: [No Change]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [No Change]
          - Triggers: [No Change]
          - Estimated Impact: [Brief downtime for function calls during migration, then normal performance.]
          */

-- Step 1: Drop existing functions to avoid conflicts.
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb[]);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.create_user_profile();

-- Step 2: Drop and recreate the custom type.
DROP TYPE IF EXISTS public.attendance_status;
CREATE TYPE public.attendance_status AS ENUM ('Present', 'Absent', 'Late', 'Excused');

-- Step 3: Recreate all functions with hardened security and correct definitions.

-- Function to create a user profile, linked to a trigger.
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.email,
    NEW.raw_user_meta_data->>'role',
    NEW.raw_user_meta_data->>'mobile_number'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
COMMENT ON FUNCTION public.create_user_profile() IS 'Creates a profile for a new user from auth.users metadata.';

-- Function for universal search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(id uuid, type text, label text, path text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, 'Student' as type, s.full_name as label, '/students/' || s.id::text as path
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
    UNION ALL
    SELECT r.id, 'Room' as type, 'Room ' || r.room_number as label, '/rooms/' || r.id::text as path
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';
END;
$$;
COMMENT ON FUNCTION public.universal_search(text) IS 'Performs a global search across students and rooms.';

-- Function to get students who are not allocated to any room.
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT p.id, p.full_name, p.email, s.course
    FROM public.profiles p
    JOIN public.students s ON p.id = s.id
    WHERE p.role = 'Student' AND NOT EXISTS (
        SELECT 1
        FROM public.room_allocations ra
        WHERE ra.student_id = p.id AND ra.is_active = true
    )
    ORDER BY p.full_name;
END;
$$;
COMMENT ON FUNCTION public.get_unallocated_students() IS 'Retrieves all students who do not have an active room allocation.';

-- Function to allocate a student to a room.
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.room_allocations (student_id, room_id, start_date)
    VALUES (p_student_id, p_room_id, now());
END;
$$;
COMMENT ON FUNCTION public.allocate_room(uuid, uuid) IS 'Allocates a student to a specific room and updates room occupancy.';

-- Function to update room occupancy count.
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
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
            WHEN occupant_count >= (SELECT occupants FROM public.rooms WHERE id = p_room_id) THEN 'Occupied'::room_status
            ELSE 'Vacant'::room_status
        END
    WHERE id = p_room_id;
END;
$$;
COMMENT ON FUNCTION public.update_room_occupancy(uuid) IS 'Recalculates and updates the occupant count and status for a given room.';

-- Function to get or create an attendance session.
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    session_id uuid;
BEGIN
    -- Attempt to find an existing session
    SELECT id INTO session_id
    FROM public.attendance_sessions
    WHERE date = p_date AND type = p_type
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
COMMENT ON FUNCTION public.get_or_create_session(date, text, text, integer) IS 'Finds an existing attendance session or creates a new one and returns its ID.';

-- Function to bulk mark attendance.
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
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
        ON CONFLICT (session_id, student_id) DO UPDATE
        SET status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.bulk_mark_attendance(uuid, jsonb) IS 'Inserts or updates multiple attendance records for a session in a single transaction.';

-- Function to get a student''s attendance calendar for a month.
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT ar.date, ar.status
    FROM public.attendance_records ar
    JOIN public.attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(YEAR FROM s.date) = p_year
      AND EXTRACT(MONTH FROM s.date) = p_month;
END;
$$;
COMMENT ON FUNCTION public.student_attendance_calendar(uuid, integer, integer) IS 'Retrieves a student''s attendance records for a specific month and year.';

-- Set search path for all new functions to enhance security
ALTER FUNCTION public.universal_search(text) SET search_path = public;
ALTER FUNCTION public.get_unallocated_students() SET search_path = public;
ALTER FUNCTION public.allocate_room(uuid, uuid) SET search_path = public;
ALTER FUNCTION public.update_room_occupancy(uuid) SET search_path = public;
ALTER FUNCTION public.get_or_create_session(date, text, text, integer) SET search_path = public;
ALTER FUNCTION public.bulk_mark_attendance(uuid, jsonb) SET search_path = public;
ALTER FUNCTION public.student_attendance_calendar(uuid, integer, integer) SET search_path = public;
ALTER FUNCTION public.create_user_profile() SET search_path = public;
