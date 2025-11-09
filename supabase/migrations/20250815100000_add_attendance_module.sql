/*
          # [Feature] Implement Attendance Module
          This migration sets up the complete database schema for the new Attendance Management feature. It includes tables for sessions, records, and leaves, along with helper functions and row-level security policies.

          ## Query Description: This script is foundational and adds new, isolated objects to the database. It does not modify or delete existing data.
          - Creates `attendance_sessions`, `attendance_records`, and `leaves` tables.
          - Creates a summary view `v_attendance_daily_summary`.
          - Adds high-performance indexes.
          - Implements three PL/pgSQL functions to handle business logic securely (`get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`).
          - Enables and configures Row-Level Security (RLS) for all new tables to ensure data privacy between roles.
          
          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Tables Added: `attendance_sessions`, `attendance_records`, `leaves`
          - Views Added: `v_attendance_daily_summary`
          - Functions Added: `get_or_create_session`, `bulk_mark_attendance`, `student_attendance_calendar`, `get_my_role`
          - Indexes Added: `idx_att_sessions_date`, `idx_att_records_student`, `idx_att_records_session`
          
          ## Security Implications:
          - RLS Status: Enabled on all new tables.
          - Policy Changes: Yes, new policies are created for the new tables.
          - Auth Requirements: Policies rely on the user's role, retrieved via a new `get_my_role()` helper function.
          
          ## Performance Impact:
          - Indexes: New indexes are added to ensure fast lookups on dates, student IDs, and session IDs.
          - Triggers: None.
          - Estimated Impact: Low. The new objects are isolated and indexed for performance.
          */

-- ========= ATTENDANCE TABLES =========
CREATE TABLE IF NOT EXISTS attendance_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_date date NOT NULL,
  session_type text NOT NULL DEFAULT 'NightRoll' CHECK (session_type IN ('NightRoll','Morning','Evening','Custom')),
  block text,
  room_id uuid REFERENCES rooms(id) ON DELETE SET NULL,
  course text,
  year text,
  created_by uuid REFERENCES profiles(id),
  created_at timestamptz DEFAULT now(),
  UNIQUE (session_date, session_type, coalesce(room_id, '00000000-0000-0000-0000-000000000000'::uuid), coalesce(block,''), coalesce(course,''), coalesce(year,''))
);
COMMENT ON TABLE attendance_sessions IS 'Defines a specific attendance-taking event for a given date, type, and scope.';

CREATE TABLE IF NOT EXISTS attendance_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
  student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  status text NOT NULL CHECK (status IN ('Present','Absent','Late','Excused')),
  marked_at timestamptz DEFAULT now(),
  marked_by uuid REFERENCES profiles(id),
  note text,
  late_minutes int DEFAULT 0 CHECK (late_minutes >= 0),
  UNIQUE (session_id, student_id)
);
COMMENT ON TABLE attendance_records IS 'Stores the attendance status for a student in a specific session.';

CREATE TABLE IF NOT EXISTS leaves (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  start_date date NOT NULL,
  end_date date NOT NULL,
  reason text,
  approved_by uuid REFERENCES profiles(id),
  created_at timestamptz DEFAULT now(),
  CHECK (end_date >= start_date)
);
COMMENT ON TABLE leaves IS 'Optional table for tracking approved student leaves.';

-- ========= INDEXES =========
CREATE INDEX IF NOT EXISTS idx_att_sessions_date ON attendance_sessions(session_date);
CREATE INDEX IF NOT EXISTS idx_att_records_student ON attendance_records(student_id);
CREATE INDEX IF NOT EXISTS idx_att_records_session ON attendance_records(session_id);

-- ========= SUMMARY VIEW =========
CREATE OR REPLACE VIEW v_attendance_daily_summary AS
SELECT
  s.session_date,
  s.session_type,
  s.block,
  s.room_id,
  s.course,
  s.year,
  count(*) FILTER (WHERE r.status = 'Present') AS present_count,
  count(*) FILTER (WHERE r.status = 'Absent')  AS absent_count,
  count(*) FILTER (WHERE r.status = 'Late')    AS late_count,
  count(*) FILTER (WHERE r.status = 'Excused') AS excused_count,
  count(*) AS total_marked
FROM attendance_sessions s
LEFT JOIN attendance_records r ON r.session_id = s.id
GROUP BY s.session_date, s.session_type, s.block, s.room_id, s.course, s.year;

