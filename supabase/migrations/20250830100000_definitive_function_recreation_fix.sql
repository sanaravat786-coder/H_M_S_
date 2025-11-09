/*
# [Fix] Definitive Function and Trigger Recreation
This migration script resolves a dependency error by safely dropping and recreating all custom functions and their associated triggers. All functions are recreated with security best practices, including setting a `search_path` to resolve security advisories.

## Query Description:
This operation will temporarily drop and then immediately recreate all custom functions and triggers in the public schema. This is a safe and robust way to fix dependency errors during migrations. There is a minimal risk of race conditions, but it is highly unlikely in a non-production environment. No data will be lost.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Drops and recreates all custom functions in the `public` schema using `CASCADE` to handle dependencies.
- Drops and recreates the `on_auth_user_created` trigger on `auth.users`.
- Drops and recreates the `trg_update_room_occupancy` trigger on `room_allocations`.

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges required to run migration.
- This script hardens all functions by setting a secure `search_path`, resolving the "Function Search Path Mutable" security advisory.

## Performance Impact:
- Indexes: None
- Triggers: Recreated
- Estimated Impact: Negligible.
*/

-- Step 1: Drop all existing custom functions and their dependent triggers using CASCADE.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer) CASCADE;
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.universal_search(text) CASCADE;
DROP FUNCTION IF EXISTS public.get_unallocated_students() CASCADE;
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.update_room_occupancy() CASCADE;
DROP FUNCTION IF EXISTS public.update_room_occupancy_by_id(uuid) CASCADE;

-- Step 2: Recreate the handle_new_user function.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, "role", mobile_number)
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

-- Step 3: Recreate the trigger on auth.users for new user profiles.
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Step 4: Recreate all other custom functions with security hardening.

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
    SELECT id INTO session_id
    FROM attendance_sessions
    WHERE date = p_date
      AND type = p_type
      AND (course IS NULL OR course = p_course)
      AND (year IS NULL OR year = p_year);

    IF session_id IS NULL THEN
        INSERT INTO attendance_sessions (date, type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;


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


CREATE OR REPLACE FUNCTION public.student_attendance_calendar(
    p_student_id uuid,
    p_month integer,
    p_year integer
)
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
    FROM attendance_sessions s
    JOIN attendance_records ar ON s.id = ar.session_id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY s.date;
END;
$$;


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
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', s.id,
                'label', s.full_name,
                'path', '/students/' || s.id
            )), '[]'::jsonb)
            FROM students s
            WHERE s.full_name ILIKE '%' || p_search_term || '%'
        ),
        'rooms', (
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'id', r.id,
                'label', 'Room ' || r.room_number,
                'path', '/rooms/' || r.id
            )), '[]'::jsonb)
            FROM rooms r
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
        )
    ) INTO results;

    RETURN results;
END;
$$;


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


CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO room_allocations (student_id, room_id, start_date)
    VALUES (p_student_id, p_room_id, NOW());
END;
$$;


CREATE OR REPLACE FUNCTION public.update_room_occupancy_by_id(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    occupant_count integer;
    room_status text;
BEGIN
    SELECT COUNT(*)
    INTO occupant_count
    FROM room_allocations
    WHERE room_id = p_room_id AND is_active = true;

    UPDATE rooms
    SET occupants = occupant_count
    WHERE id = p_room_id;

    SELECT status INTO room_status FROM rooms WHERE id = p_room_id;
    
    IF room_status != 'Maintenance' THEN
        UPDATE rooms
        SET status = CASE WHEN occupant_count > 0 THEN 'Occupied' ELSE 'Vacant' END
        WHERE id = p_room_id;
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_id uuid;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        v_room_id := NEW.room_id;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_room_id := COALESCE(NEW.room_id, OLD.room_id);
    ELSIF (TG_OP = 'DELETE') THEN
        v_room_id := OLD.room_id;
    END IF;

    IF v_room_id IS NOT NULL THEN
        PERFORM public.update_room_occupancy_by_id(v_room_id);
    END IF;

    IF (TG_OP = 'UPDATE' AND NEW.room_id IS DISTINCT FROM OLD.room_id AND OLD.room_id IS NOT NULL) THEN
        PERFORM public.update_room_occupancy_by_id(OLD.room_id);
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;


-- Step 5: Recreate the trigger on room_allocations.
CREATE TRIGGER trg_update_room_occupancy
AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
FOR EACH ROW EXECUTE FUNCTION public.update_room_occupancy();
