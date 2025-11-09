/*
          # [DEFINITIVE FUNCTION SECURITY FIX]
          This script provides a comprehensive fix for all function-related security advisories and dependency errors. It safely drops all custom triggers and functions, then recreates them with the necessary security hardening (`SET search_path = public` and `SECURITY DEFINER`). This ensures the database is secure and all dependencies are correctly re-established.

          ## Query Description: [This operation will reset all custom database functions and triggers. It is designed to be safe and non-destructive to your data, but it modifies the core application logic in the database. No data loss is expected.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops all custom triggers.
          - Drops all custom functions.
          - Recreates all functions with `SET search_path = public`.
          - Recreates all triggers.
          
          ## Security Implications:
          - RLS Status: [Unaffected]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [Unaffected]
          - Triggers: [Recreated]
          - Estimated Impact: [Brief, negligible impact during migration execution.]
          */

-- Step 1: Drop dependent triggers first
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_update_room_occupancy ON public.room_allocations;

-- Step 2: Drop all custom functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb[]);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 3: Recreate all functions with security hardening

-- Function: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
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
DECLARE
  current_occupants INT;
  room_capacity INT;
BEGIN
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    SELECT COUNT(*) INTO current_occupants
    FROM public.room_allocations
    WHERE room_id = NEW.room_id AND is_active = true;

    SELECT "capacity" INTO room_capacity
    FROM public.rooms
    WHERE id = NEW.room_id;

    UPDATE public.rooms
    SET 
      occupants = current_occupants,
      status = CASE
        WHEN current_occupants >= room_capacity THEN 'Occupied'::room_status
        WHEN status = 'Maintenance' THEN 'Maintenance'::room_status
        ELSE 'Vacant'::room_status
      END
    WHERE id = NEW.room_id;
  END IF;

  IF (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.is_active = true AND NEW.is_active = false)) THEN
     SELECT COUNT(*) INTO current_occupants
    FROM public.room_allocations
    WHERE room_id = OLD.room_id AND is_active = true;

    UPDATE public.rooms
    SET 
      occupants = current_occupants,
      status = CASE
        WHEN occupants > 0 THEN 'Occupied'::room_status
        WHEN status = 'Maintenance' THEN 'Maintenance'::room_status
        ELSE 'Vacant'::room_status
      END
    WHERE id = OLD.room_id;
  END IF;
  
  RETURN NULL; -- result is ignored since this is an AFTER trigger
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
  LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
END;
$$;
ALTER FUNCTION public.get_unallocated_students() SET search_path = public;

-- Function: allocate_room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  room_capacity INT;
  current_occupants INT;
BEGIN
  -- Check room capacity
  SELECT capacity, occupants INTO room_capacity, current_occupants
  FROM rooms WHERE id = p_room_id;

  IF current_occupants >= room_capacity THEN
    RAISE EXCEPTION 'Room is already full.';
  END IF;

  -- Deactivate any previous active allocation for the student
  UPDATE room_allocations
  SET is_active = false, end_date = NOW()
  WHERE student_id = p_student_id AND is_active = true;

  -- Insert new allocation
  INSERT INTO room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, NOW(), true);
END;
$$;

-- Function: bulk_mark_attendance
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    record jsonb;
BEGIN
    FOREACH record IN ARRAY p_records
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
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$;

-- Function: get_or_create_session
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    session_id uuid;
BEGIN
    SELECT id INTO session_id
    FROM attendance_sessions
    WHERE session_date = p_date
      AND session_type = p_type
      AND (course = p_course OR (course IS NULL AND p_course IS NULL))
      AND (year = p_year OR (year IS NULL AND p_year IS NULL));

    IF session_id IS NULL THEN
        INSERT INTO attendance_sessions (session_date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Function: student_attendance_calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.session_date::date as day,
        ar.status
    FROM attendance_records ar
    JOIN attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.session_date) = p_month
      AND EXTRACT(YEAR FROM s.session_date) = p_year;
END;
$$;
ALTER FUNCTION public.student_attendance_calendar(uuid, integer, integer) SET search_path = public;

-- Function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    results jsonb;
BEGIN
    SELECT jsonb_build_object(
        'students', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', id,
                    'label', full_name,
                    'path', '/students/' || id::text
                )
            )
            FROM students
            WHERE full_name ILIKE '%' || p_search_term || '%'
        ),
        'rooms', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', id,
                    'label', 'Room ' || room_number,
                    'path', '/rooms/' || id::text
                )
            )
            FROM rooms
            WHERE room_number ILIKE '%' || p_search_term || '%'
        )
    ) INTO results;

    RETURN results;
END;
$$;
ALTER FUNCTION public.universal_search(text) SET search_path = public;

-- Step 4: Recreate triggers
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER trg_update_room_occupancy
AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
FOR EACH ROW
EXECUTE FUNCTION public.update_room_occupancy();
