/*
# [Security Hardening] Set search_path for all functions
This migration re-creates all custom functions to explicitly set the `search_path`. This is a critical security measure to prevent function hijacking by malicious users who might create objects (like tables or functions) in their own schemas. By setting a safe `search_path`, we ensure that functions resolve to the correct, intended objects within the `public` schema.

## Query Description: 
- **Impact:** This operation will temporarily drop and then re-create several functions. There is no data loss risk, but for a very brief moment during the migration, these functions will be unavailable.
- **Safety:** This is a safe and recommended security practice. It makes the database more resilient to certain types of attacks.
- **Recommendation:** Apply this migration during a low-traffic period if possible, although the downtime for each function is negligible.

## Metadata:
- Schema-Category: "Security"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by reverting to a previous migration)

## Structure Details:
- Functions being modified:
  - is_admin()
  - is_staff()
  - get_user_role(uuid)
  - get_unallocated_students()
  - allocate_room(uuid, uuid)
  - update_room_occupancy(uuid)
  - universal_search(text)
  - get_or_create_session(date, attendance_session_type)
  - process_fee_payment(uuid)
  - handle_new_user() (trigger function)

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Functions are re-created with `SECURITY DEFINER` where appropriate, and permissions are re-granted. This change hardens security by preventing search_path attacks.

## Performance Impact:
- Indexes: None
- Triggers: The `handle_new_user` trigger function is updated.
- Estimated Impact: Negligible performance impact. The primary change is for security.
*/

-- Drop existing functions before recreating them to avoid "already exists" errors.
-- The order matters due to dependencies.
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.process_fee_payment(uuid);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, attendance_session_type);
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.get_user_role(uuid);
DROP FUNCTION IF EXISTS public.is_admin();
DROP FUNCTION IF EXISTS public.is_staff();
-- Trigger function needs to be handled with the trigger itself
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();


-- Recreate functions with security best practices

-- Function: is_admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid() AND role = 'Admin'
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- Function: is_staff
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid() AND (role = 'Admin' OR role = 'Staff')
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.is_staff() TO authenticated;

