/*
# [Fix Function Search Path]
This migration updates existing database functions to explicitly set the `search_path`. This is a security best practice that mitigates the risk of certain attack vectors by ensuring functions only search for objects within the intended schemas (in this case, `public`).

## Query Description:
This script uses `CREATE OR REPLACE FUNCTION` to redefine the `handle_new_user` and `update_room_occupants_on_student_change` functions. The only change is the addition of `SET search_path = public` to their definitions. This operation is non-destructive and will not affect any existing data. It simply hardens the security of your database logic.

## Metadata:
- Schema-Category: "Safe"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Modifies function: `public.handle_new_user`
- Modifies function: `public.update_room_occupants_on_student_change`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None
- Note: This change resolves the "Function Search Path Mutable" security advisory.

## Performance Impact:
- Indexes: None
- Triggers: Unchanged
- Estimated Impact: Negligible. This is a definition change with no runtime performance impact.
*/

-- Fix for handle_new_user function
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

-- Fix for update_room_occupants_on_student_change function
CREATE OR REPLACE FUNCTION public.update_room_occupants_on_student_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    -- On insert or update of a student's room (moving in)
    IF (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.room_id IS NOT NULL AND NEW.room_id <> OLD.room_id)) AND NEW.room_id IS NOT NULL THEN
        UPDATE rooms SET occupants = occupants + 1 WHERE id = NEW.room_id;
    END IF;

    -- On delete or update of a student's room (moving out)
    IF (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.room_id IS NOT NULL AND NEW.room_id <> OLD.room_id)) AND OLD.room_id IS NOT NULL THEN
        UPDATE rooms SET occupants = occupants - 1 WHERE id = OLD.room_id;
    END IF;

    RETURN NULL; -- Result is ignored since this is an AFTER trigger
END;
$$;
