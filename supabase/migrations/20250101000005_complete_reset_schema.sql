/*
# [Complete Schema Reset and Rebuild]
This script will completely reset and rebuild the database schema for the Hostel Management System. It first drops all existing tables, types, and functions to ensure a clean slate, then recreates the entire structure from scratch, including tables, relationships, user roles, and security policies.

## Query Description: [This is a destructive operation that will remove all existing data in the affected tables (students, rooms, fees, etc.). It is designed to fix inconsistencies from previous failed migrations and establish a clean, correct database schema. It is highly recommended to back up any critical data before applying this migration, although it's assumed you are in a development phase where data loss is acceptable.]

## Metadata:
- Schema-Category: ["Dangerous", "Structural"]
- Impact-Level: ["High"]
- Requires-Backup: [true]
- Reversible: [false]

## Structure Details:
- Drops all existing application tables: maintenance_requests, visitors, fees, rooms, students, profiles.
- Drops existing types and functions: user_role, handle_new_user.
- Re-creates all tables with correct columns, primary keys, and foreign keys.
- Re-creates the user_role ENUM type.
- Re-creates the function and trigger to automatically create user profiles.
- Re-enables Row Level Security (RLS) on all tables.
- Creates comprehensive RLS policies for 'Admin', 'Staff', and 'Student' roles.

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [Yes]
- Auth Requirements: [Policies are based on JWT claims for user_id and role.]

## Performance Impact:
- Indexes: [Primary and Foreign Key indexes will be recreated.]
- Triggers: [A trigger for new user profile creation will be added.]
- Estimated Impact: [Negligible on a new database. This operation is for setup and correction, not for a live production environment.]
*/

-- =============================================
-- RESET SCHEMA: Drop existing objects if they exist
-- =============================================
-- Drop tables in reverse order of dependency or use CASCADE
DROP TABLE IF EXISTS public.maintenance_requests CASCADE;
DROP TABLE IF EXISTS public.visitors CASCADE;
DROP TABLE IF EXISTS public.fees CASCADE;
DROP TABLE IF EXISTS public.rooms CASCADE;
DROP TABLE IF EXISTS public.students CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- Drop functions and types
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP TYPE IF EXISTS public.user_role;


-- =============================================
-- REBUILD SCHEMA: Create objects from scratch
-- =============================================

-- 1. Create custom ENUM type for user roles
CREATE TYPE public.user_role AS ENUM ('Admin', 'Staff', 'Student');

-- 2. Create profiles table to store user data
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role user_role NOT NULL DEFAULT 'Student'
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 3. Create students table
CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    full_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    course TEXT,
    contact TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

-- 4. Create rooms table
CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number INT UNIQUE NOT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Vacant',
    occupants INT NOT NULL DEFAULT 0,
    student_id UUID REFERENCES public.students(id) ON DELETE SET NULL
);
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

-- 5. Create fees table
CREATE TABLE public.fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    due_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'Due',
    payment_date DATE,
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;

-- 6. Create visitors table
CREATE TABLE public.visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_name TEXT NOT NULL,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_out_time TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'In'
);
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;

-- 7. Create maintenance_requests table
CREATE TABLE public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue TEXT NOT NULL,
    room_number INT,
    reported_by_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;


-- =============================================
-- TRIGGERS & FUNCTIONS
-- =============================================

-- Function to create a profile for a new user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    (new.raw_user_meta_data->>'role')::public.user_role
  );
  -- If the new user is a student, also create an entry in the students table
  IF (new.raw_user_meta_data->>'role')::public.user_role = 'Student' THEN
    INSERT INTO public.students (profile_id, full_name, email)
    VALUES (new.id, new.raw_user_meta_data->>'full_name', new.email);
  END IF;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function when a new user is created in auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- =============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================

-- Helper function to get user role from profiles table
CREATE OR REPLACE FUNCTION public.get_user_role(user_id UUID)
RETURNS public.user_role AS $$
DECLARE
  user_role public.user_role;
BEGIN
  SELECT role INTO user_role FROM public.profiles WHERE id = user_id;
  RETURN user_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Profiles Table Policies
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can manage all profiles" ON public.profiles FOR ALL USING (public.get_user_role(auth.uid()) = 'Admin');

-- Students Table Policies
CREATE POLICY "Admins can manage all students" ON public.students FOR ALL USING (public.get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Staff can view all students" ON public.students FOR SELECT USING (public.get_user_role(auth.uid()) IN ('Admin', 'Staff'));
CREATE POLICY "Students can view their own record" ON public.students FOR SELECT USING (profile_id = auth.uid());

-- Rooms Table Policies
CREATE POLICY "Admins can manage all rooms" ON public.rooms FOR ALL USING (public.get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Authenticated users can view all rooms" ON public.rooms FOR SELECT USING (auth.role() = 'authenticated');

-- Fees Table Policies
CREATE POLICY "Admins can manage all fees" ON public.fees FOR ALL USING (public.get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Staff can view all fees" ON public.fees FOR SELECT USING (public.get_user_role(auth.uid()) IN ('Admin', 'Staff'));
CREATE POLICY "Students can view their own fees" ON public.fees FOR SELECT USING (student_id IN (SELECT id FROM public.students WHERE profile_id = auth.uid()));

-- Visitors Table Policies
CREATE POLICY "Admins and Staff can manage all visitors" ON public.visitors FOR ALL USING (public.get_user_role(auth.uid()) IN ('Admin', 'Staff'));
CREATE POLICY "Students can view their own visitors" ON public.visitors FOR SELECT USING (student_id IN (SELECT id FROM public.students WHERE profile_id = auth.uid()));

-- Maintenance Requests Table Policies
CREATE POLICY "Admins and Staff can manage all requests" ON public.maintenance_requests FOR ALL USING (public.get_user_role(auth.uid()) IN ('Admin', 'Staff'));
CREATE POLICY "Students can manage their own requests" ON public.maintenance_requests FOR ALL USING (reported_by_id IN (SELECT id FROM public.students WHERE profile_id = auth.uid()));
