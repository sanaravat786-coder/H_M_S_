/*
          # [Migration] Definitive Function Security Fix
          This migration drops and recreates all custom database functions to apply consistent security settings, resolving the "Function Search Path Mutable" advisory.

          ## Query Description: This operation will temporarily drop and then immediately recreate all application-specific functions. There is no risk of data loss, but for a brief moment during the migration, these functions will be unavailable. This is the definitive fix to ensure all functions have their search_path explicitly set, preventing potential SQL injection vulnerabilities.
          
          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Drops and recreates the following functions:
            - handle_new_user()
            - get_unallocated_students()
            - allocate_room(uuid, uuid)
            - update_room_occupancy(uuid)
            - bulk_mark_attendance(uuid, jsonb)
            - get_or_create_session(date, text, text, integer)
            - student_attendance_calendar(uuid, integer, integer)
            - universal_search(text)
          - Drops and recreates the 'on_auth_user_created' trigger.
          
          ## Security Implications:
          - RLS Status: Unchanged
          - Policy Changes: No
          - Auth Requirements: None
          - Fixes "Function Search Path Mutable" advisory by setting a static search_path for all functions.
          
          ## Performance Impact:
          - Indexes: None
          - Triggers: Recreated
          - Estimated Impact: Negligible. A brief, one-time operation.
          */

-- Step 1: Drop all existing custom functions and triggers to prevent conflicts.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 2: Recreate the function to handle new user profile creation.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, mobile_number, email)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number',
    new.email
  );
  return new;
END;
$$;

-- Step 3: Recreate the trigger on the auth.users table.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Step 4: Recreate the function to get unallocated students.
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

-- Step 5: Recreate the function to allocate a room.
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Create new allocation
  INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, now(), true);
  -- The occupancy and status update is handled by a trigger on the room_allocations table.
END;
$$;

-- Step 6: Recreate the function to update room occupancy.
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_occupant_count int;
BEGIN
  SELECT COUNT(*) INTO v_occupant_count FROM room_allocations WHERE room_id = p_room_id AND is_active = true;
  UPDATE rooms SET occupants = v_occupant_count, status = CASE WHEN v_occupant_count > 0 THEN 'Occupied'::room_status ELSE 'Vacant'::room_status END WHERE id = p_room_id;
END;
$$;

-- Step 7: Recreate the function for bulk attendance marking.
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
            (record->>'status')::attendance_status,
            record->>'note',
            (record->>'late_minutes')::int
        )
        ON CONFLICT (session_id, student_id)
        DO UPDATE SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$;

-- Step 8: Recreate the function to get or create an attendance session.
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text DEFAULT NULL, p_year integer DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_session_id uuid;
BEGIN
    SELECT id INTO v_session_id
    FROM attendance_sessions
    WHERE session_date = p_date
      AND session_type = p_type
      AND (p_course IS NULL OR course = p_course)
      AND (p_year IS NULL OR year = p_year)
    LIMIT 1;

    IF v_session_id IS NULL THEN
        INSERT INTO attendance_sessions (session_date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO v_session_id;
    END IF;

    RETURN v_session_id;
END;
$$;

-- Step 9: Recreate the function for the student attendance calendar view.
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.session_date AS day,
        ar.status
    FROM attendance_records ar
    JOIN attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.session_date) = p_month
      AND EXTRACT(YEAR FROM s.session_date) = p_year;
END;
$$;

-- Step 10: Recreate the universal search function.
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN jsonb_build_object(
    'students', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'label', s.full_name,
          'path', '/students/' || s.id
        )
      )
      FROM students s
      WHERE s.full_name ILIKE '%' || p_search_term || '%'
    ),
    'rooms', (
      SELECT jsonb_agg(
        jsonb_build_object(
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
