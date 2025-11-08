/*
          # [Function Hardening and Search Finalization]
          This script resolves two security warnings and finalizes the setup for the universal search feature.

          ## Query Description: 
          This operation is safe and essential for security and functionality. It performs the following actions:
          1. Creates a dedicated 'extensions' schema to house database extensions, following best practices.
          2. Moves the 'pg_trgm' extension into this new schema, resolving the "Extension in Public" warning.
          3. Safely drops the existing user creation trigger and all custom functions.
          4. Recreates all functions from scratch with a hardened 'search_path', permanently resolving the "Function Search Path Mutable" warning.
          5. Re-establishes the user creation trigger.
          
          This operation does not affect any user data.

          ## Metadata:
          - Schema-Category: ["Structural", "Safe"]
          - Impact-Level: ["Low"]
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Moves extension: pg_trgm
          - Recreates functions: handle_new_user, universal_search
          - Recreates trigger: on_auth_user_created
          
          ## Security Implications:
          - RLS Status: Unchanged
          - Policy Changes: No
          - Auth Requirements: Admin privileges to run. This script resolves existing security warnings.
          
          ## Performance Impact:
          - Indexes: Unchanged
          - Triggers: Recreated
          - Estimated Impact: None. Improves security posture.
          */

-- Step 1: Create a dedicated schema for extensions
CREATE SCHEMA IF NOT EXISTS extensions;

-- Step 2: Move the pg_trgm extension to the new schema
ALTER EXTENSION pg_trgm SET SCHEMA extensions;

-- Step 3: Drop the dependent trigger to allow function replacement
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Step 4: Drop the old functions
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 5: Recreate the handle_new_user function securely
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
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
  
  -- If the new user is a student, create a corresponding student record
  IF new.raw_user_meta_data->>'role' = 'Student' THEN
    INSERT INTO public.students (id, full_name, email, contact)
    VALUES (
      new.id,
      new.raw_user_meta_data->>'full_name',
      new.email,
      new.raw_user_meta_data->>'mobile_number'
    );
  END IF;

  RETURN new;
END;
$$;
-- Set the search path to harden the function
ALTER FUNCTION public.handle_new_user() SET search_path = 'public';


-- Step 6: Recreate the trigger to call the new secure function
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- Step 7: Recreate the universal_search function securely
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
AS $$
DECLARE
    students_json json;
    rooms_json json;
    visitors_json json;
    maintenance_json json;
BEGIN
    -- Search Students
    SELECT json_agg(json_build_object(
        'id', s.id,
        'label', s.full_name,
        'path', '/students/' || s.id::text
    ))
    INTO students_json
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
       OR s.email ILIKE '%' || p_search_term || '%';

    -- Search Rooms
    SELECT json_agg(json_build_object(
        'id', r.id,
        'label', 'Room ' || r.room_number,
        'path', '/rooms/' || r.id::text
    ))
    INTO rooms_json
    FROM public.rooms r
    WHERE r.room_number::text ILIKE '%' || p_search_term || '%';

    -- Search Visitors
    SELECT json_agg(json_build_object(
        'id', v.id,
        'label', v.visitor_name,
        'path', '/visitors/' || v.id::text
    ))
    INTO visitors_json
    FROM public.visitors v
    WHERE v.visitor_name ILIKE '%' || p_search_term || '%';

    -- Search Maintenance Requests
    SELECT json_agg(json_build_object(
        'id', m.id,
        'label', m.issue,
        'path', '/maintenance/' || m.id::text
    ))
    INTO maintenance_json
    FROM public.maintenance_requests m
    WHERE m.issue ILIKE '%' || p_search_term || '%';

    -- Combine results into a single JSON object
    RETURN json_build_object(
        'students', COALESCE(students_json, '[]'::json),
        'rooms', COALESCE(rooms_json, '[]'::json),
        'visitors', COALESCE(visitors_json, '[]'::json),
        'maintenance', COALESCE(maintenance_json, '[]'::json)
    );
END;
$$;
-- Set the search path to harden the function, including the extensions schema
ALTER FUNCTION public.universal_search(text) SET search_path = 'public', 'extensions';