-- ========= HELPER FUNCTION FOR RLS =========
CREATE OR REPLACE FUNCTION get_my_role()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;
COMMENT ON FUNCTION get_my_role IS 'Fetches the role of the currently authenticated user from their profile.';

-- ========= RPC FUNCTIONS =========
CREATE OR REPLACE FUNCTION get_or_create_session(
  p_date date,
  p_type text,
  p_block text DEFAULT NULL,
  p_room_id uuid DEFAULT NULL,
  p_course text DEFAULT NULL,
  p_year text DEFAULT NULL
) RETURNS uuid 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM attendance_sessions
  WHERE session_date = p_date 
    AND session_type = p_type
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
COMMENT ON FUNCTION get_or_create_session IS 'Creates or retrieves an attendance session ID for a given scope.';


CREATE OR REPLACE FUNCTION bulk_mark_attendance(
  p_session_id uuid,
  p_records jsonb
) RETURNS void 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec jsonb;
  v_student uuid;
  v_status text;
  v_note text;
  v_late int;
BEGIN
  FOR rec IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    v_student := (rec->>'student_id')::uuid;
    v_status  := rec->>'status';
    v_note    := rec->>'note';
    v_late    := coalesce((rec->>'late_minutes')::int, 0);

    INSERT INTO attendance_records(session_id, student_id, status, note, late_minutes, marked_by)
    VALUES (p_session_id, v_student, v_status, v_note, v_late, auth.uid())
    ON CONFLICT (session_id, student_id) DO UPDATE
      SET status = excluded.status,
          note = excluded.note,
          late_minutes = excluded.late_minutes,
          marked_at = now(),
          marked_by = auth.uid();
  END LOOP;
END;
$$;
COMMENT ON FUNCTION bulk_mark_attendance IS 'Upserts a batch of attendance records for a given session.';


CREATE OR REPLACE FUNCTION student_attendance_calendar(
  p_student_id uuid,
  p_month int,
  p_year int
) RETURNS TABLE(day date, status text, session_type text) 
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
    )::date AS d
  )
  SELECT 
    d.d AS day,
    coalesce(r.status, 'Unmarked') AS status,
    s.session_type
  FROM days d
  LEFT JOIN attendance_sessions s ON s.session_date = d.d
  LEFT JOIN attendance_records r ON r.session_id = s.id AND r.student_id = p_student_id
  WHERE s.session_type = 'NightRoll' -- Default to showing NightRoll or adapt as needed
  ORDER BY d.d ASC;
$$;
COMMENT ON FUNCTION student_attendance_calendar IS 'Provides a monthly attendance summary for a single student.';

-- ========= ROW-LEVEL SECURITY =========

-- --- attendance_sessions ---
ALTER TABLE attendance_sessions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access for Admin and Staff" ON attendance_sessions;
CREATE POLICY "Allow full access for Admin and Staff" ON attendance_sessions
  FOR ALL
  USING (get_my_role() IN ('Admin', 'Staff'));

DROP POLICY IF EXISTS "Allow students to view sessions they are part of" ON attendance_sessions;
CREATE POLICY "Allow students to view sessions they are part of" ON attendance_sessions
  FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM attendance_records 
    WHERE attendance_records.session_id = attendance_sessions.id 
    AND attendance_records.student_id = auth.uid()
  ));

-- --- attendance_records ---
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access for Admin and Staff" ON attendance_records;
CREATE POLICY "Allow full access for Admin and Staff" ON attendance_records
  FOR ALL
  USING (get_my_role() IN ('Admin', 'Staff'));

DROP POLICY IF EXISTS "Allow students to view their own records" ON attendance_records;
CREATE POLICY "Allow students to view their own records" ON attendance_records
  FOR SELECT
  USING (student_id = auth.uid());

-- --- leaves ---
ALTER TABLE leaves ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow Admin and Staff to manage all leaves" ON leaves;
CREATE POLICY "Allow Admin and Staff to manage all leaves" ON leaves
  FOR ALL
  USING (get_my_role() IN ('Admin', 'Staff'));

DROP POLICY IF EXISTS "Allow students to create and view their own leaves" ON leaves;
CREATE POLICY "Allow students to create and view their own leaves" ON leaves
  FOR ALL
  USING (student_id = auth.uid())
  WITH CHECK (student_id = auth.uid());
