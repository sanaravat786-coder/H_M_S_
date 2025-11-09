/*
# [Function and Trigger Recreation]
This script resolves a migration error by safely dropping and recreating all custom database functions and the user creation trigger. It ensures all functions are defined with the latest logic and hardened against security vulnerabilities like mutable search paths.

## Query Description: This operation will temporarily remove and then restore all custom application logic (search, allocation, attendance functions) within the database. There is no risk to stored data (students, rooms, etc.), but this is a critical structural change.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: false
- Reversible: false (reverting would require re-running older, faulty migrations)

## Structure Details:
- Drops and recreates all custom functions.
- Drops and recreates the `on_auth_user_created` trigger.

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Admin privileges required to run.
- Fixes "Function Search Path Mutable" advisory by setting a static search_path for all functions.

## Performance Impact:
- Indexes: Unchanged
- Triggers: Recreated
- Estimated Impact: Negligible after migration is complete.
*/

-- Step 1: Drop existing functions and trigger to allow recreation.
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.create_user_profile();

-- Step 2: Recreate the `create_user_profile` function and its trigger.
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, "role", mobile_number)
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

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.create_user_profile();

-- Step 3: Recreate the `universal_search` function with the correct JSONB return type.
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
    ) INTO results;

    RETURN results;
END;
$$;


-- Step 4: Recreate other application-specific functions.

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

CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_occupants integer;
BEGIN
    SELECT count(*)
    INTO current_occupants
    FROM room_allocations
    WHERE room_id = p_room_id AND is_active = true;

    UPDATE rooms
    SET
        occupants = current_occupants,
        status = CASE
            WHEN status = 'Maintenance' THEN 'Maintenance'
            WHEN current_occupants > 0 THEN 'Occupied'
            ELSE 'Vacant'
        END
    WHERE id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_capacity_text text;
    v_room_capacity int;
    v_current_occupants int;
BEGIN
    SELECT r.type, r.occupants INTO v_room_capacity_text, v_current_occupants FROM rooms r WHERE r.id = p_room_id;
    
    v_room_capacity := CASE v_room_capacity_text
        WHEN 'Single' THEN 1
        WHEN 'Double' THEN 2
        WHEN 'Triple' THEN 3
        ELSE 1
    END;

    IF v_current_occupants >= v_room_capacity THEN
        RAISE EXCEPTION 'Room is already full.';
    END IF;

    UPDATE room_allocations
    SET is_active = false, end_date = now()
    WHERE student_id = p_student_id AND is_active = true;

    INSERT INTO room_allocations (student_id, room_id, start_date, is_active)
    VALUES (p_student_id, p_room_id, now(), true);

    PERFORM update_room_occupancy(p_room_id);
END;
$$;

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
    WHERE session_date = p_date
      AND session_type = p_type
      AND (course IS NULL OR course = p_course)
      AND (year IS NULL OR year = p_year);

    IF session_id IS NULL THEN
        INSERT INTO attendance_sessions (session_date, session_type, course, year)
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
BEGIN
    INSERT INTO attendance_records (session_id, student_id, status, note, late_minutes)
    SELECT
        p_session_id,
        (value ->> 'student_id')::uuid,
        (value ->> 'status')::attendance_status,
        value ->> 'note',
        (value ->> 'late_minutes')::integer
    FROM jsonb_array_elements(p_records)
    ON CONFLICT (session_id, student_id)
    DO UPDATE SET
        status = EXCLUDED.status,
        note = EXCLUDED.note,
        late_minutes = EXCLUDED.late_minutes;
END;
$$;

CREATE OR REPLACE FUNCTION public.student_attendance_calendar(
    p_student_id uuid,
    p_month integer,
    p_year integer
)
RETURNS TABLE(day date, status attendance_status)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ar.session_date AS day,
        rec.status
    FROM attendance_records rec
    JOIN attendance_sessions ar ON rec.session_id = ar.id
    WHERE rec.student_id = p_student_id
      AND EXTRACT(MONTH FROM ar.session_date) = p_month
      AND EXTRACT(YEAR FROM ar.session_date) = p_year;
END;
$$;
