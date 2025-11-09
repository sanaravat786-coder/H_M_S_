/*
# [Function Re-creation and Hardening]
This migration drops and recreates all custom database functions to resolve a migration conflict and harden security.

## Query Description:
This script will first DROP all existing custom functions to prevent errors related to changing function signatures or return types. It then recreates them with their latest logic and explicitly sets the `search_path` to 'public'. This addresses the "Function Search Path Mutable" security advisory and ensures consistent, safe execution.

- **Impact:** All custom functions will be temporarily unavailable during the migration. Application features relying on these functions will fail until the migration is complete. No data will be lost.
- **Safety:** This is a safe operation as it only affects function definitions.
- **Recommendation:** Apply this migration during a low-traffic period if possible.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: false (Requires manual re-application of the previous migration state)

## Structure Details:
- **Dropped Functions:** `universal_search`, `get_unallocated_students`, `allocate_room`, `update_room_occupancy`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`, `create_user_profile`.
- **Dropped Triggers:** `on_auth_user_created`
- **Re-created Functions:** All of the above.
- **Re-created Triggers:** `on_auth_user_created`

## Security Implications:
- RLS Status: Unchanged.
- Policy Changes: No.
- Auth Requirements: Functions are recreated with `SECURITY DEFINER` where appropriate.
- **Fix:** Explicitly sets `search_path = 'public'` for all functions, mitigating the "Function Search Path Mutable" warning.

## Performance Impact:
- Indexes: None.
- Triggers: The `on_auth_user_created` trigger is recreated.
- Estimated Impact: Negligible performance impact after migration.
*/

-- Step 1: Drop existing functions and triggers to avoid conflicts.
-- Order matters for dependencies.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.create_user_profile();
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);


-- Step 2: Recreate functions with hardened security and correct logic.

-- Function: create_user_profile()
-- Creates a profile for a new user and a student record if applicable.
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
  -- Also create a student record if the role is 'Student'
  IF NEW.raw_user_meta_data->>'role' = 'Student' THEN
    INSERT INTO public.students (id, full_name, email, contact)
    VALUES (
      NEW.id,
      NEW.raw_user_meta_data->>'full_name',
      NEW.email,
      NEW.raw_user_meta_data->>'mobile_number'
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

-- Trigger: on_auth_user_created
-- Fires after a new user is created in auth.users.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_user_profile();


-- Function: update_room_occupancy(p_room_id)
-- Updates the occupants count and status of a room.
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void AS $$
DECLARE
  current_occupants INT;
  room_capacity INT;
BEGIN
  -- Get room capacity
  SELECT capacity INTO room_capacity
  FROM public.rooms
  WHERE id = p_room_id;

  -- Calculate current occupants
  SELECT COUNT(*)
  INTO current_occupants
  FROM public.room_allocations
  WHERE room_id = p_room_id AND end_date IS NULL;

  -- Update the room record
  UPDATE public.rooms
  SET
    occupants = current_occupants,
    status = CASE
      WHEN status = 'Maintenance' THEN 'Maintenance'
      WHEN current_occupants >= room_capacity THEN 'Occupied'
      ELSE 'Vacant'
    END
  WHERE id = p_room_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';


-- Function: allocate_room(p_student_id, p_room_id)
-- Allocates a student to a room.
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void AS $$
DECLARE
  room_capacity INT;
  current_occupants INT;
BEGIN
  -- Check room capacity
  SELECT capacity, occupants INTO room_capacity, current_occupants
  FROM public.rooms
  WHERE id = p_room_id;

  IF current_occupants >= room_capacity THEN
    RAISE EXCEPTION 'Room is already full.';
  END IF;

  -- Deactivate any previous active allocation for the student
  UPDATE public.room_allocations
  SET end_date = NOW(), is_active = false
  WHERE student_id = p_student_id AND is_active = true;

  -- Create new allocation
  INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, NOW(), true);

  -- Update room occupancy
  PERFORM public.update_room_occupancy(p_room_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';


-- Function: get_unallocated_students()
-- Returns students not currently allocated to a room.
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text) AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course
  FROM public.students s
  LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public';


-- Function: universal_search(p_search_term)
-- Performs a global search across students and rooms.
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb AS $$
DECLARE
    results jsonb;
BEGIN
    SELECT jsonb_build_object(
        'students', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', s.id,
                'label', s.full_name,
                'path', '/students/' || s.id::text
            )), '[]'::jsonb)
            FROM public.students s
            WHERE s.full_name ILIKE '%' || p_search_term || '%'
        ),
        'rooms', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', r.id,
                'label', 'Room ' || r.room_number,
                'path', '/rooms/' || r.id::text
            )), '[]'::jsonb)
            FROM public.rooms r
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
        )
    ) INTO results;

    RETURN results;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public';


-- Function: get_or_create_session(...)
-- Gets or creates an attendance session and returns its ID.
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
RETURNS uuid AS $$
DECLARE
  session_id uuid;
BEGIN
  -- Try to find an existing session
  SELECT id INTO session_id
  FROM public.attendance_sessions
  WHERE session_date = p_date
    AND session_type = p_type
    AND (p_course IS NULL OR course = p_course)
    AND (p_year IS NULL OR year = p_year)
  LIMIT 1;

  -- If not found, create it
  IF session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (session_date, session_type, course, year)
    VALUES (p_date, p_type, p_course, p_year)
    RETURNING id INTO session_id;
  END IF;

  RETURN session_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';


-- Function: bulk_mark_attendance(...)
-- Upserts attendance records for a session.
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';


-- Function: student_attendance_calendar(...)
-- Fetches attendance data for a student's calendar view.
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status) AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.session_date as day,
    ar.status
  FROM public.attendance_records ar
  JOIN public.attendance_sessions s ON ar.session_id = s.id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM s.session_date) = p_month
    AND EXTRACT(YEAR FROM s.session_date) = p_year
  ORDER BY s.session_date;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = 'public';
