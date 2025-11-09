/*
  # [MASTER SCRIPT] Definitive Function Security Fix
  [This script drops and recreates all custom functions and triggers to resolve all 'Function Search Path Mutable' security advisories and dependency errors.]

  ## Query Description: [This is a comprehensive reset of all custom database logic. It will:
  1. Temporarily remove all triggers.
  2. Delete all custom functions.
  3. Recreate all functions from scratch with proper security definitions.
  4. Re-establish all triggers.
  This operation is designed to be safe and should not impact existing data, but it fundamentally changes the database's procedural code. No backup is strictly required, but it is always best practice before significant schema changes.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: false
  - Reversible: false
  
  ## Structure Details:
  - Drops Triggers: [on_auth_user_created, trg_update_room_occupancy]
  - Drops Functions: [handle_new_user, update_room_occupancy, universal_search, get_unallocated_students, allocate_room, get_or_create_session, bulk_mark_attendance, student_attendance_calendar]
  - Creates Functions: All of the above with security hardening.
  - Creates Triggers: All of the above.
  
  ## Security Implications:
  - RLS Status: [Unaffected]
  - Policy Changes: [No]
  - Auth Requirements: [None for execution]
  - Fixes: This script is intended to resolve all outstanding 'Function Search Path Mutable' warnings.
  
  ## Performance Impact:
  - Indexes: [Unaffected]
  - Triggers: [Recreated]
  - Estimated Impact: [Brief, negligible impact during execution. Post-execution performance should be identical.]
*/

-- Step 1: Drop existing triggers to remove dependencies
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_update_room_occupancy ON public.room_allocations;

-- Step 2: Drop existing functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(integer, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);


-- Step 3: Recreate all functions with security hardening

-- Function to handle new user creation and profile setup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number'
  );
  
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

-- Function to update room occupancy counts automatically
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  -- After an insert or update, recalculate for the new room_id
  IF (TG_OP = 'INSERT' OR TG_OP = 'UPDATE') THEN
    IF NEW.room_id IS NOT NULL THEN
      UPDATE public.rooms
      SET occupants = (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = NEW.room_id AND is_active = true)
      WHERE id = NEW.room_id;
    END IF;
  END IF;

  -- After a delete or update, recalculate for the old room_id
  IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
    -- Make sure we don't re-run for the same room_id on update
    IF OLD.room_id IS NOT NULL AND OLD.room_id IS DISTINCT FROM NEW.room_id THEN
      UPDATE public.rooms
      SET occupants = (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = OLD.room_id AND is_active = true)
      WHERE id = OLD.room_id;
    END IF;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Function for universal search across students and rooms
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_students jsonb;
  v_rooms jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object(
    'id', s.id,
    'label', s.full_name,
    'path', '/students/' || s.id::text
  ))
  INTO v_students
  FROM students s
  WHERE s.full_name ILIKE '%' || p_search_term || '%';

  SELECT jsonb_agg(jsonb_build_object(
    'id', r.id,
    'label', 'Room ' || r.room_number,
    'path', '/rooms/' || r.id::text
  ))
  INTO v_rooms
  FROM rooms r
  WHERE r.room_number ILIKE '%' || p_search_term || '%';

  RETURN jsonb_build_object(
    'students', COALESCE(v_students, '[]'::jsonb),
    'rooms', COALESCE(v_rooms, '[]'::jsonb)
  );
END;
$$;

-- Function to get students who are not allocated to any room
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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

-- Function to allocate a student to a room with capacity checks
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_occupants int;
  v_capacity int;
BEGIN
  IF EXISTS (SELECT 1 FROM room_allocations WHERE student_id = p_student_id AND is_active = true) THEN
    RAISE EXCEPTION 'Student is already allocated to a room.';
  END IF;

  SELECT occupants, (CASE type WHEN 'Single' THEN 1 WHEN 'Double' THEN 2 WHEN 'Triple' THEN 3 ELSE 0 END)
  INTO v_occupants, v_capacity
  FROM rooms
  WHERE id = p_room_id;

  IF v_occupants >= v_capacity THEN
    RAISE EXCEPTION 'Room is already at full capacity.';
  END IF;

  INSERT INTO room_allocations (student_id, room_id, start_date)
  VALUES (p_student_id, p_room_id, now());
END;
$$;

-- Function to get or create an attendance session
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_type text,
    p_course text DEFAULT NULL,
    p_year integer DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
    v_session_id integer;
BEGIN
    SELECT id INTO v_session_id
    FROM attendance_sessions
    WHERE session_date = p_date
      AND session_type = p_type
      AND (p_course IS NULL OR course = p_course)
      AND (p_year IS NULL OR year = p_year);

    IF v_session_id IS NULL THEN
        INSERT INTO attendance_sessions (session_date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO v_session_id;
    END IF;

    RETURN v_session_id;
END;
$$;

-- Function for bulk marking attendance records
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(
    p_session_id integer,
    p_records jsonb
)
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
            record->>'status',
            record->>'note',
            COALESCE((record->>'late_minutes')::integer, 0)
        )
        ON CONFLICT (session_id, student_id)
        DO UPDATE SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$;

-- Function to get monthly attendance for a student
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(
    p_student_id uuid,
    p_month integer,
    p_year integer
)
RETURNS TABLE(day date, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
    RETURN QUERY
    SELECT
        "as".session_date as day,
        ar.status
    FROM attendance_records ar
    JOIN attendance_sessions "as" ON ar.session_id = "as".id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM "as".session_date) = p_month
      AND EXTRACT(YEAR FROM "as".session_date) = p_year;
END;
$$;

-- Step 4: Recreate the triggers
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER trg_update_room_occupancy
  AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
  FOR EACH ROW EXECUTE FUNCTION public.update_room_occupancy();
