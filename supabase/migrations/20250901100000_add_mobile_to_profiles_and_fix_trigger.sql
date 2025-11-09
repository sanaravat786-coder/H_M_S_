/*
# [Add Mobile Number to Profiles and Fix Trigger]
This migration adds a `mobile_number` column to the `public.profiles` table and updates the `handle_new_user` trigger function to correctly populate this new field upon user creation. This resolves the database error occurring during signup.

## Query Description: [This operation performs two main actions:
1. It adds a new `mobile_number` column (type TEXT) to the `public.profiles` table. This is a safe, structural change.
2. It replaces the existing `handle_new_user` function and its trigger to include logic for the new `mobile_number` field. This ensures new user signups correctly populate all profile fields.
This change is essential for the signup feature to work correctly.]

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Medium"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Table Modified: `public.profiles`
  - Column Added: `mobile_number` (Type: `TEXT`)
- Function Modified: `public.handle_new_user()`
- Trigger Modified: `on_auth_user_created` on `auth.users`

## Security Implications:
- RLS Status: Enabled (on `public.profiles`)
- Policy Changes: No. Existing RLS policies on `profiles` will now also apply to the `mobile_number` column.
- Auth Requirements: The function runs with `SECURITY DEFINER` privileges to insert into the `profiles` table.

## Performance Impact:
- Indexes: None added.
- Triggers: The `on_auth_user_created` trigger is replaced with an updated version. Impact on insert performance for `auth.users` is negligible.
- Estimated Impact: Low.
*/

-- Step 1: Add the mobile_number column to the profiles table.
-- This column will store the mobile number provided during signup.
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS mobile_number TEXT;

COMMENT ON COLUMN public.profiles.mobile_number IS 'Stores the user''s mobile phone number, provided at signup.';

-- Step 2: Update the trigger function to handle the new field.
-- We safely replace the function and trigger to ensure the logic is updated.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
-- Set a secure search_path:
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, "role", mobile_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data ->> 'full_name',
    NEW.email,
    NEW.raw_user_meta_data ->> 'role',
    NEW.raw_user_meta_data ->> 'mobile_number' -- This line is added to handle the new field
  );
  RETURN NEW;
END;
$$;

-- Ensure the trigger is correctly configured on the auth.users table.
CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

COMMENT ON FUNCTION public.handle_new_user() IS 'Trigger to create a profile for a new user, including full_name, role, and mobile_number from auth metadata.';
