-- =================================================================
-- Step 1: Drop dependent triggers
-- =================================================================

/*
  # [Operation Name] Drop Dependent Triggers
  [This operation safely removes existing triggers that depend on functions we are about to modify. This is a necessary preparatory step to avoid dependency errors.]

  ## Query Description: [This operation temporarily removes the 'on_auth_user_created' and 'trg_update_room_occupancy' triggers. They will be recreated at the end of this script. No data is lost, but new user signups or room allocations will not trigger profile/occupancy updates during the brief migration window.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [false]
  
  ## Security Implications:
  - RLS Status: [N/A]
  - Policy Changes: [No]
  - Auth Requirements: [Admin]
*/
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS trg_update_room_occupancy ON public.room_allocations;


-- =================================================================
-- Step 2: Drop all custom functions
-- =================================================================

/*
  # [Operation Name] Drop All Custom Functions
  [This operation removes all custom functions from the database. This allows them to be recreated from scratch with the correct security settings.]

  ## Query Description: [This operation drops all custom functions. This is a safe operation as they will be immediately recreated in the next step. It is part of a script to fix security advisories.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [false]
  
  ## Security Implications:
  - RLS Status: [N/A]
  - Policy Changes: [No]
  - Auth Requirements: [Admin]
*/
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.update_room_occupancy();
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, text, text, integer);
DROP FUNCTION IF EXISTS public.bulk_mark_attendance(uuid, jsonb);
DROP FUNCTION IF EXISTS public.student_attendance_calendar(uuid, integer, integer);
DROP FUNCTION IF EXISTS public.universal_search(text);


-- =================================================================
-- Step 3: Recreate all functions with security hardening
-- =================================================================

-- Function 1: handle_new_user
/*
  # [Operation Name] Recreate handle_new_user Function
  [This operation recreates the function responsible for creating a user profile after signup.]

  ## Query Description: [This recreates the handle_new_user function, adding security definer and setting a safe search_path to resolve security advisories. It ensures new users get a profile record correctly.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [Triggered by Supabase Auth]
*/
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number'
  );
  RETURN new;
END;
$$;
ALTER FUNCTION public.handle_new_user() SET search_path = 'public';


-- Function 2: update_room_occupancy
/*
  # [Operation Name] Recreate update_room_occupancy Function
  [This operation recreates the trigger function that updates a room's occupancy count when allocations change.]

  ## Query Description: [This recreates the update_room_occupancy function with proper security settings. It ensures room occupancy counts are accurate.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [Triggered by app]
*/
CREATE OR REPLACE FUNCTION public.update_room_occupancy()
RETURNS TRIGGER AS $$
DECLARE
    v_room_id UUID;
BEGIN
    IF (TG_OP = 'INSERT') THEN
        v_room_id := NEW.room_id;
    ELSIF (TG_OP = 'UPDATE') THEN
        v_room_id := COALESCE(NEW.room_id, OLD.room_id);
    ELSIF (TG_OP = 'DELETE') THEN
        v_room_id := OLD.room_id;
    END IF;

    IF v_room_id IS NOT NULL THEN
        UPDATE public.rooms
        SET 
            occupants = (
                SELECT COUNT(*) 
                FROM public.room_allocations 
                WHERE room_id = v_room_id AND is_active = true
            )
        WHERE id = v_room_id;

        UPDATE public.rooms
        SET status = CASE
            WHEN occupants > 0 THEN 'Occupied'
            ELSE 'Vacant'
        END
        WHERE id = v_room_id AND status != 'Maintenance';
    END IF;

    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
ALTER FUNCTION public.update_room_occupancy() SET search_path = 'public';


-- Function 3: get_unallocated_students
/*
  # [Operation Name] Recreate get_unallocated_students Function
  [This operation recreates the function to find students who do not have an active room allocation.]

  ## Query Description: [This recreates the get_unallocated_students function with proper security settings. It's used in the room allocation modal.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [Authenticated users]
*/
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text) AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.full_name, s.email, s.course
    FROM public.students s
    LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
    WHERE ra.id IS NULL
    ORDER BY s.full_name;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
ALTER FUNCTION public.get_unallocated_students() SET search_path = 'public';


-- Function 4: allocate_room
/*
  # [Operation Name] Recreate allocate_room Function
  [This operation recreates the function to allocate a student to a room.]

  ## Query Description: [This recreates the allocate_room function with proper security settings. It handles creating a new allocation record and ensures atomicity.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - PolicyChanges: [No]
  - Auth Requirements: [Authenticated users (Admin/Staff)]
*/
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void AS $$
BEGIN
    -- Deactivate any previous active allocation for the student
    UPDATE public.room_allocations
    SET is_active = false, end_date = now()
    WHERE student_id = p_student_id AND is_active = true;

    -- Create new active allocation
    INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
    VALUES (p_student_id, p_room_id, now(), true);
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
ALTER FUNCTION public.allocate_room(uuid, uuid) SET search_path = 'public';


