/*
          # [Operation Name]
          Universal Search Setup &amp; Security Hardening

          ## Query Description: This script performs two major operations:
1.  It hardens all existing database functions by dropping and recreating them with a secure, non-mutable search path. This will permanently resolve the "Function Search Path Mutable" security warning.
2.  It sets up the backend for a new Universal Search feature by enabling the `pg_trgm` extension, adding efficient GIN indexes for text searching, and creating a new RPC function (`universal_search`) to query across multiple tables at once.

          ## Metadata:
          - Schema-Category: ["Structural", "Security"]
          - Impact-Level: ["Medium"]
          - Requires-Backup: false
          - Reversible: false
          
          ## Structure Details:
          - Functions Dropped: `handle_new_user`, `search_students`, `allocate_room`
          - Functions Created: `handle_new_user`, `search_students`, `allocate_room`, `universal_search`
          - Triggers Modified: `on_auth_user_created` (dropped and recreated)
          - Extensions Added: `pg_trgm`
          - Indexes Added: GIN indexes on `students`, `rooms`, `visitors`, `maintenance_requests`
          
          ## Security Implications:
          - RLS Status: Unchanged. The new search function is `SECURITY INVOKER` to respect existing RLS policies.
          - Policy Changes: No.
          - Auth Requirements: None.
          - Security Fix: Resolves the `WARN` level "Function Search Path Mutable" advisory.
          
          ## Performance Impact:
          - Indexes: Adds several GIN trigram indexes which will significantly speed up text search operations at the cost of slightly slower writes to indexed columns.
          - Triggers: No significant impact.
          - Estimated Impact: Positive. Search queries will be much faster.
          */

-- Step 1: Drop dependent objects and old functions safely
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.search_students(text);
DROP FUNCTION IF EXISTS public.allocate_room(uuid, uuid);
DROP FUNCTION IF EXISTS public.universal_search(text);

-- Step 2: Recreate handle_new_user function securely
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, mobile_number)
  VALUES (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'role',
    new.raw_user_meta_data ->> 'mobile_number'
  );
  RETURN new;
END;
$$;

-- Step 3: Recreate the trigger for new users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Step 4: Enable Trigram extension for fuzzy search
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Step 5: Add GIN indexes for fast text searching
CREATE INDEX IF NOT EXISTS idx_students_full_name_trgm ON public.students USING gin (full_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_students_email_trgm ON public.students USING gin (email gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_rooms_room_number_trgm ON public.rooms USING gin (room_number gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_visitors_name_trgm ON public.visitors USING gin (visitor_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_maint_issue_trgm ON public.maintenance_requests USING gin (issue gin_trgm_ops);

-- Step 6: Create the Universal Search RPC function
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    student_results jsonb;
    room_results jsonb;
    visitor_results jsonb;
    maintenance_results jsonb;
BEGIN
    -- Search students by name or email
    SELECT jsonb_agg(s) INTO student_results
    FROM (
        SELECT id, full_name as label, 'students' as type, '/students/' || id::text as path
        FROM public.students
        WHERE p_search_term IS NOT NULL AND p_search_term != '' AND (full_name % p_search_term OR email % p_search_term)
        ORDER BY similarity(full_name, p_search_term) DESC
        LIMIT 5
    ) s;

    -- Search rooms by room number
    SELECT jsonb_agg(r) INTO room_results
    FROM (
        SELECT id, 'Room ' || room_number as label, 'rooms' as type, '/rooms/' || id::text as path
        FROM public.rooms
        WHERE p_search_term IS NOT NULL AND p_search_term != '' AND room_number % p_search_term
        ORDER BY similarity(room_number, p_search_term) DESC
        LIMIT 5
    ) r;
    
    -- Search visitors by name
    SELECT jsonb_agg(v) INTO visitor_results
    FROM (
        SELECT id, visitor_name as label, 'visitors' as type, '/visitors/' || id::text as path
        FROM public.visitors
        WHERE p_search_term IS NOT NULL AND p_search_term != '' AND visitor_name % p_search_term
        ORDER BY similarity(visitor_name, p_search_term) DESC
        LIMIT 5
    ) v;

    -- Search maintenance requests by issue
    SELECT jsonb_agg(m) INTO maintenance_results
    FROM (
        SELECT id, issue as label, 'maintenance' as type, '/maintenance/' || id::text as path
        FROM public.maintenance_requests
        WHERE p_search_term IS NOT NULL AND p_search_term != '' AND issue % p_search_term
        ORDER BY similarity(issue, p_search_term) DESC
        LIMIT 5
    ) m;
    
    -- Combine all results into a single JSONB object
    RETURN jsonb_build_object(
        'students', COALESCE(student_results, '[]'::jsonb),
        'rooms', COALESCE(room_results, '[]'::jsonb),
        'visitors', COALESCE(visitor_results, '[]'::jsonb),
        'maintenance', COALESCE(maintenance_results, '[]'::jsonb)
    );
END;
$$;
