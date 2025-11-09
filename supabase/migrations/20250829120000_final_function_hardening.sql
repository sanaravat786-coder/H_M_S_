/*
  # [Function Hardening] Final Security Fix for Search Path
  [This migration script re-creates all user-defined functions to explicitly set the `search_path`. This is a critical security measure that prevents a class of vulnerabilities where a malicious user could potentially execute arbitrary code by manipulating the function's execution context. By locking down the search path, we ensure that functions only look for objects (tables, types, etc.) in schemas we explicitly trust.]

  ## Query Description: [This operation is safe and non-destructive. It replaces existing function definitions with more secure versions. No data will be lost or altered. This is a preventative security enhancement to address the "Function Search Path Mutable" advisory.]
  
  ## Metadata:
  - Schema-Category: ["Security", "Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Structure Details:
  - Functions being altered:
    - create_user_profile()
    - universal_search(p_search_term TEXT)
    - get_unallocated_students()
    - allocate_room(p_student_id UUID, p_room_id UUID)
    - update_room_occupancy()
    - bulk_mark_attendance(p_session_id UUID, p_records JSONB[])
    - get_or_create_session(p_date DATE, p_type TEXT, p_course TEXT, p_year INT)
    - student_attendance_calendar(p_student_id UUID, p_month INT, p_year INT)
  
  ## Security Implications:
  - RLS Status: [Unaffected]
  - Policy Changes: [No]
  - Auth Requirements: [This change hardens security by mitigating search_path attacks.]
  
  ## Performance Impact:
  - Indexes: [Unaffected]
  - Triggers: [Unaffected]
  - Estimated Impact: [Negligible. This is a security and definition change, not a performance-heavy operation.]
*/

-- Harden create_user_profile function
CREATE OR REPLACE FUNCTION public.create_user_profile()
RETURNS TRIGGER AS $$
BEGIN
  -- Use a transaction block to ensure atomicity
  BEGIN
    INSERT INTO public.profiles (id, full_name, role, mobile_number)
    VALUES (
      NEW.id,
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'role',
      NEW.raw_user_meta_data->>'mobile_number'
    );
  EXCEPTION
    WHEN unique_violation THEN
      -- This can happen in rare race conditions. Ignore it.
      NULL;
  END;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
ALTER FUNCTION public.create_user_profile() SET search_path = 'public';

-- Harden universal_search function
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term TEXT)
RETURNS JSONB
AS $$
DECLARE
    results JSONB;
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
            FROM public.students s
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
            FROM public.rooms r
            WHERE r.room_number ILIKE '%' || p_search_term || '%'
        )
    ) INTO results;

    RETURN results;
END;
$$ LANGUAGE plpgsql STABLE SECURITY INVOKER;
ALTER FUNCTION public.universal_search(TEXT) SET search_path = 'public';

-- Harden get_unallocated_students function
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id UUID, full_name TEXT, email TEXT, course TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.full_name, s.email, s.course
    FROM public.students s
    LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = TRUE
    WHERE ra.id IS NULL
    ORDER BY s.full_name;
END;
$$ LANGUAGE plpgsql STABLE SECURITY INVOKER;
ALTER FUNCTION public.get_unallocated_students() SET search_path = 'public';

-- Harden allocate_room function
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id UUID, p_room_id UUID)
RETURNS void AS $$
BEGIN
    -- Deactivate any previous active allocation for the student
    UPDATE public.room_allocations
    SET end_date = now(), is_active = FALSE
    WHERE student_id = p_student_id AND is_active = TRUE;

    -- Create new allocation
    INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
    VALUES (p_student_id, p_room_id, now(), TRUE);

END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
ALTER FUNCTION public.allocate_room(UUID, UUID) SET search_path = 'public';

-- Harden update_room_occupancy function
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS TRIGGER AS $$
DECLARE
    v_room_id UUID;
BEGIN
    IF (TG_OP = 'DELETE' OR TG_OP = 'UPDATE') THEN
        v_room_id := OLD.room_id;
    ELSE
        v_room_id := NEW.room_id;
    END IF;

    UPDATE public.rooms
    SET 
        occupants = (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = v_room_id AND is_active = TRUE),
        status = CASE 
            WHEN status = 'Maintenance' THEN 'Maintenance'::public.room_status
            WHEN (SELECT COUNT(*) FROM public.room_allocations WHERE room_id = v_room_id AND is_active = TRUE) > 0 THEN 'Occupied'::public.room_status
            ELSE 'Vacant'::public.room_status
        END
    WHERE id = v_room_id;

    RETURN NULL; -- result is ignored since this is an AFTER trigger
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
ALTER FUNCTION public.update_room_occupancy() SET search_path = 'public';

-- Harden bulk_mark_attendance function
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id UUID, p_records JSONB[])
RETURNS void AS $$
DECLARE
    record JSONB;
BEGIN
    FOREACH record IN ARRAY p_records
    LOOP
        INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
        VALUES (
            p_session_id,
            (record->>'student_id')::UUID,
            (record->>'status')::public.attendance_status,
            record->>'note',
            (record->>'late_minutes')::INT
        )
        ON CONFLICT (session_id, student_id)
        DO UPDATE SET
            status = EXCLUDED.status,
            note = EXCLUDED.note,
            late_minutes = EXCLUDED.late_minutes;
    END LOOP;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
ALTER FUNCTION public.bulk_mark_attendance(UUID, JSONB[]) SET search_path = 'public';

-- Harden get_or_create_session function
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date DATE, p_type TEXT, p_course TEXT, p_year INT)
RETURNS UUID AS $$
DECLARE
    session_id UUID;
BEGIN
    -- Attempt to find an existing session
    SELECT id INTO session_id
    FROM public.attendance_sessions
    WHERE session_date = p_date
      AND session_type = p_type
      AND (course = p_course OR (course IS NULL AND p_course IS NULL))
      AND (year = p_year OR (year IS NULL AND p_year IS NULL));

    -- If not found, create a new one
    IF session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (session_date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
ALTER FUNCTION public.get_or_create_session(DATE, TEXT, TEXT, INT) SET search_path = 'public';

-- Harden student_attendance_calendar function
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id UUID, p_month INT, p_year INT)
RETURNS TABLE(day DATE, status public.attendance_status) AS $$
BEGIN
    RETURN QUERY
    SELECT
        ar.created_at::DATE AS day,
        ar.status
    FROM public.attendance_records ar
    JOIN public.attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.session_date) = p_month
      AND EXTRACT(YEAR FROM s.session_date) = p_year
    ORDER BY ar.created_at::DATE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY INVOKER;
ALTER FUNCTION public.student_attendance_calendar(UUID, INT, INT) SET search_path = 'public';
