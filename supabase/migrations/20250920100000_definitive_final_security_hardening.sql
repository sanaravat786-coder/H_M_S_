/*
# [Definitive Final Security Hardening]
This migration provides a comprehensive and definitive fix for all database functions, ensuring they are secure and correctly defined. It resolves all outstanding "Function Search Path Mutable" security advisories by explicitly setting `search_path = public` and using `SECURITY DEFINER` where necessary. It also safely drops and recreates dependent objects like triggers to prevent dependency errors.

## Query Description: [This script will safely drop and recreate all custom database functions to apply final security hardening. It is designed to be the last step in stabilizing the database schema and resolving all security warnings. No data will be lost.]

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [false]

## Structure Details:
- Functions being recreated:
  - `is_admin()`
  - `get_or_create_session(date, public.attendance_session_type)`
  - `get_attendance_summary_for_student(uuid, integer, integer)`
  - `get_monthly_attendance_for_student(uuid, integer, integer)`
  - `get_room_details(uuid)`
  - `universal_search(text)`
  - `handle_new_user()`
- Triggers being recreated:
  - `on_auth_user_created` on `auth.users`
- Types being created (if not exist):
  - `public.attendance_session_type`
  - `public.attendance_statuses` (ensuring 'Holiday' is included)

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [No]
- Auth Requirements: [All functions are hardened against security vulnerabilities like search path hijacking.]

## Performance Impact:
- Indexes: [No change]
- Triggers: [Recreated]
- Estimated Impact: [Negligible performance impact. This change improves security and stability.]
*/

-- Step 1: Ensure custom types exist to prevent errors.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_session_type') THEN
        CREATE TYPE public.attendance_session_type AS ENUM ('morning', 'evening');
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_statuses') THEN
        CREATE TYPE public.attendance_statuses AS ENUM ('Present', 'Absent', 'Leave');
    END IF;

    -- Add 'Holiday' to the attendance_statuses enum if it doesn't already exist.
    -- This is done without dropping the type to preserve data.
    BEGIN
        ALTER TYPE public.attendance_statuses ADD VALUE IF NOT EXISTS 'Holiday';
    EXCEPTION
        WHEN duplicate_object THEN
            -- The value already exists, so we can ignore the error.
            NULL;
    END;
END;
$$;


