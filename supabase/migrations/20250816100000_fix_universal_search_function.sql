/*
# [Function Fix] Recreate universal_search function
This script resolves a migration error by dropping and recreating the 'universal_search' function. The previous function definition had a different return type, which cannot be changed with 'CREATE OR REPLACE'. This version also hardens the function's security by setting a fixed search_path.

## Query Description:
- This operation drops the existing 'universal_search' function and immediately recreates it.
- There is no risk of data loss, but the search feature will be briefly unavailable if called during the migration.
- The new function returns a JSONB object, which is what the frontend search component expects.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by restoring the old function definition)

## Security Implications:
- RLS Status: Not directly applicable to the function, but it queries RLS-protected tables.
- Policy Changes: No
- Auth Requirements: The function is SECURITY DEFINER but is now safer due to the fixed search_path.

## Performance Impact:
- Indexes: This function benefits from indexes on the columns being searched (e.g., students.full_name, rooms.room_number).
- Triggers: None
- Estimated Impact: Low. The function is only called on user interaction.
*/

-- Drop the old function to allow for a new return type
DROP FUNCTION IF EXISTS universal_search(text);

-- Recreate the function with the correct return type (jsonb) and a secure search_path
CREATE OR REPLACE FUNCTION universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
-- Set a secure search_path to mitigate hijacking attacks
SET search_path = public
AS $$
DECLARE
  v_students jsonb;
  v_rooms jsonb;
BEGIN
  -- Search students by name
  SELECT jsonb_agg(jsonb_build_object(
    'id', s.id,
    'label', s.full_name,
    'path', '/students/' || s.id::text
  ))
  INTO v_students
  FROM students s
  WHERE s.full_name ILIKE '%' || p_search_term || '%';

  -- Search rooms by number
  SELECT jsonb_agg(jsonb_build_object(
    'id', r.id,
    'label', 'Room ' || r.room_number,
    'path', '/rooms/' || r.id::text
  ))
  INTO v_rooms
  FROM rooms r
  WHERE r.room_number ILIKE '%' || p_search_term || '%';

  -- Combine results into a single JSONB object
  RETURN jsonb_build_object(
    'Students', coalesce(v_students, '[]'::jsonb),
    'Rooms', coalesce(v_rooms, '[]'::jsonb)
  );
END;
$$;
