/*
# [Function Hardening] Harden universal_search

## Query Description:
This operation secures the `universal_search` function by explicitly setting its `search_path` to 'public'. This is a best practice that prevents potential security vulnerabilities related to search path hijacking. This change is non-destructive and has no impact on existing data.

## Metadata:
- Schema-Category: ["Security", "Safe"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Modifies function: `universal_search(text)`

## Security Implications:
- RLS Status: [Not Applicable]
- Policy Changes: [No]
- Auth Requirements: [None]

## Performance Impact:
- Indexes: [No change]
- Triggers: [No change]
- Estimated Impact: [None]
*/
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS TABLE(id uuid, type text, label text, path text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  RETURN QUERY
    -- Search Students
    SELECT s.id, 'Student' AS type, s.full_name AS label, '/students/' || s.id::text AS path
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
       OR s.email ILIKE '%' || p_search_term || '%'
    UNION ALL
    -- Search Rooms
    SELECT r.id, 'Room' AS type, 'Room ' || r.room_number AS label, '/rooms/' || r.id::text AS path
    FROM public.rooms r
    WHERE r.room_number ILIKE '%' || p_search_term || '%';
END;
$$;
