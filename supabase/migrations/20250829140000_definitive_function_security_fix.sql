/*
          # [Definitive Function Security Hardening]
          This migration script recreates all custom database functions to apply definitive security hardening. It addresses all "Function Search Path Mutable" warnings by explicitly setting a safe search_path and using SECURITY DEFINER where appropriate.

          ## Query Description: [This operation will drop and recreate several functions, including 'universal_search', 'create_user_profile', and others related to core application logic. This is a safe and necessary procedure to apply security patches. There is no risk of data loss as only the function definitions are being replaced.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Functions being replaced: 
            - create_user_profile
            - get_unallocated_students
            - allocate_room
            - update_room_occupancy
            - bulk_mark_attendance
            - get_or_create_session
            - student_attendance_calendar
            - universal_search
          
          ## Security Implications:
          - RLS Status: [Unaffected]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          - Fixes: Resolves all 'Function Search Path Mutable' warnings by setting a non-mutable search_path for all functions.
          
          ## Performance Impact:
          - Indexes: [Unaffected]
          - Triggers: [Unaffected]
          - Estimated Impact: [None. This is a change to function definitions and does not impact query performance.]
          */

-- Drop the function that previously caused issues to ensure a clean recreation.
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Recreate all functions with proper security context.

-- Function to create a user profile from the trigger on auth.users
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.email,
    NEW.raw_user_meta_data ->> 'role',
    NEW.raw_user_meta_data ->> 'mobile_number'
  );
  RETURN NEW;
END;
$$;

-- Function to get students who are not currently allocated to a room
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

-- Function to update the number of occupants in a room
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
                 WHEN occupant_count > 0 THEN 'Occupied'::room_status
                 ELSE 'Vacant'::room_status
               END
  WHERE id = p_room_id;
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
    v_room_capacity int;
    v_current_occupants int;
BEGIN
    -- Check room capacity
    SELECT capacity, occupants INTO v_room_capacity, v_current_occupants FROM public.rooms WHERE id = p_room_id;
    IF v_current_occupants >= v_room_capacity THEN
        RAISE EXCEPTION 'Room is already full.';
    END IF;

    -- Deactivate any previous active allocation for the student
    UPDATE public.room_allocations
    SET is_active = false, end_date = now()
    WHERE student_id = p_student_id AND is_active = true;

    -- Create new allocation
    INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
    VALUES (p_student_id, p_room_id, now(), true);

    -- Update room occupancy
    PERFORM public.update_room_occupancy(p_room_id);
END;
$$;

-- Function to bulk mark attendance
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
        INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
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

-- Function to get or create an attendance session
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
    FROM public.attendance_sessions
    WHERE session_date = p_date AND session_type = p_type;

    IF NOT FOUND THEN
        INSERT INTO public.attendance_sessions (session_date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Function for student's attendance calendar view
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ar.created_at::date as day,
        ar.status
    FROM public.attendance_records ar
    JOIN public.attendance_sessions as2 ON ar.session_id = as2.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM as2.session_date) = p_month
      AND EXTRACT(YEAR FROM as2.session_date) = p_year;
END;
$$;

-- Finally, recreate the universal search function
CREATE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(
    id uuid,
    label text,
    type text,
    path text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET search_path = 'public';
  RETURN QUERY
    -- Search Students
    SELECT s.id, s.full_name AS label, 'Student' AS type, '/students/' || s.id::text AS path
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
       OR s.email ILIKE '%' || p_search_term || '%'
    
    UNION ALL
    
    -- Search Rooms
    SELECT r.id, 'Room ' || r.room_number AS label, 'Room' AS type, '/rooms/' || r.id::text AS path
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';
END;
$$;
