/*
-- =================================================================
-- DEFINITIVE MIGRATION FIX
-- This script addresses multiple migration failures by resetting
-- and recreating all functions and policies related to the
-- attendance module and universal search. It also ensures the
-- 'room_allocations' table exists, which was the cause of the
-- latest error.
-- =================================================================
*/

/*
# [Recreate Room Allocations Table]
This operation creates the 'room_allocations' table, which appears to have been dropped during a previous migration attempt. This table is critical for managing which student is in which room.

## Query Description: "This operation creates a new table 'room_allocations'. If this table somehow exists with data, this script will not harm it, but it is designed to fix a state where the table is missing. No data loss is expected as the table is presumed to be non-existent."

## Metadata:
- Schema-Category: ["Structural"]
- Impact-Level: ["Medium"]
- Requires-Backup: [false]
- Reversible: [false]

## Structure Details:
- Table: room_allocations
- Columns: id, room_id, student_id, start_date, end_date, created_at, is_active

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [Yes]
- Auth Requirements: [Admin/Staff for write, Student for own-read]

## Performance Impact:
- Indexes: [Added]
- Triggers: [None]
- Estimated Impact: [Low. Adds a new table and indexes.]
*/
CREATE TABLE IF NOT EXISTS public.room_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id uuid NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    start_date timestamptz NOT NULL DEFAULT now(),
    end_date timestamptz,
    created_at timestamptz DEFAULT now(),
    is_active boolean GENERATED ALWAYS AS (end_date IS NULL) STORED
);
CREATE UNIQUE INDEX IF NOT EXISTS room_allocations_unique_active_student ON public.room_allocations (student_id) WHERE (is_active = true);
CREATE INDEX IF NOT EXISTS idx_room_allocations_room_id ON public.room_allocations(room_id);


/*
# [Recreate All Functions and Policies]
This operation drops all custom functions and their dependent RLS policies, then recreates them with proper security hardening (SECURITY DEFINER, search_path). This is to fix dependency and syntax errors from previous migrations.

## Query Description: "This operation will temporarily drop functions and security policies and then immediately recreate them. There is a brief moment where RLS is not enforced on the affected tables during the script's execution. It is highly recommended to run this during a low-traffic period. No data will be modified."

## Metadata:
- Schema-Category: ["Dangerous"]
- Impact-Level: ["High"]
- Requires-Backup: [false]
- Reversible: [false]

## Structure Details:
- Functions: is_admin, is_staff, get_unallocated_students, update_room_occupancy, allocate_room, universal_search, get_or_create_session, bulk_mark_attendance, student_attendance_calendar
- Policies: All RLS policies on attendance tables, leaves, and room_allocations.

## Security Implications:
- RLS Status: [Re-enabled]
- Policy Changes: [Yes]
- Auth Requirements: [Full recreation of auth-based policies]

## Performance Impact:
- Indexes: [None]
- Triggers: [None]
- Estimated Impact: [Low. Recreates functions and policies.]
*/

-- Step 1: Clean up all potentially broken functions and their dependent policies.
DROP FUNCTION IF EXISTS public.is_admin() CASCADE;
DROP FUNCTION IF EXISTS public.is_staff() CASCADE;
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, uuid, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb) CASCADE;
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, int, int) CASCADE;
DROP FUNCTION IF EXISTS public.universal_search(text) CASCADE;
DROP FUNCTION IF EXISTS public.get_unallocated_students() CASCADE;
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid) CASCADE;


-- Step 2: Recreate all functions with security best practices.

-- Role checking functions
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT 'Admin' = (auth.jwt() -> 'user_metadata' ->> 'role')), false);
$$;

CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT (auth.jwt() -> 'user_metadata' ->> 'role') IN ('Admin', 'Staff')), false);
$$;

-- Student/Allocation related functions
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text) LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, s.full_name, s.email, s.course
  FROM students s
  LEFT JOIN room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
$$;

CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE rooms
  SET occupants = (SELECT COUNT(*) FROM room_allocations WHERE room_id = p_room_id AND is_active = true)
  WHERE id = p_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_room_capacity int;
  v_current_occupants int;
  v_room_type text;