-- Function 5: get_or_create_session
/*
  # [Operation Name] Recreate get_or_create_session Function
  [This operation recreates the function to get or create an attendance session.]

  ## Query Description: [This recreates the get_or_create_session function with proper security settings. It's used to manage attendance marking sessions.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [Authenticated users (Admin/Staff)]
*/
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text DEFAULT NULL, p_year integer DEFAULT NULL)
RETURNS uuid AS $$
DECLARE
    session_id uuid;
BEGIN
    SELECT id INTO session_id
    FROM public.attendance_sessions
    WHERE session_date = p_date
      AND session_type = p_type
      AND (p_course IS NULL OR course = p_course)
      AND (p_year IS NULL OR year = p_year);

    IF session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (session_date, session_type, course, year)
        VALUES (p_date, p_type, p_course, p_year)
        RETURNING id INTO session_id;
    END IF;

    RETURN session_id;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
ALTER FUNCTION public.get_or_create_session(date, text, text, integer) SET search_path = 'public';


-- Function 6: bulk_mark_attendance
/*
  # [Operation Name] Recreate bulk_mark_attendance Function
  [This operation recreates the function for bulk-updating attendance records.]

  ## Query Description: [This recreates the bulk_mark_attendance function with proper security settings. It efficiently saves multiple attendance records at once.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Medium"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [Authenticated users (Admin/Staff)]
*/
CREATE OR REPLACE FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
RETURNS void AS $$
DECLARE
    record jsonb;
BEGIN
    FOR record IN SELECT * FROM jsonb_array_elements(p_records)
    LOOP
        INSERT INTO public.attendance_records (session_id, student_id, status, note, late_minutes)
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
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;
ALTER FUNCTION public.bulk_mark_attendance(uuid, jsonb) SET search_path = 'public';


-- Function 7: student_attendance_calendar
/*
  # [Operation Name] Recreate student_attendance_calendar Function
  [This operation recreates the function to fetch a student's monthly attendance data.]

  ## Query Description: [This recreates the student_attendance_calendar function with proper security settings. It's used on the 'My Attendance' page.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [Authenticated user (Student)]
*/
CREATE OR REPLACE FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
RETURNS TABLE(day date, status text) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.session_date::date as day,
        ar.status::text
    FROM public.attendance_records ar
    JOIN public.attendance_sessions s ON ar.session_id = s.id
    WHERE ar.student_id = p_student_id
      AND EXTRACT(MONTH FROM s.session_date) = p_month
      AND EXTRACT(YEAR FROM s.session_date) = p_year
    ORDER BY s.session_date;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
ALTER FUNCTION public.student_attendance_calendar(uuid, integer, integer) SET search_path = 'public';


-- Function 8: universal_search
/*
  # [Operation Name] Recreate universal_search Function
  [This operation recreates the global search function.]

  ## Query Description: [This recreates the universal_search function with proper security settings. It powers the global search bar in the header.]
  
  ## Metadata:
  - Schema-Category: ["Data"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [Authenticated user]
*/
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json AS $$
DECLARE
    students_json json;
    rooms_json json;
    result_json json;
BEGIN
    SELECT json_agg(s) INTO students_json
    FROM (
        SELECT id, full_name AS label, '/students/' || id AS path
        FROM public.students
        WHERE full_name ILIKE '%' || p_search_term || '%'
        LIMIT 5
    ) s;

    SELECT json_agg(r) INTO rooms_json
    FROM (
        SELECT id, 'Room ' || room_number AS label, '/rooms/' || id AS path
        FROM public.rooms
        WHERE room_number ILIKE '%' || p_search_term || '%'
        LIMIT 5
    ) r;

    result_json := json_build_object(
        'students', COALESCE(students_json, '[]'::json),
        'rooms', COALESCE(rooms_json, '[]'::json)
    );

    RETURN result_json;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
ALTER FUNCTION public.universal_search(text) SET search_path = 'public';


-- =================================================================
-- Step 4: Recreate triggers
-- =================================================================

/*
  # [Operation Name] Recreate Triggers
  [This operation recreates the triggers that were dropped in Step 1, linking them to the newly secured functions.]

  ## Query Description: [This operation recreates the 'on_auth_user_created' and 'trg_update_room_occupancy' triggers. This restores automatic profile creation and room occupancy updates.]
  
  ## Metadata:
  - Schema-Category: ["Structural"]
  - Impact-Level: ["Low"]
  - Requires-Backup: [false]
  - Reversible: [true]
  
  ## Security Implications:
  - RLS Status: [Enabled]
  - Policy Changes: [No]
  - Auth Requirements: [N/A - System triggers]
*/
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

CREATE TRIGGER trg_update_room_occupancy
  AFTER INSERT OR UPDATE OR DELETE ON public.room_allocations
  FOR EACH ROW EXECUTE PROCEDURE public.update_room_occupancy();
