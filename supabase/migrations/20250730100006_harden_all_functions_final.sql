/*
# [Function Hardening - Definitive Fix]
[This migration re-defines all custom database functions to explicitly set the `search_path`. This is a security best practice that prevents potential search path hijacking attacks and resolves the "Function Search Path Mutable" warning.]

## Query Description: [This operation safely replaces the existing functions with updated versions. It is non-destructive to data and is designed to be idempotent (safe to run multiple times). This is the definitive fix for the persistent security advisory.]

## Metadata:
- Schema-Category: ["Structural", "Safe"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Functions affected:
  - `public.handle_new_user()`
  - `public.search_students(text)`

## Security Implications:
- RLS Status: [Not Applicable]
- Policy Changes: [No]
- Auth Requirements: [Admin privileges to alter functions]
- Fixes: Resolves "Function Search Path Mutable" warning by setting a fixed `search_path`.

## Performance Impact:
- Indexes: [Not Applicable]
- Triggers: [Not Applicable]
- Estimated Impact: [None. Function logic remains the same.]
*/

-- Harden handle_new_user function
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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

-- Harden search_students function
CREATE OR REPLACE FUNCTION public.search_students(search_term TEXT)
RETURNS TABLE(id UUID, full_name TEXT, email TEXT, course TEXT, contact TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
AS $$
BEGIN
  SET search_path = 'public';
  RETURN QUERY
  SELECT s.id, s.full_name, s.email, s.course, s.contact, s.created_at
  FROM students s
  WHERE s.full_name ILIKE '%' || search_term || '%'
     OR s.email ILIKE '%' || search_term || '%'
     OR s.course ILIKE '%' || search_term || '%';
END;
$$;