-- Function: get_user_role
CREATE OR REPLACE FUNCTION public.get_user_role(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
DECLARE
  v_role text;
BEGIN
  SELECT role INTO v_role
  FROM public.profiles
  WHERE id = p_user_id;
  RETURN v_role;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_user_role(uuid) TO authenticated;

-- Function: get_unallocated_students
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text, contact text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name, p.email, p.course, p.contact
  FROM public.profiles p
  WHERE p.role = 'Student'
  AND NOT EXISTS (
    SELECT 1
    FROM public.room_allocations ra
    WHERE ra.student_id = p.id AND ra.is_active = true
  )
  ORDER BY p.full_name;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_unallocated_students() TO authenticated;

-- Function: update_room_occupancy
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
DECLARE
  active_occupants int;
BEGIN
  SELECT count(*)
  INTO active_occupants
  FROM public.room_allocations
  WHERE room_id = p_room_id AND is_active = true;

  UPDATE public.rooms
  SET status = CASE
    WHEN active_occupants >= occupants THEN 'Occupied'
    ELSE 'Vacant'
  END
  WHERE id = p_room_id AND status != 'Maintenance';
END;
$$;
GRANT EXECUTE ON FUNCTION public.update_room_occupancy(uuid) TO authenticated;

-- Function: allocate_room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
DECLARE
  v_room_capacity int;
  v_current_occupants int;
BEGIN
  -- Check if user is Admin or Staff
  IF NOT (public.is_admin() OR public.is_staff()) THEN
    RAISE EXCEPTION 'Only Admin or Staff can allocate rooms';
  END IF;

  -- Get room capacity and current occupancy
  SELECT occupants INTO v_room_capacity FROM public.rooms WHERE id = p_room_id;
  SELECT COUNT(*) INTO v_current_occupants FROM public.room_allocations WHERE room_id = p_room_id AND is_active = true;

  -- Check if room is full
  IF v_current_occupants >= v_room_capacity THEN
    RAISE EXCEPTION 'This room is already full.';
  END IF;

  -- Deactivate any previous active allocation for the student
  UPDATE public.room_allocations
  SET is_active = false, end_date = now()
  WHERE student_id = p_student_id AND is_active = true;

  -- Insert new allocation
  INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, now(), true);

  -- Update room status
  PERFORM public.update_room_occupancy(p_room_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.allocate_room(uuid, uuid) TO authenticated;


-- Function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
DECLARE
    v_results json;
BEGIN
    SELECT json_build_object(
        'students', (
            SELECT json_agg(
                json_build_object(
                    'id', id,
                    'label', full_name || ' (' || email || ')',
                    'path', '/students/' || id
                )
            )
            FROM public.profiles
            WHERE role = 'Student' AND (full_name ILIKE '%' || p_search_term || '%' OR email ILIKE '%' || p_search_term || '%')
            LIMIT 5
        ),
        'rooms', (
            SELECT json_agg(
                json_build_object(
                    'id', id,
                    'label', 'Room ' || room_number || ' (' || type || ')',
                    'path', '/rooms/' || id
                )
            )
            FROM public.rooms
            WHERE room_number ILIKE '%' || p_search_term || '%'
            LIMIT 5
        )
    ) INTO v_results;

    RETURN v_results;
END;
$$;
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO authenticated;

-- Function: get_or_create_session
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_session_type attendance_session_type)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  -- Allow students to call this for self-attendance marking
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_session_id
    FROM public.attendance_sessions
    WHERE date = p_date AND session_type = p_session_type;

    IF v_session_id IS NULL THEN
      -- Only admin/staff can create new sessions
      IF (public.is_admin() OR public.is_staff()) THEN
        INSERT INTO public.attendance_sessions (date, session_type)
        VALUES (p_date, p_session_type)
        RETURNING id INTO v_session_id;
      ELSE
        -- If a student tries to mark attendance for a session that doesn't exist, do nothing.
        -- This prevents students from creating sessions for future dates.
        RETURN NULL;
      END IF;
    END IF;

    RETURN v_session_id;
  ELSE
    RAISE EXCEPTION 'User must be authenticated.';
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, attendance_session_type) TO authenticated;


-- Function: process_fee_payment
CREATE OR REPLACE FUNCTION public.process_fee_payment(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
DECLARE
  v_student_id uuid;
  v_amount numeric;
BEGIN
  -- Get fee details and ensure it belongs to the current user
  SELECT student_id, amount INTO v_student_id, v_amount
  FROM public.fees
  WHERE id = p_fee_id AND student_id = auth.uid();

  IF v_student_id IS NULL THEN
    RAISE EXCEPTION 'Fee record not found or you do not have permission to pay it.';
  END IF;

  -- Update fee status
  UPDATE public.fees
  SET status = 'Paid', payment_date = now()
  WHERE id = p_fee_id;

  -- Insert into payments table
  INSERT INTO public.payments (fee_id, amount, paid_on, payment_method)
  VALUES (p_fee_id, v_amount, now(), 'Online');
END;
$$;
GRANT EXECUTE ON FUNCTION public.process_fee_payment(uuid) TO authenticated;

-- Trigger Function: handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = '';
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, contact, course, joining_date)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number',
    new.raw_user_meta_data->>'course',
    (new.raw_user_meta_data->>'joining_date')::date
  );

  IF new.raw_user_meta_data->>'room_number' IS NOT NULL AND new.raw_user_meta_data->>'room_number' != '' THEN
    DECLARE
      v_room_id uuid;
    BEGIN
      SELECT id INTO v_room_id FROM public.rooms WHERE room_number = (new.raw_user_meta_data->>'room_number');
      IF v_room_id IS NOT NULL THEN
        INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
        VALUES (new.id, v_room_id, now(), true);
        PERFORM public.update_room_occupancy(v_room_id);
      END IF;
    EXCEPTION
      WHEN others THEN
        RAISE NOTICE 'Could not allocate room during sign-up: %', SQLERRM;
    END;
  END IF;

  RETURN new;
END;
$$;

-- Recreate the trigger
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