-- Step 2: Drop the user creation trigger and function before recreating them.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Step 3: Drop all other custom functions.
DROP FUNCTION IF EXISTS public.is_admin();
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type);
DROP FUNCTION IF EXISTS public.get_attendance_summary_for_student(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_monthly_attendance_for_student(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.get_room_details(uuid);
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 4: Recreate all functions with security best practices.

-- Function: is_admin()
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
END;
$$;

-- Function: get_or_create_session(date, attendance_session_type)
CREATE OR REPLACE FUNCTION public.get_or_create_session(
  p_date date,
  p_session_type public.attendance_session_type
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  session_id uuid;
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only admins can perform this action';
  END IF;

  SELECT id INTO session_id
  FROM public.attendance_sessions
  WHERE date = p_date AND session_type = p_session_type;

  IF session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (date, session_type)
    VALUES (p_date, p_session_type)
    RETURNING id INTO session_id;
  END IF;

  RETURN session_id;
END;
$$;

-- Function: get_attendance_summary_for_student(uuid, integer, integer)
CREATE OR REPLACE FUNCTION public.get_attendance_summary_for_student(
  p_student_id uuid,
  p_month integer,
  p_year integer
)
RETURNS TABLE(status public.attendance_statuses, count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() AND auth.uid() <> p_student_id THEN
    RAISE EXCEPTION 'You are not authorized to view this attendance summary.';
  END IF;

  RETURN QUERY
  SELECT ar.status, COUNT(ar.id)
  FROM public.attendance_records ar
  JOIN public.attendance_sessions s ON ar.session_id = s.id
  WHERE ar.student_id = p_student_id
    AND EXTRACT(MONTH FROM s.date) = p_month
    AND EXTRACT(YEAR FROM s.date) = p_year
  GROUP BY ar.status;
END;
$$;

-- Function: get_monthly_attendance_for_student(uuid, integer, integer)
CREATE OR REPLACE FUNCTION public.get_monthly_attendance_for_student(
  p_student_id uuid,
  p_month integer,
  p_year integer
)
RETURNS TABLE(day date, status public.attendance_statuses)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() <> p_student_id AND NOT is_admin() THEN
    RAISE EXCEPTION 'You are not authorized to view this attendance data.';
  END IF;

  RETURN QUERY
  WITH daily_attendance AS (
    SELECT
      s.date,
      ar.status,
      ROW_NUMBER() OVER(PARTITION BY s.date ORDER BY
        CASE ar.status
          WHEN 'Absent' THEN 1
          WHEN 'Leave' THEN 2
          WHEN 'Holiday' THEN 3
          WHEN 'Present' THEN 4
          ELSE 5
        END, s.session_type DESC) as rn
    FROM public.attendance_records ar
    JOIN public.attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.date) = p_month
      AND EXTRACT(YEAR FROM s.date) = p_year
  )
  SELECT da.date AS day, da.status
  FROM daily_attendance da
  WHERE da.rn = 1;
END;
$$;

-- Function: get_room_details(uuid)
CREATE OR REPLACE FUNCTION public.get_room_details(p_room_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    room_details json;
BEGIN
    IF NOT is_admin() THEN
        RAISE EXCEPTION 'Only admins can perform this action';
    END IF;

    SELECT json_build_object(
        'room', r,
        'students', COALESCE(
            (SELECT json_agg(
                json_build_object(
                    'id', p.id,
                    'full_name', p.full_name,
                    'email', p.email
                )
            )
            FROM public.profiles p
            WHERE p.id IN (
                SELECT ra.student_id
                FROM public.room_allocations ra
                WHERE ra.room_id = r.id AND ra.end_date IS NULL
            )),
            '[]'::json
        )
    )
    INTO room_details
    FROM public.rooms r
    WHERE r.id = p_room_id;

    RETURN room_details;
END;
$$;

-- Function: universal_search(text)
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(
  id uuid,
  full_name text,
  email text,
  "type" text,
  details jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Only admins can perform this action';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.email,
    'Student' AS "type",
    jsonb_build_object('room_number', r.room_number)
  FROM public.profiles p
  LEFT JOIN public.room_allocations ra ON p.id = ra.student_id AND ra.end_date IS NULL
  LEFT JOIN public.rooms r ON ra.room_id = r.id
  WHERE p.role = 'student' AND (
    p.full_name ILIKE '%' || p_search_term || '%' OR
    p.email ILIKE '%' || p_search_term || '%'
  )
  UNION ALL
  SELECT
    r.id,
    r.room_number AS full_name,
    NULL AS email,
    'Room' AS "type",
    jsonb_build_object('capacity', r.capacity, 'block', r.block)
  FROM public.rooms r
  WHERE r.room_number ILIKE '%' || p_search_term || '%';
END;
$$;

-- Function: handle_new_user()
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT := COALESCE(new.raw_user_meta_data->>'role', 'student');
  v_full_name TEXT := COALESCE(new.raw_user_meta_data->>'full_name', '');
BEGIN
  IF v_role NOT IN ('admin', 'staff', 'student') THEN
    v_role := 'student';
  END IF;

  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (new.id, new.email, v_full_name, v_role)
  ON CONFLICT (id) DO NOTHING;

  RETURN new;
END;
$$;

-- Step 5: Recreate the trigger for handle_new_user.
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- Step 6: Grant execute permissions on all functions
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_summary_for_student(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_monthly_attendance_for_student(uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_room_details(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO postgres, authenticated, anon;
