/*
# [DEFINITIVE] Harden All Functions &amp; Fix Trigger Dependencies
This migration script resolves a critical dependency issue that prevented previous migrations from running. It also hardens all custom database functions by setting a secure `search_path`, which fixes all outstanding security advisories.

## Query Description:
This operation will safely drop and recreate all custom functions and their associated triggers.
1.  **Dependency Fix**: The `on_auth_user_created` trigger is dropped before its dependent function (`handle_new_user`) is modified, resolving the migration error.
2.  **Security Hardening**: All functions are recreated with `SET search_path = public` to prevent potential security vulnerabilities, addressing all `Function Search Path Mutable` warnings.
3.  **Integrity**: The functions and triggers are recreated with their correct definitions, ensuring the application logic remains intact.

This is a safe and necessary operation to ensure the database is both secure and in a consistent state.

## Metadata:
- Schema-Category: ["Structural", "Security"]
- Impact-Level: ["Medium"]
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Drops and recreates triggers: `on_auth_user_created`, `update_room_occupancy_trigger`
- Drops and recreates functions: `handle_new_user`, `universal_search`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`, `update_room_occupancy`, `get_unallocated_students`, `allocate_room`, `update_room_occupancy_on_change`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges
- Fixes all `Function Search Path Mutable` security warnings.

## Performance Impact:
- Indexes: None
- Triggers: Recreated
- Estimated Impact: Negligible. A brief moment where triggers are inactive during the migration.
*/

-- Step 1: Drop dependent triggers first to avoid dependency errors.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS update_room_occupancy_trigger ON public.room_allocations;

-- Step 2: Drop all custom functions that will be recreated.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy_on_change();

-- Step 3: Recreate all functions with security hardening (SET search_path).

-- Function to handle new user profile creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.email,
    NEW.raw_user_meta_data->>'role'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- Function for universal search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(id uuid, label text, type text, path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.full_name AS label, 'Students' AS type, '/students/' || s.id::text AS path
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
    UNION ALL
    SELECT r.id, 'Room ' || r.room_number AS label, 'Rooms' AS type, '/rooms/' || r.id::text AS path
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';
END;
$$;

-- Function to get or create an attendance session
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type public.attendance_session_type, p_course text, p_year integer)
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
    WHERE date = p_date AND type = p_type AND (course IS NULL OR course = p_course) AND (year IS NULL OR year = p_year);

    IF session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (date, type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Function for bulk marking attendance
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
        INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
        VALUES (
            p_session_id,
            (record->>'student_id')::uuid,
            (record->>'status')::public.attendance_status,
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

-- Function to get a student's attendance calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day text, status public.attendance_status, session_type public.attendance_session_type, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.date::text AS day,
        ar.status,
        s.type AS session_type,
        ar.note
    FROM public.attendance_sessions s
    JOIN public.attendance_records ar ON s.id = ar.session_id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY s.date;
END;
$$;

-- Function to update room occupancy count and status
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    active_occupants integer;
BEGIN
    SELECT count(*)
    INTO active_occupants
    FROM public.room_allocations
    WHERE room_id = p_room_id AND is_active = true;

    UPDATE public.rooms
    SET
        occupants = active_occupants,
        status = CASE
            WHEN status = 'Maintenance' THEN 'Maintenance'
            WHEN active_occupants > 0 THEN 'Occupied'
            ELSE 'Vacant'
        END
    WHERE id = p_room_id;
END;
$$;

-- Trigger function for room occupancy changes
CREATE OR REPLACE FUNCTION public.update_room_occupancy_on_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        PERFORM public.update_room_occupancy(OLD.room_id);
    ELSE
        PERFORM public.update_room_occupancy(NEW.room_id);
        IF (TG_OP = 'UPDATE' AND OLD.room_id <> NEW.room_id) THEN
            PERFORM public.update_room_occupancy(OLD.room_id);
        END IF;
    END IF;
    RETURN NULL;
END;
$$;


-- Function to get unallocated students
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
        WHERE ra.student_id = s.id AND ra.is_active = true
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
    old_room_id uuid;
BEGIN
    -- Find and store the old room ID before deactivating
    SELECT room_id INTO old_room_id
    FROM public.room_allocations
    WHERE student_id = p_student_id AND is_active = true;

    -- Deactivate any previous active allocation for the student
    UPDATE public.room_allocations
    SET is_active = false, end_date = now()
    WHERE student_id = p_student_id AND is_active = true;

    -- Create new allocation
    INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
    VALUES (p_student_id, p_room_id, now(), true);
    
    -- Manually trigger occupancy update for the old room if it exists
    IF old_room_id IS NOT NULL AND old_room_id <> p_room_id THEN
        PERFORM public.update_room_occupancy(old_room_id);
    END IF;
END;
$$;

-- Step 4: Recreate the triggers that were dropped.
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER update_room_occupancy_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
FOR EACH ROW EXECUTE FUNCTION public.update_room_occupancy_on_change();
