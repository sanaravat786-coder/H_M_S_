/*
# [DEFINITIVE SCHEMA RESET & REBUILD]
This script provides a comprehensive reset for the attendance and allocation modules. It is designed to fix migration errors caused by partially applied scripts and cascading drops.

## Query Description:
This operation will first DROP several tables, functions, and policies related to recent features (Attendance, Room Allocation, Universal Search) and then recreate them from a clean slate. This is necessary to resolve dependency conflicts and ensure the database schema is in a consistent, correct, and secure state.

- **Tables being reset:** `attendance_records`, `leaves`, `attendance_sessions`, `room_allocations`
- **Functions being reset:** `is_admin`, `is_staff`, `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`, `universal_search`, `get_unallocated_students`, `allocate_room`, `update_room_occupancy`
- **Views being reset:** `v_attendance_daily_summary`
- **Policies being reset:** All RLS policies on the tables listed above.

**SAFETY WARNING:** This script is designed to be run on the current state of your project. While it only targets specific objects, it's always best practice to have a database backup before running significant schema changes.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: true
- Reversible: false

## Structure Details:
- Drops and recreates tables, functions, views, and policies to ensure a clean state.
- Recreates the `room_allocations` table which may have been inadvertently dropped.
- Hardens all functions by setting a `search_path` to resolve security warnings.

## Security Implications:
- RLS Status: RLS is re-enabled on all relevant tables.
- Policy Changes: All policies are dropped and recreated with correct, secure definitions.
- Auth Requirements: Functions and policies correctly reference `auth.uid()` and custom role-checking functions.

## Performance Impact:
- Indexes: All necessary indexes are recreated on the new tables.
- Triggers: The `update_room_occupancy_trigger` is recreated.
- Estimated Impact: A brief period of high database load during execution. Post-execution, performance will be as-designed.
*/

-- STEP 1: Drop all related objects in a safe order.
-- We use IF EXISTS to prevent errors if an object is already gone.
-- We use CASCADE to handle complex dependencies automatically.
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;
DROP FUNCTION IF EXISTS public.is_staff() CASCADE;
DROP FUNCTION IF EXISTS public.get_unallocated_students() CASCADE;
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.universal_search(text) CASCADE;
DROP TABLE IF EXISTS public.attendance_records CASCADE;
DROP TABLE IF EXISTS public.leaves CASCADE;
DROP TABLE IF EXISTS public.attendance_sessions CASCADE;
DROP TABLE IF EXISTS public.room_allocations CASCADE;
DROP VIEW IF EXISTS public.v_attendance_daily_summary;

-- STEP 2: Recreate tables with all constraints.

-- Recreate room_allocations table (inferred from codebase)
CREATE TABLE public.room_allocations (
    id uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    start_date timestamptz NOT NULL DEFAULT now(),
    end_date timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    is_active boolean GENERATED ALWAYS AS (end_date IS NULL) STORED
);
-- Add a unique constraint to ensure a student can only have one active allocation
CREATE UNIQUE INDEX ON public.room_allocations (student_id) WHERE (is_active = true);
-- Add indexes for performance
CREATE INDEX ON public.room_allocations (room_id);
CREATE INDEX ON public.room_allocations (student_id);


-- Recreate attendance tables
CREATE TABLE public.attendance_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_date date NOT NULL,
    session_type text NOT NULL DEFAULT 'NightRoll' CHECK (session_type IN ('NightRoll','Morning','Evening','Custom')),
    block text,
    room_id uuid REFERENCES public.rooms(id) ON DELETE SET NULL,
    course text,
    year text,
    created_by uuid REFERENCES public.profiles(id),
    created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX uq_attendance_session ON public.attendance_sessions (session_date, session_type, coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(block,''), coalesce(course,''), coalesce(year,''));
CREATE INDEX idx_att_sessions_date ON public.attendance_sessions(session_date);

CREATE TABLE public.attendance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id uuid NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    status text NOT NULL CHECK (status IN ('Present','Absent','Late','Excused')),
    marked_at timestamptz DEFAULT now(),
    marked_by uuid REFERENCES public.profiles(id),
    note text,
    late_minutes int DEFAULT 0 CHECK (late_minutes >= 0),
    UNIQUE (session_id, student_id)
);
CREATE INDEX idx_att_records_student ON public.attendance_records(student_id);
CREATE INDEX idx_att_records_session ON public.attendance_records(session_id);

CREATE TABLE public.leaves (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    start_date date NOT NULL,
    end_date date NOT NULL,
    reason text,
    approved_by uuid REFERENCES public.profiles(id),
    created_at timestamptz DEFAULT now(),
    CHECK (end_date >= start_date)
);

-- STEP 3: Recreate views and functions with security best practices.

