/*
# [Function Hardening] Secure All Custom Functions
[This operation secures all custom functions (`handle_new_user`, `search_students`) by explicitly setting their search path and defining them as SECURITY DEFINER. This is a comprehensive fix to resolve any lingering "Function Search Path Mutable" warnings.]

## Query Description: [This query updates all custom functions to be more secure. It sets a fixed `search_path` to `public`, preventing potential hijacking attacks. This is a safe, non-destructive operation that improves security without affecting data.]

## Metadata:
- Schema-Category: ["Safe", "Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Function: `public.handle_new_user()`
- Function: `public.search_students(search_term TEXT)`

## Security Implications:
- RLS Status: [Not Applicable]
- Policy Changes: [No]
- Auth Requirements: [Admin privileges to alter functions]
- Fixes: Resolves "Function Search Path Mutable" warning.

## Performance Impact:
- Indexes: [No change]
- Triggers: [No change]
- Estimated Impact: [None]
*/

-- Harden the handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  
  -- If the new user is a student, create a corresponding entry in the students table
  IF new.raw_user_meta_data->>'role' = 'Student' THEN
    INSERT INTO public.students (id, full_name, email)
    VALUES (new.id, new.raw_user_meta_data->>'full_name', new.email);
  END IF;
  
  RETURN new;
END;
$$;

-- Harden the search_students function
CREATE OR REPLACE FUNCTION public.search_students(search_term TEXT)
RETURNS TABLE(id UUID, full_name TEXT, email TEXT, course TEXT, contact TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course, s.contact
  FROM public.students s
  WHERE s.full_name ILIKE '%' || search_term || '%'
     OR s.email ILIKE '%' || search_term || '%';
END;
$$;
