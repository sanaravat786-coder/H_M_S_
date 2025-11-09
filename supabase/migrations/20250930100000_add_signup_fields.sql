/*
          # [Operation Name]
          Add joining_date and room_number to profiles

          ## Query Description: This migration adds a `joining_date` and `room_number` column to the `profiles` table to store additional information during user sign-up. It also updates the `handle_new_user` function, which is triggered on new user creation, to correctly populate these new fields from the metadata provided during the sign-up process. This change is non-destructive and adds new capabilities.
          
          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true
          
          ## Structure Details:
          - Tables Modified: `public.profiles`
          - Columns Added: `joining_date` (DATE), `room_number` (TEXT)
          - Functions Modified: `public.handle_new_user()`
          
          ## Security Implications:
          - RLS Status: Unchanged
          - Policy Changes: No
          - Auth Requirements: This function is called by a trigger on the `auth.users` table.
          
          ## Performance Impact:
          - Indexes: None
          - Triggers: The `on_auth_user_created` trigger's underlying function is updated. The performance impact is negligible.
          - Estimated Impact: Low.
          */

-- Step 1: Add the new columns to the profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS joining_date DATE,
ADD COLUMN IF NOT EXISTS room_number TEXT;

-- Step 2: Recreate the handle_new_user function to include the new fields
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, contact, course, joining_date, room_number)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number',
    new.raw_user_meta_data->>'course',
    (new.raw_user_meta_data->>'joining_date')::date,
    new.raw_user_meta_data->>'room_number'
  );
  RETURN new;
END;
$$;