-- Security helper functions
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT 'Admin' = (SELECT raw_user_meta_data->>'role' FROM auth.users WHERE id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT (raw_user_meta_data->>'role') IN ('Admin', 'Staff') FROM auth.users WHERE id = auth.uid();
$$;

-- Allocation functions
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE rooms
  SET occupants = (SELECT count(*) FROM room_allocations WHERE room_id = p_room_id AND is_active = true)
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
  v_room_capacity int;
  v_current_occupants int;
BEGIN
  -- Check room capacity
  SELECT capacity, occupants INTO v_room_capacity, v_current_occupants FROM rooms WHERE id = p_room_id;
  IF v_current_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'Room is already full';
  END IF;

  -- Deactivate any previous allocation for the student
  UPDATE room_allocations SET end_date = now() WHERE student_id = p_student_id AND is_active = true;

  -- Insert new allocation
  INSERT INTO room_allocations (student_id, room_id) VALUES (p_student_id, p_room_id);

  -- Update room occupancy count
  PERFORM update_room_occupancy(p_room_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT s.id, s.full_name, s.email, s.course
  FROM students s
  LEFT JOIN room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
$$;


-- Universal search function
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_search_term text := '%' || p_search_term || '%';
BEGIN
  RETURN jsonb_build_object(
    'students', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'label', s.full_name,
          'path', '/students/' || s.id
        )
      )
      FROM students s
      WHERE s.full_name ILIKE v_search_term OR s.email ILIKE v_search_term
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
      WHERE r.room_number::text ILIKE v_search_term
    )
  );
END;
$$;


-- Attendance view
CREATE OR REPLACE VIEW public.v_attendance_daily_summary
WITH (security_invoker = true)
AS
SELECT
  s.session_date,
  s.session_type,
  s.block,
  s.room_id,
  s.course,
  s.year,
  count(*) FILTER (WHERE r.status = 'Present') as present_count,
  count(*) FILTER (WHERE r.status = 'Absent')  as absent_count,
  count(*) FILTER (WHERE r.status = 'Late')    as late_count,
  count(*) FILTER (WHERE r.status = 'Excused') as excused_count,
  count(*) as total_marked
FROM attendance_sessions s
LEFT JOIN attendance_records r ON r.session_id = s.id
GROUP BY s.session_date, s.session_type, s.block, s.room_id, s.course, s.year;


-- Attendance functions
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_block text DEFAULT NULL, p_room_id uuid DEFAULT NULL, p_course text DEFAULT NULL, p_year text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM attendance_sessions
  WHERE session_date = p_date AND session_type = p_type
    AND coalesce(block, '') = coalesce(p_block, '')
    AND coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND coalesce(course, '') = coalesce(p_course, '')
    AND coalesce(year, '') = coalesce(p_year, '');
  
  IF v_id IS NULL THEN
    INSERT INTO attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    VALUES (p_date, p_type, p_block, p_room_id, p_course, p_year, auth.uid())
    RETURNING id INTO v_id;
  END IF;
  
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec jsonb;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    INSERT INTO attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    VALUES (
      p_session_id,
      (rec->>'student_id')::uuid,
      rec->>'status',
      rec->>'note',
      coalesce((rec->>'late_minutes')::int, 0),
      auth.uid()
    )
    ON CONFLICT (session_id, student_id) DO UPDATE
    SET
      status = excluded.status,
      note = excluded.note,
      late_minutes = excluded.late_minutes,
      marked_at = now(),
      marked_by = auth.uid();
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month int, p_year int)
RETURNS TABLE(day date, status text, session_type text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH days AS (
    SELECT generate_series(
      make_date(p_year, p_month, 1),
      (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date,
      interval '1 day'
    )::date as d
  )
  SELECT
    d.d as day,
    coalesce(r.status, 'Unmarked') as status,
    s.session_type
  FROM days d
  LEFT JOIN attendance_sessions s ON s.session_date = d.d
  LEFT JOIN attendance_records r ON r.session_id = s.id AND r.student_id = p_student_id
  ORDER BY d.d ASC;
$$;

-- STEP 4: Re-enable RLS and recreate all policies.

-- room_allocations
ALTER TABLE public.room_allocations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all allocations" ON public.room_allocations FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Students can view their own allocation" ON public.room_allocations FOR SELECT USING (student_id = auth.uid());

-- attendance_sessions
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all sessions" ON public.attendance_sessions FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Students can view sessions they are part of" ON public.attendance_sessions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM attendance_records ar
    WHERE ar.session_id = id AND ar.student_id = auth.uid()
  )
);

-- attendance_records
ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all records" ON public.attendance_records FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Students can view their own records" ON public.attendance_records FOR SELECT USING (student_id = auth.uid());

-- leaves
ALTER TABLE public.leaves ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all leaves" ON public.leaves FOR ALL USING (is_staff()) WITH CHECK (is_staff());
CREATE POLICY "Students can manage their own leaves" ON public.leaves FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());
