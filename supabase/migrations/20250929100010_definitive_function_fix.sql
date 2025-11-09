-- This migration script recreates all custom functions to ensure correct syntax and to apply security hardening by setting a fixed search_path.
-- This resolves the syntax error from the previous migration and addresses the "Function Search Path Mutable" security advisory.

/*
# [Function: handle_new_user]
[Trigger function to create a public.profiles record when a new user signs up in auth.users.]

## Query Description: [This function automatically populates the profiles table with metadata provided during sign-up. It ensures user data is consistent between the authentication and public schemas.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Medium"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Writes to: public.profiles
- Reads from: NEW (auth.users record)

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER]
- Policy Changes: [No]
- Auth Requirements: [Fires automatically on user creation.]

## Performance Impact:
- Indexes: [Relies on primary key of public.profiles.]
- Triggers: [This IS a trigger function.]
- Estimated Impact: [Low, runs once per user sign-up.]
*/
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, role, contact, course, joining_date, room_number)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    NEW.email,
    NEW.raw_user_meta_data->>'role',
    NEW.raw_user_meta_data->>'mobile_number',
    NEW.raw_user_meta_data->>'course',
    (NEW.raw_user_meta_data->>'joining_date')::date,
    NEW.raw_user_meta_data->>'room_number'
  );
  RETURN NEW;
END;
$$;


/*
# [Function: is_admin]
[Helper function to check if the currently authenticated user has the 'Admin' role.]

## Query Description: [A boolean check against the profiles table. Used for RLS policies to grant administrative privileges.]

## Metadata:
- Schema-Category: ["Security"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Reads from: public.profiles

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER to read roles.]
- Policy Changes: [No]
- Auth Requirements: [Requires an authenticated user session.]

## Performance Impact:
- Indexes: [Uses primary key on profiles.id.]
- Triggers: [No]
- Estimated Impact: [Low, fast lookup.]
*/
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF auth.role() = 'authenticated' THEN
        RETURN EXISTS (
            SELECT 1
            FROM public.profiles
            WHERE id = auth.uid() AND role = 'Admin'
        );
    END IF;
    RETURN FALSE;
END;
$$;


/*
# [Function: get_unallocated_students]
[Retrieves a list of all students who are not currently assigned to a room.]

## Query Description: [Selects students from the profiles table who do not have an active record in the room_allocations table.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Reads from: public.profiles, public.room_allocations

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER.]
- Policy Changes: [No]
- Auth Requirements: [Should be called by an admin/staff role.]

## Performance Impact:
- Indexes: [Benefits from indexes on room_allocations.student_id and room_allocations.is_active.]
- Triggers: [No]
- Estimated Impact: [Medium, depends on table sizes.]
*/
CREATE OR REPLACE FUNCTION public.get_unallocated_students()
RETURNS TABLE(id uuid, full_name text, email text, course text, contact text) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    RETURN QUERY 
    SELECT
        p.id,
        p.full_name,
        p.email,
        p.course,
        p.contact
    FROM
        public.profiles p
    WHERE
        p.role = 'Student' AND
        p.id NOT IN (
            SELECT ra.student_id
            FROM public.room_allocations ra
            WHERE ra.is_active = TRUE
        )
    ORDER BY
        p.full_name;
END;
$$;


/*
# [Function: allocate_room]
[Assigns a student to a room, creating a new allocation record.]

## Query Description: [Deactivates any previous allocation for the student and inserts a new active allocation. Triggers will update room occupancy status.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Medium"]
- Requires-Backup: [false]
- Reversible: [false] -- Deactivates old record.

## Structure Details:
- Writes to: public.room_allocations

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER.]
- Policy Changes: [No]
- Auth Requirements: [Admin/staff only.]

## Performance Impact:
- Indexes: [Uses indexes on room_allocations table.]
- Triggers: [Yes, fires trigger to update room status.]
- Estimated Impact: [Low.]
*/
CREATE OR REPLACE FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    UPDATE public.room_allocations
    SET is_active = FALSE, end_date = NOW()
    WHERE student_id = p_student_id AND is_active = TRUE;

    INSERT INTO public.room_allocations (student_id, room_id, start_date, is_active)
    VALUES (p_student_id, p_room_id, NOW(), TRUE);
END;
$$;


