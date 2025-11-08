/*
          # [Feature] Add Mobile Number to User Profiles
          This migration adds a `mobile_number` field to the user profiles and updates the user creation logic to capture it during signup.

          ## Query Description:
          - **ALTER TABLE**: Adds a new `mobile_number` column of type `TEXT` to the `public.profiles` table. This is a non-destructive operation.
          - **CREATE OR REPLACE FUNCTION**: Updates the `handle_new_user` function. This function is triggered when a new user signs up. The update adds logic to read the `mobile_number` from the user's metadata and insert it into the new column in the `profiles` table.

          ## Metadata:
          - Schema-Category: "Structural"
          - Impact-Level: "Low"
          - Requires-Backup: false
          - Reversible: true (The column can be dropped, and the function can be reverted)

          ## Structure Details:
          - **Table Modified**: `public.profiles`
            - **Column Added**: `mobile_number` (TEXT)
          - **Function Modified**: `public.handle_new_user()`

          ## Security Implications:
          - RLS Status: Unchanged. Existing RLS policies on `profiles` will apply.
          - Policy Changes: No.
          - Auth Requirements: The function is `SECURITY DEFINER`.

          ## Performance Impact:
          - Indexes: None added.
          - Triggers: The `on_auth_user_created` trigger remains, but will now execute the updated function logic.
          - Estimated Impact: Negligible.
          */

ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS mobile_number TEXT;

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
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'role',
    new.raw_user_meta_data->>'mobile_number'
  );
  RETURN new;
END;
$$;
