/*
          # [Function] Create User Profile If Not Exists
          This function creates a profile for a newly signed-up user. It's designed to be called from the client-side after a successful login event. This replaces the previous database trigger approach, which is restricted by Supabase's security policies in the dashboard environment.

          ## Query Description: 
          - This operation creates a new PL/pgSQL function `create_user_profile_if_not_exists`.
          - The function is idempotent; it checks if a profile already exists for the current user (auth.uid()) before attempting to insert a new one, preventing errors or duplicates.
          - It securely reads the user's metadata (full_name, role, mobile_number) from `auth.users` to populate the `public.profiles` and `public.students` tables.
          - This is a safe, non-destructive operation that only adds data.

          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true (the function can be dropped)
          
          ## Structure Details:
          - Creates function: `public.create_user_profile_if_not_exists()`
          
          ## Security Implications:
          - RLS Status: Not applicable to function creation itself.
          - Policy Changes: No
          - Auth Requirements: The function uses `auth.uid()` and is `SECURITY DEFINER`, ensuring it runs with elevated privileges but can only operate on behalf of the currently authenticated user.
          
          ## Performance Impact:
          - Indexes: None
          - Triggers: None
          - Estimated Impact: Negligible. The function runs once per user upon their first sign-in.
          */
CREATE OR REPLACE FUNCTION public.create_user_profile_if_not_exists()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_meta jsonb;
  user_email text;
BEGIN
  -- Check if a profile already exists for the current user
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid()) THEN
    -- Get user's metadata from the auth.users table
    SELECT raw_user_meta_data, email INTO user_meta, user_email FROM auth.users WHERE id = auth.uid();

    -- Insert into profiles
    INSERT INTO public.profiles (id, full_name, email, role, mobile_number)
    VALUES (
      auth.uid(),
      user_meta->>'full_name',
      user_email,
      user_meta->>'role',
      user_meta->>'mobile_number'
    );

    -- If the user's role is 'Student', create a corresponding entry in the students table
    IF user_meta->>'role' = 'Student' THEN
      INSERT INTO public.students (id, full_name, email, contact)
      VALUES (
        auth.uid(),
        user_meta->>'full_name',
        user_email,
        user_meta->>'mobile_number'
      );
    END IF;
  END IF;
END;
$$;
