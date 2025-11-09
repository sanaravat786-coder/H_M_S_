/*
          # [DEFINITIVE FUNCTION & SECURITY FIX]
          This script performs a full reset of all custom database functions and triggers to resolve persistent dependency errors and security advisories related to 'Function Search Path Mutable'. It drops all custom triggers and functions, then recreates them with the correct security definitions (`SET search_path = 'public'`) and in the correct dependency order.

          ## Query Description: [This operation will temporarily drop and then recreate all custom application logic in the database (functions and triggers). It is designed to be safe and non-destructive to your data, but it is a significant structural change. No data will be lost. This is the definitive fix for the recurring migration errors and security warnings.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops all custom triggers.
          - Drops all custom functions.
          - Recreates all custom functions with security patches.
          - Recreates all custom triggers linked to the new functions.
          
          ## Security Implications:
          - RLS Status: [Unaffected]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [Unaffected]
          - Triggers: [Recreated]
          - Estimated Impact: [Brief, negligible impact during migration execution. Overall performance will be identical post-migration.]
          */

-- Step 1: Drop existing triggers to remove dependencies
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_update_room_occupancy ON public.room_allocations;

-- Step 2: Drop existing functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);

-- Step 3: Recreate all functions with security hardening

-- Function to create a profile when a new user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number'
  );
  RETURN new;
END;
$$;

-- Function to update room occupancy counts and status
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_id UUID;
    v_active_occupants INT;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        v_room_id := OLD.room_id;
    ELSE
        v_room_id := NEW.room_id;
    END IF;

    -- Recalculate active occupants for the affected room
    SELECT count(*)
    INTO v_active_occupants
    FROM public.room_allocations
    WHERE room_id = v_room_id AND end_date IS NULL;

    -- Update room status and occupants count, but not if it's under maintenance
    UPDATE public.rooms
    SET 
        occupants = v_active_occupants,
        status = CASE 
            WHEN status = 'Maintenance' THEN 'Maintenance'::room_status
            WHEN v_active_occupants > 0 THEN 'Occupied'::room_status
            ELSE 'Vacant'::room_status
        END
    WHERE id = v_room_id;

    RETURN NULL; -- Result is ignored since this is an AFTER trigger
END;
$$;

-- Function to get an existing attendance session or create a new one
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_type text,
    p_course text DEFAULT NULL,
    p_year integer DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

-- Function for universal search across the app
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
            WHERE s.full_name ILIKE '%' || p_search_term || '%'
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
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
        )
    );
END;
$$;

-- Function to get attendance data for a student's calendar view
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ar.date,
        ar.status
    FROM attendance_records ar
    JOIN attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year;
END;
$$;

-- Function to bulk insert or update attendance records
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rec jsonb;
    v_date date;
BEGIN
    SELECT date INTO v_date FROM attendance_sessions WHERE id = p_session_id;

    IF v_date IS NULL THEN
        RAISE EXCEPTION 'Session not found';
    END IF;

    FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
        INSERT INTO attendance_records (session_id, student_id, date, status, note, late_minutes)
        VALUES (
            p_session_id,
            (rec->>'student_id')::uuid,
            v_date,
            (rec->>'status')::attendance_status,
            rec->>'note',
            COALESCE((rec->>'late_minutes')::integer, 0)
        )
        ON CONFLICT (student_id, date) DO UPDATE SET
            status = excluded.status,
            note = excluded.note,
            late_minutes = excluded.late_minutes,
            session_id = excluded.session_id;
    END LOOP;
END;
$$;

-- Function to get all students not currently in a room
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
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.room_allocations ra
    WHERE ra.student_id = s.id AND ra.end_date IS NULL
  )
  ORDER BY s.full_name;
END;
$$;

-- Function to allocate a student to a room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_capacity INT;
    v_current_occupants INT;
BEGIN
    -- Check if student is already allocated
    IF EXISTS (SELECT 1 FROM room_allocations WHERE student_id = p_student_id AND end_date IS NULL) THEN
        RAISE EXCEPTION 'Student is already allocated to a room.';
    END IF;

    -- Check room capacity
    SELECT capacity, occupants INTO v_room_capacity, v_current_occupants FROM rooms WHERE id = p_room_id;
    IF v_current_occupants >= v_room_capacity THEN
        RAISE EXCEPTION 'Room is already full.';
    END IF;

    -- Create new allocation
    INSERT INTO room_allocations (student_id, room_id, start_date)
    VALUES (p_student_id, p_room_id, now());
    
    -- The trigger `trg_update_room_occupancy` will handle updating the room status and count.
END;
$$;

-- Step 4: Recreate the triggers
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_user();

CREATE TRIGGER trg_update_room_occupancy
    AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
    FOR EACH ROW
    EXECUTE PROCEDURE public.update_room_occupancy();
