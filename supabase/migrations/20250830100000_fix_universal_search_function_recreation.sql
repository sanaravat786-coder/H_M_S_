/*
# [Function Re-creation] Fix universal_search return type
This migration corrects an issue where the `universal_search` function could not be updated due to a return type mismatch. It safely drops the existing function and recreates it with the correct structure and security settings.

## Query Description: This operation is safe. It drops and recreates a search function. No data is modified. The application's global search feature will be briefly unavailable if this is run on a live system, but the impact is negligible.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: false (The old function is dropped)

## Structure Details:
- Drops function: `public.universal_search(text)`
- Creates function: `public.universal_search(p_search_term text)`

## Security Implications:
- RLS Status: Not Applicable
- Policy Changes: No
- Auth Requirements: The new function will be defined with `SECURITY DEFINER` and a fixed `search_path` to mitigate security risks.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. Function re-creation is a fast operation.
*/

-- Drop the existing function to allow for return type changes
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Recreate the function with the correct return type and hardened security
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_students json;
    v_rooms json;
    v_results json;
BEGIN
    -- Search students
    SELECT COALESCE(json_agg(s), '[]'::json)
    INTO v_students
    FROM (
        SELECT
            'student' AS type,
            id,
            full_name AS label,
            '/students/' || id::text AS path
        FROM public.students
        WHERE full_name ILIKE '%' || p_search_term || '%'
        LIMIT 5
    ) s;

    -- Search rooms
    SELECT COALESCE(json_agg(r), '[]'::json)
    INTO v_rooms
    FROM (
        SELECT
            'room' AS type,
            id,
            'Room ' || room_number AS label,
            '/rooms/' || id::text AS path
        FROM public.rooms
        WHERE room_number ILIKE '%' || p_search_term || '%'
        LIMIT 5
    ) r;

    -- Combine results into a single JSON object
    SELECT json_build_object(
        'students', v_students,
        'rooms', v_rooms
    )
    INTO v_results;

    RETURN v_results;
END;
$$;

-- Grant execution rights to authenticated users
GRANT EXECUTE ON FUNCTION public.universal_search(text) TO authenticated;
