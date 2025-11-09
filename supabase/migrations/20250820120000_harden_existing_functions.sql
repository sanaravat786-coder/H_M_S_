/*
# [Function Hardening]
This script hardens existing database functions by explicitly setting the `search_path`. This resolves the "Function Search Path Mutable" security advisory by preventing potential hijacking of function execution by malicious actors who might alter the session's search path.

## Query Description: This operation redefines four existing functions (`universal_search`, `get_unallocated_students`, `allocate_room`, `update_room_occupancy`) to include `SET search_path = ''`. This is a non-destructive, safe operation that enhances security without altering data.

## Metadata:
- Schema-Category: "Safe"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by redeploying the functions without the `SET search_path` clause)

## Structure Details:
- Modifies function: `universal_search(text)`
- Modifies function: `get_unallocated_students()`
- Modifies function: `allocate_room(uuid, uuid)`
- Modifies function: `update_room_occupancy(uuid)`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: Unchanged
- Mitigates: `search_path` manipulation attacks.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible.
*/

-- Harden universal_search function
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN jsonb_build_object(
    'students', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'label', s.full_name,
          'path', '/students/' || s.id::text
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
          'path', '/rooms/' || r.id::text
        )
      )
      FROM public.rooms r
      WHERE r.room_number ILIKE '%' || p_search_term || '%'
    )
  );
END;
$$;

-- Harden get_unallocated_students function
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT s.id, s.full_name, s.email, s.course
  FROM public.students s
  LEFT JOIN public.room_allocations ra ON s.id = ra.student_id AND ra.is_active = true
  WHERE ra.id IS NULL
  ORDER BY s.full_name;
$$;

-- Harden allocate_room function
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Ensure student is not already actively allocated
  IF EXISTS (SELECT 1 FROM public.room_allocations WHERE student_id = p_student_id AND is_active = true) THEN
    RAISE EXCEPTION 'Student is already allocated to an active room.';
  END IF;

  -- Insert new active allocation
  INSERT INTO public.room_allocations(student_id, room_id, start_date, is_active)
  VALUES (p_student_id, p_room_id, now(), true);
END;
$$;

-- Harden update_room_occupancy function
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.rooms
  SET occupants = (
    SELECT COUNT(*)
    FROM public.room_allocations
    WHERE room_id = p_room_id AND is_active = true
  )
  WHERE id = p_room_id;
END;
$$;
