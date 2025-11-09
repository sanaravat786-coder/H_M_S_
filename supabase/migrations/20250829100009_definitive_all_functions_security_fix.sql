/*
          # [Definitive Function Security Fix]
          This script drops and recreates all custom functions in the 'public' schema to ensure they are secure and have a fixed search_path. This resolves all "Function Search Path Mutable" security advisories and ensures database stability.

          ## Query Description: [This operation will safely reset all custom database functions to their latest secure versions. It is a non-destructive operation for your data, but it is critical for application security and functionality. No backup is required, but this is the final planned database schema change.]
          
          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: [false]
          - Reversible: [false]
          
          ## Structure Details:
          - Drops and recreates all custom functions: handle_new_user, get_or_create_session, bulk_mark_attendance, student_attendance_calendar, universal_search, get_unallocated_students, allocate_room, update_room_occupancy.
          - Drops and recreates associated triggers for handle_new_user and update_room_occupancy.
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          - This migration is designed specifically to FIX all outstanding security advisories related to function search paths.
          
          ## Performance Impact:
          - Indexes: [None]
          - Triggers: [Recreated]
          - Estimated Impact: [Low. There will be a brief moment where functions are unavailable during the migration, but it should be seamless.]
          */

-- This script will drop and recreate all custom functions in the 'public' schema
-- to ensure they are secure and have a fixed search_path. This resolves
-- all "Function Search Path Mutable" security advisories.

-- Function 1: handle_new_user()
-- This function is attached to a trigger on auth.users. It must be dropped with CASCADE.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
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
-- Recreate the trigger
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Function 2: get_or_create_session()
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type, text, integer);
CREATE OR REPLACE FUNCTION public.get_or_create_session(
    p_date date,
    p_type public.attendance_session_type,
    p_course text,
    p_year integer
)
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
    WHERE date = p_date AND type = p_type;

    IF session_id IS NULL THEN
        INSERT INTO attendance_sessions (date, type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Function 3: bulk_mark_attendance()
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(
    p_session_id uuid,
    p_records jsonb
)
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
        ON CONFLICT (session_id, student_id)
        DO UPDATE SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$;

-- Function 4: student_attendance_calendar()
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(
    p_student_id uuid,
    p_month integer,
    p_year integer
)
RETURNS TABLE(day date, session_type public.attendance_session_type, status public.attendance_status, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.date AS day,
        s.type AS session_type,
        ar.status,
        ar.note
    FROM
        attendance_sessions s
    JOIN
        attendance_records ar ON s.id = ar.session_id
    WHERE
        ar.student_id = p_student_id
        AND EXTRACT(MONTH FROM s.date) = p_month
        AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY
        s.date;
END;
$$;


-- Function 5: universal_search()
DROP FUNCTION IF EXISTS public.universal_search(text);
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
                    'path', '/students/' || s.id::text
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
                    'path', '/rooms/' || r.id::text
                )
            )
            FROM rooms r
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
        )
    );
END;
$$;

-- Function 6: get_unallocated_students()
DROP FUNCTION IF EXISTS public.get_unallocated_students();
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

-- Function 7: allocate_room()
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
CREATE OR REPLACE FUNCTION public.allocate_room(
    p_student_id uuid,
    p_room_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Deactivate any previous active allocation for the student
    UPDATE room_allocations
    SET is_active = false, end_date = now()
    WHERE student_id = p_student_id AND is_active = true;

    -- Create new allocation
    INSERT INTO room_allocations (student_id, room_id, start_date, is_active)
    VALUES (p_student_id, p_room_id, now(), true);
END;
$$;


-- Function 8: update_room_occupancy()
DROP FUNCTION IF EXISTS public.update_room_occupancy() CASCADE;
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_id uuid;
    v_occupant_count int;
BEGIN
    -- Determine which room_id to update based on the operation
    IF (TG_OP = 'DELETE') THEN
        v_room_id := OLD.room_id;
    ELSE
        v_room_id := NEW.room_id;
    END IF;

    -- Recalculate the number of active occupants for the affected room
    SELECT count(*)
    INTO v_occupant_count
    FROM room_allocations
    WHERE room_id = v_room_id AND is_active = true;

    -- Update the rooms table
    UPDATE rooms
    SET occupants = v_occupant_count,
        status = CASE
            WHEN v_occupant_count > 0 THEN 'Occupied'::public.room_status
            ELSE 'Vacant'::public.room_status
        END
    WHERE id = v_room_id AND status != 'Maintenance'::public.room_status;

    -- If it's an update and the old room is different, update that one too
    IF (TG_OP = 'UPDATE' AND OLD.room_id IS DISTINCT FROM NEW.room_id) THEN
        SELECT count(*)
        INTO v_occupant_count
        FROM room_allocations
        WHERE room_id = OLD.room_id AND is_active = true;

        UPDATE rooms
        SET occupants = v_occupant_count,
            status = CASE
                WHEN v_occupant_count > 0 THEN 'Occupied'::public.room_status
                ELSE 'Vacant'::public.room_status
            END
        WHERE id = OLD.room_id AND status != 'Maintenance'::public.room_status;
    END IF;

    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$$;
-- Recreate the trigger for update_room_occupancy
CREATE TRIGGER after_allocation_change
AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
FOR EACH ROW EXECUTE FUNCTION public.update_room_occupancy();
