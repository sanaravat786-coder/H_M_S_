/*
          # [Function Hardening] Final Security Fix
          [This operation hardens the final remaining function by setting its search_path, resolving the last security advisory warning.]

          ## Query Description: [This is a safe, non-destructive operation that modifies the metadata of an existing function to improve security. It does not affect any data or table structures.]
          
          ## Metadata:
          - Schema-Category: ["Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: [false]
          - Reversible: [true]
          
          ## Structure Details:
          - Modifies function: `universal_search`
          
          ## Security Implications:
          - RLS Status: [Not Applicable]
          - Policy Changes: [No]
          - Auth Requirements: [None]
          
          ## Performance Impact:
          - Indexes: [None]
          - Triggers: [None]
          - Estimated Impact: [Negligible. This is a metadata change.]
          */

CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_results jsonb;
BEGIN
    SELECT jsonb_build_object(
        'students', (SELECT jsonb_agg(jsonb_build_object('id', s.id, 'label', s.full_name, 'path', '/students/' || s.id::text)) FROM students s WHERE s.full_name ILIKE '%' || p_search_term || '%'),
        'rooms', (SELECT jsonb_agg(jsonb_build_object('id', r.id, 'label', 'Room ' || r.room_number, 'path', '/rooms/' || r.id::text)) FROM rooms r WHERE r.room_number ILIKE '%' || p_search_term || '%')
    )
    INTO v_results;

    RETURN v_results;
END;
$function$;
