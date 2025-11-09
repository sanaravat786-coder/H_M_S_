/*
          # [Definitive Final Security Fix & Schema Hardening]
          This migration provides a comprehensive fix for all remaining security advisories and schema inconsistencies. It safely drops and recreates all custom database functions to enforce a secure 'search_path', preventing potential SQL injection vulnerabilities. It also ensures the 'attendance_status' type includes 'Holiday' and that the 'attendance_sessions' table has the correct structure.

          ## Query Description: "This operation will securely redefine all application-specific database functions and triggers. It is a safe, idempotent script designed to be the final step in stabilizing the database schema. No data loss will occur."
          
          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Functions Affected: get_monthly_attendance_for_student, get_or_create_session, get_unallocated_students, handle_new_user, universal_search, update_room_occupancy, allocate_room
          - Triggers Affected: on_auth_user_created
          - Types Affected: attendance_status
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [None]
          - Triggers: [Recreated]
          - Estimated Impact: [Negligible. Recreates functions and triggers with secure defaults.]
          */

-- Step 1: Ensure 'Holiday' value exists in the attendance_status enum.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_enum WHERE enumtypid = 'public.attendance_status'::regtype AND enumlabel = 'Holiday') THEN
        ALTER TYPE public.attendance_status ADD VALUE 'Holiday';
    END IF;
END$$;

-- Step 2: Ensure 'date' column exists in attendance_sessions table.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'attendance_sessions' AND column_name = 'date') THEN
        ALTER TABLE public.attendance_sessions ADD COLUMN "date" date;
    END IF;
END$$;

-- Step 3: Drop all existing custom functions and triggers to prepare for recreation.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_monthly_attendance_for_student(uuid,integer,integer);
DROP FUNCTION IF EXISTS public.get_or_create_session(date,public.attendance_session_type);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.allocate_room(uuid,uuid);

-- Step 4: Recreate the handle_new_user function securely.
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
  );
  RETURN NEW;
END;
$$;

-- Step 5: Recreate the on_auth_user_created trigger.
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 6: Recreate all other application functions securely.

CREATE OR REPLACE FUNCTION public.get_monthly_attendance_for_student(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status public.attendance_status)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT s.date AS day, ar.status
    FROM public.attendance_sessions s
    JOIN public.attendance_records ar ON s.id = ar.session_id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_session_type public.attendance_session_type)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    session_uuid uuid;
BEGIN
    SELECT id INTO session_uuid
    FROM public.attendance_sessions
    WHERE date = p_date AND session_type = p_session_type;

    IF session_uuid IS NULL THEN
        INSERT INTO public.attendance_sessions (date, session_type)
        VALUES (p_date, p_session_type)
        RETURNING id INTO session_uuid;
    END IF;

    RETURN session_uuid;
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
    SELECT p.id, p.full_name, p.email, s.course
    FROM public.profiles p
    JOIN public.students s ON p.id = s.id
    WHERE p.role = 'student' AND NOT EXISTS (
        SELECT 1
        FROM public.room_allocations ra
        WHERE ra.student_id = p.id AND ra.is_active = TRUE
    )
    ORDER BY p.full_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    students_json json;
    rooms_json json;
BEGIN
    SELECT json_agg(json_build_object(
        'id', s.id,
        'label', s.full_name,
        'path', '/students/' || s.id
    ))
    INTO students_json
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%';

    SELECT json_agg(json_build_object(
        'id', r.id,
        'label', 'Room ' || r.room_number,
        'path', '/rooms/' || r.id
    ))
    INTO rooms_json
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';

    RETURN json_build_object(
        'students', COALESCE(students_json, '[]'::json),
        'rooms', COALESCE(rooms_json, '[]'::json)
    );
END;
$$;

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
    WHERE room_id = p_room_id AND is_active = TRUE;

    UPDATE public.rooms
    SET occupants = occupant_count
    WHERE id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.room_allocations (student_id, room_id, start_date)
    VALUES (p_student_id, p_room_id, now());
END;
$$;

-- Step 7: Grant usage to authenticated users.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
