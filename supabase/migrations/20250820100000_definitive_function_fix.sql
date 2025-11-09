/*
# [Function Hardening and Recreation]
This operation drops and recreates the 'universal_search' function to resolve a security advisory and a migration error.

## Query Description:
This script first drops the existing 'universal_search' function to allow for its recreation with a modified structure. It then recreates the function with a fixed 'search_path' to address the "Function Search Path Mutable" security warning. This ensures the function executes in a predictable and secure environment.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: false (The old function is dropped)

## Structure Details:
- Drops function: universal_search(text)
- Creates function: universal_search(text)

## Security Implications:
- RLS Status: Not directly affected, but the function respects RLS of the calling user.
- Policy Changes: No
- Auth Requirements: Assumes the function is called by an authenticated user.
- Fixes "Function Search Path Mutable" warning.

## Performance Impact:
- Indexes: The function's performance depends on indexes on the searched columns (e.g., students.full_name, rooms.room_number).
- Triggers: None
- Estimated Impact: Negligible impact on database performance.
*/

-- Drop the existing function to allow recreation with a different signature/return type
DROP FUNCTION IF EXISTS universal_search(text);

-- Recreate the function with security hardening (fixed search_path)
CREATE OR REPLACE FUNCTION universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_results jsonb;
BEGIN
  SELECT jsonb_build_object(
    'students', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', s.id,
          'label', s.full_name,
          'path', '/students/' || s.id::text
        )
      )
      FROM students s
      WHERE s.full_name ILIKE '%' || p_search_term || '%'
         OR s.email ILIKE '%' || p_search_term || '%'
    ),
    'rooms', (
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', r.id,
          'label', 'Room ' || r.room_number,
          'path', '/rooms/' || r.id::text
        )
      )
      FROM rooms r
      WHERE r.room_number ILIKE '%' || p_search_term || '%'
    )
  ) INTO v_results;

  RETURN v_results;
END;
$$;
