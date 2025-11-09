-- Previous migration failed due to inability to change function return types.
-- This script explicitly DROPS all functions before recreating them to ensure a clean state.
-- This resolves the "cannot change return type" error and hardens all functions.

/*
          # [Function Drop & Recreate]
          This script drops and recreates all custom database functions to fix a migration error and apply security hardening.

          ## Query Description: This operation will temporarily remove and then restore all custom functions in the 'public' schema. This is necessary to update their definitions and security settings (like the search_path). There should be no data loss, but there will be a brief moment during the migration where these functions are unavailable.

          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Medium"
          - Requires-Backup: false
          - Reversible: false
          
          ## Security Implications:
          - RLS Status: Unchanged
          - Policy Changes: No
          - Auth Requirements: Requires database owner privileges.
          
          ## Performance Impact:
          - Indexes: Unchanged
          - Triggers: Unchanged
          - Estimated Impact: Minimal, a brief downtime for the functions during migration.
          */

-- Drop existing functions before recreating them
DROP FUNCTION IF EXISTS public.get_unallocated_students();
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.update_room_occupancy(uuid);
DROP FUNCTION IF EXISTS public.universal_search(text);
DROP FUNCTION IF EXISTS public.get_or_create_session(date, public.attendance_session_type);
DROP FUNCTION IF EXISTS public.process_fee_payment(uuid);


-- Recreate function: get_unallocated_students
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text, contact text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.full_name, p.email, p.course, p.mobile_number AS contact
  FROM public.profiles p
  WHERE p.role = 'Student' AND NOT EXISTS (
    SELECT 1
    FROM public.room_allocations ra
    WHERE ra.student_id = p.id AND ra.is_active = true
  )
  ORDER BY p.full_name;
END;
$$;

-- Recreate function: allocate_room
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Deactivate any previous active allocation for the student
  UPDATE public.room_allocations
  SET is_active = false, end_date = now()
  WHERE student_id = p_student_id AND is_active = true;

  -- Create new active allocation
  INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, now(), true);

  -- The trigger on room_allocations will handle updating the room status and occupancy.
END;
$$;

-- Recreate function: update_room_occupancy
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  active_occupants INT;
  max_capacity INT;
BEGIN
  -- Calculate current active occupants
  SELECT count(*)
  INTO active_occupants
  FROM public.room_allocations
  WHERE room_id = p_room_id AND is_active = true;

  -- Get room's max capacity
  SELECT occupants
  INTO max_capacity
  FROM public.rooms
  WHERE id = p_room_id;

  -- Update room status based on occupancy
  IF active_occupants = 0 THEN
    UPDATE public.rooms
    SET status = 'Vacant'
    WHERE id = p_room_id AND status != 'Maintenance';
  ELSIF active_occupants >= max_capacity THEN
    UPDATE public.rooms
    SET status = 'Occupied'
    WHERE id = p_room_id AND status != 'Maintenance';
  ELSE
    -- If it was 'Occupied' but now has space, it becomes 'Vacant' (partially occupied is still vacant for new allocations)
    UPDATE public.rooms
    SET status = 'Vacant'
    WHERE id = p_room_id AND status = 'Occupied';
  END IF;
END;
$$;

-- Recreate function: universal_search
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_results json;
BEGIN
  WITH students AS (
    SELECT json_agg(json_build_object(
      'id', id,
      'label', full_name,
      'path', '/students/' || id::text
    )) AS results
    FROM public.profiles
    WHERE role = 'Student' AND full_name ILIKE '%' || p_search_term || '%'
  ),
  rooms AS (
    SELECT json_agg(json_build_object(
      'id', id,
      'label', 'Room ' || room_number,
      'path', '/rooms/' || id::text
    )) AS results
    FROM public.rooms
    WHERE room_number ILIKE '%' || p_search_term || '%'
  )
  SELECT json_build_object(
    'Students', (SELECT results FROM students),
    'Rooms', (SELECT results FROM rooms)
  )
  INTO v_results;

  RETURN v_results;
END;
$$;

-- Recreate function: get_or_create_session
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_session_type public.attendance_session_type)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_id uuid;
BEGIN
  -- Attempt to find an existing session
  SELECT id INTO v_session_id
  FROM public.attendance_sessions
  WHERE date = p_date AND session_type = p_session_type;

  -- If not found, create a new one
  IF v_session_id IS NULL THEN
    INSERT INTO public.attendance_sessions (date, session_type)
    VALUES (p_date, p_session_type)
    RETURNING id INTO v_session_id;
  END IF;

  RETURN v_session_id;
END;
$$;

-- Recreate function: process_fee_payment
CREATE OR REPLACE FUNCTION public.process_fee_payment(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fee_amount numeric;
BEGIN
  -- Get the fee amount
  SELECT amount INTO v_fee_amount
  FROM public.fees
  WHERE id = p_fee_id AND status != 'Paid';

  IF v_fee_amount IS NULL THEN
    RAISE EXCEPTION 'Fee record not found, or is already paid.';
  END IF;

  -- Update the fee status
  UPDATE public.fees
  SET status = 'Paid', payment_date = now()
  WHERE id = p_fee_id;

  -- Insert a record into the payments table
  INSERT INTO public.payments (fee_id, amount, paid_on, payment_method)
  VALUES (p_fee_id, v_fee_amount, now(), 'Card');
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.get_unallocated_students() TO authenticated;
GRANT EXECUTE ON FUNCTION public.allocate_room(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_room_occupancy(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_session(date, public.attendance_session_type) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_fee_payment(uuid) TO authenticated;
