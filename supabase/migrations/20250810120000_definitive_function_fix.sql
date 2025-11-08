/*
# [Security Hardening] Definitive Fix for All Database Functions
[This migration completely rebuilds all custom database functions from scratch to resolve persistent errors and security warnings related to function definitions and search paths.]

## Query Description: [This operation will first DROP (delete) the existing `handle_new_user` and `search_students` functions, and then immediately CREATE them again with the correct, secure configuration. This is a safe and necessary step to fix the underlying issues. There is no risk to your data, as only the function definitions are being replaced.]

## Metadata:
- Schema-Category: ["Structural", "Safe"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Functions Dropped: `handle_new_user`, `search_students`
- Functions Created: `handle_new_user`, `search_students`

## Security Implications:
- RLS Status: [Unaffected]
- Policy Changes: [No]
- Auth Requirements: [None]
- Mitigates: `Function Search Path Mutable` vulnerability and `cannot change return type` error.

## Performance Impact:
- Indexes: [Unaffected]
- Triggers: [Unaffected]
- Estimated Impact: [None]
*/

-- Drop the existing functions to ensure a clean slate and prevent errors.
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.search_students(TEXT);


-- Recreate the function to create a profile for a new user, with security settings.
CREATE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public' -- Harden the function against search path attacks.
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  RETURN new;
END;
$$;


-- Recreate the function to search students, with security settings.
CREATE FUNCTION public.search_students(p_search_term TEXT)
RETURNS TABLE(id UUID, full_name TEXT, email TEXT, course TEXT, contact TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
STABLE -- Mark as stable as it only reads data, which is a performance best practice.
SET search_path = 'public' -- Harden the function against search path attacks.
AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, s.full_name, s.email, s.course, s.contact, s.created_at
    FROM public.students s
    WHERE s.full_name ILIKE '%' || p_search_term || '%'
       OR s.email ILIKE '%' || p_search_term || '%'
       OR s.course ILIKE '%' || p_search_term || '%';
END;
$$;
