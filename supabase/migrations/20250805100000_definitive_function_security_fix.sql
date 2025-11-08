/*
# [Operation Name]
Drop Existing User Creation Trigger

## Query Description:
This operation safely removes the existing trigger responsible for creating user profiles. This is a temporary step to allow for the underlying function to be updated securely. The trigger will be recreated immediately after the function is updated. There is no risk to existing data.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Drops trigger: on_auth_user_created on table auth.users

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None

## Performance Impact:
- Triggers: Removed (temporarily)
- Estimated Impact: Negligible
*/
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;


/*
# [Operation Name]
Drop Existing Custom Functions

## Query Description:
This operation removes the old versions of the `handle_new_user` and `search_students` functions. This is necessary to redefine them with improved security settings.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: false (but they are recreated immediately)

## Structure Details:
- Drops function: handle_new_user()
- Drops function: search_students(text)

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None

## Performance Impact:
- Triggers: None
- Estimated Impact: Negligible
*/
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.search_students(text);


/*
# [Operation Name]
Recreate and Secure New User Handler Function

## Query Description:
This operation recreates the function that handles new user sign-ups. It is now defined with a secure, non-mutable search path to resolve the "Function Search Path Mutable" security warning. This function automatically creates a profile for a new user in the `public.profiles` table after they sign up.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Creates function: handle_new_user()

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None

## Performance Impact:
- Triggers: None
- Estimated Impact: Negligible
*/
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  RETURN new;
END;
$$;


/*
# [Operation Name]
Recreate and Secure Student Search Function

## Query Description:
This operation recreates the function used for searching students. It is now defined with a secure, non-mutable search path to resolve the "Function Search Path Mutable" security warning. This function allows for efficient searching of student records.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Creates function: search_students(text)

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None

## Performance Impact:
- Indexes: This function could benefit from an index on the columns being searched.
- Estimated Impact: Low
*/
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
       OR s.email ILIKE '%' || search_term || '%'
       OR s.course ILIKE '%' || search_term || '%';
END;
$$;


/*
# [Operation Name]
Recreate New User Trigger

## Query Description:
This operation recreates the trigger on the `auth.users` table. It now securely calls the updated `handle_new_user` function to ensure a profile is created for every new user.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Creates trigger: on_auth_user_created on table auth.users

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: This trigger is essential for the application's user management flow.

## Performance Impact:
- Triggers: Added
- Estimated Impact: Negligible, as it only fires on new user creation.
*/
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