BEGIN
  IF EXISTS (SELECT 1 FROM room_allocations WHERE student_id = p_student_id AND is_active = true) THEN
    RAISE EXCEPTION 'Student is already allocated to a room.';
  END IF;

  SELECT type, occupants INTO v_room_type, v_current_occupants FROM rooms WHERE id = p_room_id;
  
  v_room_capacity := CASE 
    WHEN v_room_type = 'Single' THEN 1
    WHEN v_room_type = 'Double' THEN 2
    WHEN v_room_type = 'Triple' THEN 3
    ELSE 0
  END;

  IF v_current_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'This room is already full.';
  END IF;

  INSERT INTO room_allocations (student_id, room_id) VALUES (p_student_id, p_room_id);
  PERFORM update_room_occupancy(p_room_id);
END;
$$;

-- Universal Search function
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_search_term text := '%' || p_search_term || '%';
BEGIN
  RETURN json_build_object(
    'students', (
      SELECT json_agg(json_build_object('id', s.id, 'label', s.full_name || ' (' || s.course || ')', 'path', '/students/' || s.id))
      FROM students s WHERE s.full_name ILIKE v_search_term OR s.email ILIKE v_search_term LIMIT 5
    ),
    'rooms', (
      SELECT json_agg(json_build_object('id', r.id, 'label', 'Room ' || r.room_number || ' (' || r.type || ')', 'path', '/rooms/' || r.id))
      FROM rooms r WHERE r.room_number ILIKE v_search_term LIMIT 5
    )
  );
END;
$$;

-- Attendance functions
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_block text DEFAULT NULL, p_room_id uuid DEFAULT NULL, p_course text DEFAULT NULL, p_year text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM attendance_sessions
   WHERE session_date = p_date AND session_type = p_type
     AND coalesce(block,'') = coalesce(p_block,'')
     AND coalesce(room_id,'00000000-0000-0000-0000-000000000000'::uuid) = coalesce(p_room_id,'00000000-0000-0000-0000-000000000000'::uuid)
     AND coalesce(course,'') = coalesce(p_course,'')
     AND coalesce(year,'') = coalesce(p_year,'');
  IF v_id IS NULL THEN
    INSERT INTO attendance_sessions(session_date, session_type, block, room_id, course, year, created_by)
    VALUES (p_date, p_type, p_block, p_room_id, p_course, p_year, auth.uid())
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rec jsonb;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    INSERT INTO attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    VALUES (p_session_id, (rec->>'student_id')::uuid, rec->>'status', rec->>'note', coalesce((rec->>'late_minutes')::int, 0), auth.uid())
    ON CONFLICT (session_id, student_id) DO UPDATE
      SET status = excluded.status, note = excluded.note, late_minutes = excluded.late_minutes, marked_at = now(), marked_by = auth.uid();
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month int, p_year int)
RETURNS TABLE(day date, status text, session_type text) LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH days AS (SELECT generate_series(make_date(p_year, p_month, 1), (make_date(p_year, p_month, 1) + interval '1 month - 1 day')::date, interval '1 day')::date AS d)
  SELECT d.d AS day, coalesce(r.status, 'Unmarked') AS status, s.session_type
  FROM days d
  LEFT JOIN attendance_sessions s ON s.session_date = d.d
  LEFT JOIN attendance_records r ON r.session_id = s.id AND r.student_id = p_student_id
  ORDER BY d.d ASC;
$$;


-- Step 3: Re-enable RLS and recreate all policies.
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all sessions" ON public.attendance_sessions FOR ALL USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Students can view sessions they are part of" ON public.attendance_sessions FOR SELECT USING (EXISTS (SELECT 1 FROM attendance_records ar WHERE ar.session_id = id AND ar.student_id = auth.uid()));

ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all records" ON public.attendance_records FOR ALL USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Students can view their own records" ON public.attendance_records FOR SELECT USING (student_id = auth.uid());

ALTER TABLE public.leaves ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all leaves" ON public.leaves FOR ALL USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Students can manage their own leaves" ON public.leaves FOR ALL USING (student_id = auth.uid()) WITH CHECK (student_id = auth.uid());

ALTER TABLE public.room_allocations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can manage all allocations" ON public.room_allocations FOR ALL USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "Students can view their own allocation" ON public.room_allocations FOR SELECT USING (student_id = auth.uid());
