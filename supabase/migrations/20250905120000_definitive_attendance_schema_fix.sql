/*
# [Definitive Attendance Schema Fix]
This migration script addresses a critical schema mismatch that caused previous migrations to fail. The error "column s.date does not exist" indicates that the `public.attendance_sessions` table is missing the required `date` column.

This script will perform the following actions safely:
1. Drop all database functions related to attendance that depend on the incorrect schema.
2. Add the missing `date` column to the `public.attendance_sessions` table.
3. Recreate all the necessary attendance-related functions with the correct schema and security settings (SECURITY DEFINER and `search_path`).

## Query Description: This is a structural change to fix a broken database schema. It is designed to be non-destructive to your existing attendance data. It drops and recreates functions, which is a safe operation. It adds a column, which is also safe. No data will be lost.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: false (but the previous state was broken)

## Structure Details:
- Tables affected: `public.attendance_sessions` (adds a `date` column).
- Functions affected: Drops and recreates `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`.

## Security Implications:
- RLS Status: Unchanged.
- Policy Changes: No.
- Auth Requirements: None.

## Performance Impact:
- Indexes: Adds an index on the new `date` column in `attendance_sessions` to improve query performance.
- Triggers: None.
- Estimated Impact: Positive, as it fixes broken functionality and adds a necessary index.
*/

-- Step 1: Drop functions that depend on the attendance tables to allow schema changes.
-- We drop them defensively with the correct signatures.
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);

-- Step 2: Add the missing 'date' column to the 'attendance_sessions' table if it doesn't exist.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'attendance_sessions' AND column_name = 'date'
  ) THEN
    ALTER TABLE public.attendance_sessions ADD COLUMN date DATE;
  END IF;
END;
$$;

-- Step 3: Ensure the attendance session type exists.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'attendance_session_type') THEN
    CREATE TYPE public.attendance_session_type AS ENUM ('NightRoll', 'Morning', 'Evening');
  END IF;
END;
$$;

-- Step 4: Recreate the functions with the corrected schema and security hardening.

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
  WHERE date = p_date
    AND type = p_type
    AND (course IS NULL OR course = p_course)
    AND (year IS NULL OR year = p_year);

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
            (record->>'late_minutes')::integer
        )
        ON CONFLICT (session_id, student_id) DO UPDATE
        SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes,
            updated_at = now();
    END LOOP;
END;
$$;

-- Function for student's attendance calendar view
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH month_days AS (
    SELECT generate_series(
      make_date(p_year, p_month, 1),
      (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date,
      interval '1 day'
    )::date AS day
  )
  SELECT
    d.day,
    COALESCE(ar.status, 'Unmarked') AS status
  FROM month_days d
  LEFT JOIN (
    SELECT s.date, ar_inner.status::text
    FROM public.attendance_records ar_inner
    JOIN public.attendance_sessions s ON ar_inner.session_id = s.id
    WHERE ar_inner.student_id = p_student_id
      AND s.date >= make_date(p_year, p_month, 1)
      AND s.date < (make_date(p_year, p_month, 1) + interval '1 month')
  ) ar ON ar.date = d.day;
END;
$$;

-- Step 5: Grant permissions on the recreated functions
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_mark_attendance(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_attendance_calendar(uuid, integer, integer) TO authenticated;

-- Step 6: Add an index to the new column for performance
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_date ON public.attendance_sessions(date);