/*
# [Function: update_room_occupancy]
[Recalculates and updates the status of a room based on its number of active occupants.]

## Query Description: [Counts active allocations for a given room and sets its status to 'Occupied' or 'Vacant'.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Medium"]
- Requires-Backup: [false]
- Reversible: [false]

## Structure Details:
- Writes to: public.rooms
- Reads from: public.room_allocations

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER.]
- Policy Changes: [No]
- Auth Requirements: [Admin/staff only.]

## Performance Impact:
- Indexes: [Uses index on room_allocations.room_id.]
- Triggers: [No]
- Estimated Impact: [Low.]
*/
CREATE OR REPLACE FUNCTION public.update_room_occupancy(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_occupant_count int;
BEGIN
    SELECT count(*)
    INTO v_occupant_count
    FROM public.room_allocations
    WHERE room_id = p_room_id AND is_active = true;

    IF v_occupant_count > 0 THEN
        UPDATE public.rooms
        SET status = 'Occupied'
        WHERE id = p_room_id;
    ELSE
        UPDATE public.rooms
        SET status = 'Vacant'
        WHERE id = p_room_id AND status != 'Maintenance';
    END IF;
END;
$$;


/*
# [Function: universal_search]
[Performs a global search across students and rooms.]

## Query Description: [Searches for a term in student names and room numbers, returning a JSON object with results.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Reads from: public.profiles, public.rooms

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER.]
- Policy Changes: [No]
- Auth Requirements: [Authenticated user.]

## Performance Impact:
- Indexes: [Benefits from text search indexes if available.]
- Triggers: [No]
- Estimated Impact: [Medium, depends on search term and table size.]
*/
CREATE OR REPLACE FUNCTION public.universal_search(p_search_term text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_search_term text := '%' || p_search_term || '%';
BEGIN
    RETURN json_build_object(
        'students', (
            SELECT json_agg(
                json_build_object(
                    'id', p.id,
                    'label', p.full_name,
                    'path', '/students/' || p.id
                )
            )
            FROM public.profiles p
            WHERE p.role = 'Student' AND p.full_name ILIKE v_search_term
        ),
        'rooms', (
            SELECT json_agg(
                json_build_object(
                    'id', r.id,
                    'label', 'Room ' || r.room_number,
                    'path', '/rooms/' || r.id
                )
            )
            FROM public.rooms r
            WHERE r.room_number ILIKE v_search_term
        )
    );
END;
$$;


/*
# [Function: get_or_create_session]
[Finds an attendance session for a given date and type, or creates one if it doesn't exist.]

## Query Description: [Ensures an attendance session record exists before marking attendance. Returns the session ID.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [false] -- Can create new records.

## Structure Details:
- Writes to: public.attendance_sessions
- Reads from: public.attendance_sessions

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER.]
- Policy Changes: [No]
- Auth Requirements: [Authenticated user.]

## Performance Impact:
- Indexes: [Uses index on attendance_sessions(date, session_type).]
- Triggers: [No]
- Estimated Impact: [Low.]
*/
CREATE OR REPLACE FUNCTION public.get_or_create_session(p_date date, p_session_type attendance_session_type)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_session_id uuid;
BEGIN
    SELECT id INTO v_session_id
    FROM public.attendance_sessions
    WHERE date = p_date AND session_type = p_session_type;

    IF v_session_id IS NULL THEN
        INSERT INTO public.attendance_sessions (date, session_type)
        VALUES (p_date, p_session_type)
        RETURNING id INTO v_session_id;
    END IF;

    RETURN v_session_id;
END;
$$;


/*
# [Function: process_fee_payment]
[Processes a simulated fee payment, updating the fee status and creating a payment record.]

## Query Description: [Marks a fee as 'Paid' and logs the transaction in the payments table.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["High"]
- Requires-Backup: [true]
- Reversible: [false]

## Structure Details:
- Writes to: public.fees, public.payments
- Reads from: public.fees

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER.]
- Policy Changes: [No]
- Auth Requirements: [Student paying their own fee.]

## Performance Impact:
- Indexes: [Uses primary key on fees.id.]
- Triggers: [No]
- Estimated Impact: [Low.]
*/
CREATE OR REPLACE FUNCTION public.process_fee_payment(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_fee record;
BEGIN
    SELECT * INTO v_fee
    FROM public.fees
    WHERE id = p_fee_id FOR UPDATE;

    IF v_fee.status = 'Paid' THEN
        RAISE EXCEPTION 'Fee is already paid.';
    END IF;

    INSERT INTO public.payments (fee_id, amount, paid_on, payment_method)
    VALUES (p_fee_id, v_fee.amount, NOW(), 'online_simulated');

    UPDATE public.fees
    SET status = 'Paid', payment_date = NOW()
    WHERE id = p_fee_id;
END;
$$;


/*
# [Function: get_user_profile_details]
[This function retrieves a comprehensive user profile, including room allocation details.]

## Query Description: [This is a read-only function and does not modify any data. It joins profiles with room allocations to provide a complete view.]

## Metadata:
- Schema-Category: ["Data"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [true]

## Structure Details:
- Reads from: public.profiles, public.room_allocations, public.rooms

## Security Implications:
- RLS Status: [Bypassed with SECURITY DEFINER]
- Policy Changes: [No]
- Auth Requirements: [Can be called with a specific user ID.]

## Performance Impact:
- Indexes: [Relies on primary key indexes on id columns for joins.]
- Triggers: [No]
- Estimated Impact: [Low, as it queries based on a primary key.]
*/
CREATE OR REPLACE FUNCTION public.get_user_profile_details(p_user_id uuid)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_profile json;
BEGIN
    SELECT
        json_build_object(
            'id', p.id,
            'full_name', p.full_name,
            'email', p.email,
            'contact', p.contact,
            'course', p.course,
            'role', p.role,
            'created_at', p.created_at,
            'joining_date', p.joining_date,
            'room_number', r.room_number
        )
    INTO v_profile
    FROM
        public.profiles p
    LEFT JOIN
        public.room_allocations ra ON p.id = ra.student_id AND ra.is_active = TRUE
    LEFT JOIN
        public.rooms r ON ra.room_id = r.id
    WHERE
        p.id = p_user_id;

    RETURN v_profile;
END;
$$;
