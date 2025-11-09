/*
# [Migration] Add Holiday Status and Harden All Functions
This migration introduces a 'Holiday' status for attendance, enhances the student attendance calendar function to provide more data for reports, and hardens all existing database functions by setting a fixed search_path to resolve security warnings.

## Query Description:
- **ALTER TYPE**: Adds a new 'Holiday' value to the `attendance_status` enum. This is a non-destructive operation.
- **DROP/CREATE FUNCTION**: All existing functions are dropped and recreated. This is done to:
  1. Update the `student_attendance_calendar` function to return more detailed data for reporting.
  2. Set a non-mutable `search_path` for all functions, which is a critical security best practice to prevent hijacking attacks.

## Metadata:
- Schema-Category: "Structural", "Safe"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: false (Dropping functions is reversible only if you have the old definitions)

## Structure Details:
- **Types Affected**: `public.attendance_status`
- **Functions Affected**:
  - `handle_new_user`
  - `get_or_create_session`
  - `bulk_mark_attendance`
  - `student_attendance_calendar` (Return type changed)
  - `universal_search`
  - `update_room_occupancy`
  - `get_unallocated_students`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None
- **Security Hardening**: This migration explicitly sets `search_path = public` for all custom functions, resolving the "Function Search Path Mutable" security advisory.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. Function recreation is a one-time, low-impact operation.
*/

-- 1. Add 'Holiday' to attendance_status enum if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = 'public.attendance_status'::regtype AND enumlabel = 'Holiday') THEN
        ALTER TYPE public.attendance_status ADD VALUE 'Holiday';
    END IF;
END$$;


-- 2. Recreate all functions with security hardening and enhancements

-- Drop old functions with specific signatures to avoid errors
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb[]);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.get_unallocated_students();

-- Recreate function: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (new.id, new.email, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role')
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

-- Recreate function: get_or_create_session
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
    -- Try to find an existing session
    SELECT id INTO session_id
    FROM public.attendance_sessions
    WHERE date = p_date
      AND type = p_type
      AND (course = p_course OR p_course IS NULL)
      AND (year = p_year OR p_year IS NULL);

    -- If not found, create a new one
    IF session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (date, type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$;

-- Recreate function: bulk_mark_attendance
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(
    p_session_id uuid,
    p_records jsonb[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rec jsonb;
BEGIN
    FOREACH rec IN ARRAY p_records
    LOOP
        INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
        VALUES (
            p_session_id,
            (rec->>'student_id')::uuid,
            (rec->>'status')::public.attendance_status,
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
$$;

-- Recreate and enhance function: student_attendance_calendar
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(
    p_student_id uuid,
    p_month integer,
    p_year integer
)
RETURNS TABLE(day date, status public.attendance_status, session_type public.attendance_session_type, note text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.date AS day,
        ar.status,
        s.type as session_type,
        ar.note
    FROM public.attendance_sessions s
    JOIN public.attendance_records ar ON s.id = ar.session_id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year
    ORDER BY s.date;
END;
$$;

-- Recreate function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_results jsonb;
BEGIN
    SELECT jsonb_build_object(
        'Students', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', s.id,
                    'label', s.full_name,
                    'path', '/students/' || s.id
                )
            )
            FROM public.students s
            WHERE s.full_name ILIKE '%' || p_search_term || '%'
        ),
        'Rooms', (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', r.id,
                    'label', 'Room ' || r.room_number,
                    'path', '/rooms/' || r.id
                )
            )
            FROM public.rooms r
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
        )
    ) INTO v_results;

    RETURN v_results;
END;
$$;

-- Recreate function: update_room_occupancy
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_room_id uuid;
    v_occupant_count integer;
BEGIN
    -- Determine which room_id to update
    IF (TG_OP = 'DELETE') THEN
        v_room_id := OLD.room_id;
    ELSE
        v_room_id := NEW.room_id;
    END IF;

    -- Recalculate the number of active occupants for the room
    SELECT count(*)
    INTO v_occupant_count
    FROM public.room_allocations
    WHERE room_id = v_room_id AND end_date IS NULL;

    -- Update the occupants count and status on the rooms table
    UPDATE public.rooms
    SET
        occupants = v_occupant_count,
        status = CASE
            WHEN status = 'Maintenance' THEN 'Maintenance'
            WHEN v_occupant_count > 0 THEN 'Occupied'
            ELSE 'Vacant'
        END
    WHERE id = v_room_id;

    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$$;

-- Recreate function: get_unallocated_students
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
    LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.end_date IS NULL
    WHERE ra.id IS NULL
    ORDER BY s.full_name;
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type, text, integer) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_mark_attendance(uuid, jsonb[]) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.student_attendance_calendar(uuid, integer, integer) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.update_room_occupancy() TO postgres, authenticated;
GRANT EXECUTE ON FUNCTION public.get_unallocated_students() TO postgres, authenticated;
