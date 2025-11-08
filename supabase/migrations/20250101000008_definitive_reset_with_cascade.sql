/*
          # [Definitive Schema Reset with Cascade]
          This script performs a complete reset of the public schema to resolve dependency conflicts from previous failed migrations. It will drop all existing tables, types, functions, and policies before rebuilding them from a clean slate.

          ## Query Description: [This is a destructive operation that will remove all data in your public tables (students, rooms, etc.). This is necessary to fix the underlying schema conflicts and ensure a stable database. It is recommended to run this in a development environment or after backing up any critical data.]
          
          ## Metadata:
          - Schema-Category: "Dangerous"
          - Impact-Level: "High"
          - Requires-Backup: true
          - Reversible: false
          
          ## Structure Details:
          - Drops all triggers, functions, tables, and types in the public schema.
          - Recreates the entire schema including: profiles, students, rooms, fees, visitors, maintenance_requests.
          - Recreates helper functions, triggers for user profile creation, and all Row-Level Security (RLS) policies.
          
          ## Security Implications:
          - RLS Status: Enabled on all tables.
          - Policy Changes: Yes, all policies are dropped and recreated correctly.
          - Auth Requirements: Policies are based on 'Admin', 'Staff', and 'Student' roles.
          
          ## Performance Impact:
          - Indexes: All indexes are dropped and recreated.
          - Triggers: All triggers are dropped and recreated.
          - Estimated Impact: "Brief downtime during migration, followed by normal performance."
          */

-- Step 1: Drop dependent objects using CASCADE to resolve conflicts.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP FUNCTION IF EXISTS public.get_user_role() CASCADE;

-- Step 2: Drop all tables and types to ensure a clean slate.
DROP TABLE IF EXISTS public.maintenance_requests CASCADE;
DROP TABLE IF EXISTS public.visitors CASCADE;
DROP TABLE IF EXISTS public.fees CASCADE;
DROP TABLE IF EXISTS public.room_assignments CASCADE;
DROP TABLE IF EXISTS public.rooms CASCADE;
DROP TABLE IF EXISTS public.students CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

DROP TYPE IF EXISTS public.role;
DROP TYPE IF EXISTS public.room_type;
DROP TYPE IF EXISTS public.room_status;
DROP TYPE IF EXISTS public.fee_status;
DROP TYPE IF EXISTS public.maintenance_status;
DROP TYPE IF EXISTS public.visitor_status;

-- Step 3: Recreate all types
CREATE TYPE public.role AS ENUM ('Admin', 'Staff', 'Student');
CREATE TYPE public.room_type AS ENUM ('Single', 'Double', 'Triple');
CREATE TYPE public.room_status AS ENUM ('Vacant', 'Occupied', 'Maintenance');
CREATE TYPE public.fee_status AS ENUM ('Paid', 'Due', 'Overdue');
CREATE TYPE public.maintenance_status AS ENUM ('Pending', 'In Progress', 'Resolved');
CREATE TYPE public.visitor_status AS ENUM ('In', 'Out');

-- Step 4: Recreate tables
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role public.role NOT NULL DEFAULT 'Student'
);

CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    course TEXT,
    contact TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number INT UNIQUE NOT NULL,
    type public.room_type NOT NULL,
    status public.room_status NOT NULL DEFAULT 'Vacant',
    occupants INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    due_date DATE NOT NULL,
    status public.fee_status NOT NULL DEFAULT 'Due',
    payment_date DATE,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_name TEXT NOT NULL,
    student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_out_time TIMESTAMPTZ,
    status public.visitor_status NOT NULL DEFAULT 'In',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue TEXT NOT NULL,
    room_number INT,
    reported_by_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
    status public.maintenance_status NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Step 5: Recreate functions and triggers
CREATE OR REPLACE FUNCTION public.get_user_role(user_id UUID)
RETURNS public.role
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT role FROM public.profiles WHERE id = user_id;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, role)
    VALUES (new.id, new.raw_user_meta_data->>'full_name', (new.raw_user_meta_data->>'role')::public.role);
    RETURN new;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 6: Re-enable RLS and create policies
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;

-- Policies for 'profiles'
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can manage all profiles" ON public.profiles FOR ALL USING (get_user_role(auth.uid()) = 'Admin');

-- Policies for 'students'
CREATE POLICY "All authenticated users can view students" ON public.students FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins can manage students" ON public.students FOR ALL USING (get_user_role(auth.uid()) = 'Admin');

-- Policies for 'rooms'
CREATE POLICY "All authenticated users can view rooms" ON public.rooms FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins can manage rooms" ON public.rooms FOR ALL USING (get_user_role(auth.uid()) = 'Admin');

-- Policies for 'fees'
CREATE POLICY "Admins and Staff can view all fees" ON public.fees FOR SELECT USING (get_user_role(auth.uid()) IN ('Admin', 'Staff'));
CREATE POLICY "Students can view their own fees" ON public.fees FOR SELECT USING (EXISTS (SELECT 1 FROM students WHERE students.email = (SELECT email FROM auth.users WHERE id = auth.uid()) AND students.id = fees.student_id));
CREATE POLICY "Admins can manage fees" ON public.fees FOR ALL USING (get_user_role(auth.uid()) = 'Admin');

-- Policies for 'visitors'
CREATE POLICY "All authenticated users can view visitors" ON public.visitors FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins and Staff can manage visitors" ON public.visitors FOR ALL USING (get_user_role(auth.uid()) IN ('Admin', 'Staff'));

-- Policies for 'maintenance_requests'
CREATE POLICY "Authenticated users can view requests" ON public.maintenance_requests FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Students can create their own requests" ON public.maintenance_requests FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM students WHERE students.email = (SELECT email FROM auth.users WHERE id = auth.uid()) AND students.id = maintenance_requests.reported_by_id));
CREATE POLICY "Admins and Staff can manage requests" ON public.maintenance_requests FOR ALL USING (get_user_role(auth.uid()) IN ('Admin', 'Staff'));
