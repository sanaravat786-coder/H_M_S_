/*
# [Definitive Schema Reset]
This script completely resets the public schema by dropping all existing tables, types, functions, and triggers before recreating them from scratch. It is designed to resolve migration conflicts and establish a clean, consistent database state.

## Query Description: [This operation is destructive and will erase all data in the affected tables (students, rooms, fees, etc.). It is intended to be used during development to fix a corrupted or inconsistent schema. BACKUP YOUR DATA if you have any important information stored.]

## Metadata:
- Schema-Category: ["Dangerous"]
- Impact-Level: ["High"]
- Requires-Backup: [true]
- Reversible: [false]

## Structure Details:
- Drops and recreates all application tables: profiles, students, rooms, fees, visitors, maintenance_requests.
- Drops and recreates all custom types: user_role, room_type, room_status, etc.
- Drops and recreates the handle_new_user function and its associated trigger.
- Drops and recreates all Row Level Security policies.

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [Yes]
- Auth Requirements: [Resets all policies for Admin, Staff, and Student roles.]

## Performance Impact:
- Indexes: [Recreated]
- Triggers: [Recreated]
- Estimated Impact: [Minimal on an empty database. Will cause a brief write lock during execution.]
*/

-- Step 1: Drop dependent objects (trigger and function)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Step 2: Drop all tables with CASCADE to handle dependencies
DROP TABLE IF EXISTS public.maintenance_requests CASCADE;
DROP TABLE IF EXISTS public.visitors CASCADE;
DROP TABLE IF EXISTS public.fees CASCADE;
DROP TABLE IF EXISTS public.students CASCADE;
DROP TABLE IF EXISTS public.rooms CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- Step 3: Drop all custom types
DROP TYPE IF EXISTS public.user_role;
DROP TYPE IF EXISTS public.room_type;
DROP TYPE IF EXISTS public.room_status;
DROP TYPE IF EXISTS public.fee_status;
DROP TYPE IF EXISTS public.visitor_status;
DROP TYPE IF EXISTS public.maintenance_status;

-- Step 4: Recreate all custom types
CREATE TYPE public.user_role AS ENUM ('Admin', 'Staff', 'Student');
CREATE TYPE public.room_type AS ENUM ('Single', 'Double', 'Triple');
CREATE TYPE public.room_status AS ENUM ('Occupied', 'Vacant', 'Maintenance');
CREATE TYPE public.fee_status AS ENUM ('Paid', 'Due', 'Overdue');
CREATE TYPE public.visitor_status AS ENUM ('In', 'Out');
CREATE TYPE public.maintenance_status AS ENUM ('Pending', 'In Progress', 'Resolved');

-- Step 5: Recreate profiles table to link auth.users
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role user_role NOT NULL DEFAULT 'Student'
);
COMMENT ON TABLE public.profiles IS 'Stores public-facing user profile information.';

-- Step 6: Recreate application tables
CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    full_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    course TEXT,
    contact TEXT,
    room_id UUID, -- To be linked later
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.students IS 'Stores student information.';

CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number INT UNIQUE NOT NULL,
    type room_type NOT NULL,
    status room_status NOT NULL DEFAULT 'Vacant',
    occupants INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.rooms IS 'Manages hostel rooms and their status.';

-- Add foreign key from students to rooms after rooms table is created
ALTER TABLE public.students ADD CONSTRAINT fk_room FOREIGN KEY (room_id) REFERENCES public.rooms(id) ON DELETE SET NULL;

CREATE TABLE public.fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    due_date DATE NOT NULL,
    status fee_status NOT NULL DEFAULT 'Due',
    payment_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.fees IS 'Tracks student fee payments.';

CREATE TABLE public.visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_name TEXT NOT NULL,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_out_time TIMESTAMPTZ,
    status visitor_status NOT NULL DEFAULT 'In'
);
COMMENT ON TABLE public.visitors IS 'Logs visitor entries and exits.';

CREATE TABLE public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue TEXT NOT NULL,
    room_number INT NOT NULL,
    reported_by_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    status maintenance_status NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.maintenance_requests IS 'Tracks maintenance issues reported by students.';

-- Step 7: Recreate function and trigger for new user profiles
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    (new.raw_user_meta_data->>'role')::user_role
  );
  -- If the new user is a student, create an entry in the students table
  IF (new.raw_user_meta_data->>'role')::user_role = 'Student' THEN
    INSERT INTO public.students(profile_id, full_name, email)
    VALUES (new.id, new.raw_user_meta_data->>'full_name', new.email);
  END IF;
  RETURN new;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Step 8: Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;

-- Step 9: Recreate all RLS policies
-- Profiles
CREATE POLICY "Allow all access to own profile" ON public.profiles FOR ALL USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "Admins can manage all profiles" ON public.profiles FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Admin' );
CREATE POLICY "Allow read access to authenticated users" ON public.profiles FOR SELECT USING ( auth.role() = 'authenticated' );

-- Students
CREATE POLICY "Allow admin full access to students" ON public.students FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Admin' );
CREATE POLICY "Allow staff to view students" ON public.students FOR SELECT USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Staff' );
CREATE POLICY "Allow students to view their own record" ON public.students FOR SELECT USING ( profile_id = auth.uid() );

-- Rooms
CREATE POLICY "Allow authenticated users to view rooms" ON public.rooms FOR SELECT USING ( auth.role() = 'authenticated' );
CREATE POLICY "Allow admin full access to rooms" ON public.rooms FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Admin' );

-- Fees
CREATE POLICY "Allow admin full access to fees" ON public.fees FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Admin' );
CREATE POLICY "Allow students to see their own fees" ON public.fees FOR SELECT USING ( student_id IN (SELECT id FROM public.students WHERE profile_id = auth.uid()) );

-- Visitors
CREATE POLICY "Allow admin full access to visitors" ON public.visitors FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Admin' );
CREATE POLICY "Allow staff to manage visitors" ON public.visitors FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Staff' );
CREATE POLICY "Allow students to see their own visitors" ON public.visitors FOR SELECT USING ( student_id IN (SELECT id FROM public.students WHERE profile_id = auth.uid()) );

-- Maintenance Requests
CREATE POLICY "Allow admin full access to maintenance" ON public.maintenance_requests FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Admin' );
CREATE POLICY "Allow staff to manage maintenance" ON public.maintenance_requests FOR ALL USING ( (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'Staff' );
CREATE POLICY "Allow students to manage their own requests" ON public.maintenance_requests FOR ALL USING ( reported_by_id IN (SELECT id FROM public.students WHERE profile_id = auth.uid()) );
