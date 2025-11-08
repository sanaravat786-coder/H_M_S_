/*
# Initial Schema for Hostel Management System
This script sets up the required tables, relationships, and security policies for the application.

## Query Description: This script is foundational and will create new tables and security rules. It is safe to run on a new project but could conflict with existing tables if they have the same names. It is designed to work with the application's authentication flow.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Creates tables: profiles, students, rooms, fees, visitors, maintenance_requests.
- Creates a function and trigger to handle new user profiles.
- Enables Row Level Security on all new tables.
- Creates RLS policies for Admin, Student, and Staff roles.

## Security Implications:
- RLS Status: Enabled on all tables.
- Policy Changes: Yes, new policies are created.
- Auth Requirements: Policies are based on the `role` in the user's metadata.

## Performance Impact:
- Indexes: Primary keys and foreign keys are indexed by default.
- Triggers: One trigger is added to `auth.users`.
- Estimated Impact: Low on a new project.
*/

-- 1. PROFILES TABLE
-- Stores public user data and role.
CREATE TABLE public.profiles (
  id UUID NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  role TEXT
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 2. STUDENTS TABLE
CREATE TABLE public.students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  course TEXT,
  contact TEXT
);
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

-- 3. ROOMS TABLE
CREATE TABLE public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_number INT UNIQUE NOT NULL,
  type TEXT,
  status TEXT DEFAULT 'Vacant'
);
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

-- 4. FEES TABLE
CREATE TABLE public.fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
  amount NUMERIC(10, 2) NOT NULL,
  due_date DATE,
  status TEXT DEFAULT 'Due',
  payment_date DATE
);
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;

-- 5. VISITORS TABLE
CREATE TABLE public.visitors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_name TEXT NOT NULL,
  student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
  check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
  check_out_time TIMESTAMPTZ,
  status TEXT DEFAULT 'In'
);
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;

-- 6. MAINTENANCE REQUESTS TABLE
CREATE TABLE public.maintenance_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue TEXT NOT NULL,
  room_number INT NOT NULL,
  reported_by_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  date DATE NOT NULL DEFAULT now(),
  status TEXT DEFAULT 'Pending'
);
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;


-- 7. FUNCTION & TRIGGER to create a profile for new users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- 8. RLS POLICIES

-- Helper function to get user role
CREATE OR REPLACE FUNCTION get_user_role(user_id UUID)
RETURNS TEXT AS $$
DECLARE
  role TEXT;
BEGIN
  SELECT p.role INTO role FROM public.profiles p WHERE p.id = user_id;
  RETURN role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Policies for PROFILES table
CREATE POLICY "Users can view their own profile." ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Admins can view all profiles." ON public.profiles FOR SELECT USING (get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Users can update their own profile." ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Policies for STUDENTS table
CREATE POLICY "Admins can manage all students." ON public.students FOR ALL USING (get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Authenticated users can view students." ON public.students FOR SELECT USING (auth.role() = 'authenticated');

-- Policies for ROOMS table
CREATE POLICY "Admins can manage all rooms." ON public.rooms FOR ALL USING (get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Authenticated users can view rooms." ON public.rooms FOR SELECT USING (auth.role() = 'authenticated');

-- Policies for FEES table
CREATE POLICY "Admins can manage all fees." ON public.fees FOR ALL USING (get_user_role(auth.uid()) = 'Admin');
-- This policy needs a way to link student to auth.uid. Assuming students table has an email that matches auth.users email.
-- For simplicity, we'll allow students to see fees linked to their student record, which Admins create.
-- A more robust solution would link profiles.id to students.id.
CREATE POLICY "Students can view their own fees." ON public.fees FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM students s JOIN profiles p ON s.email = p.email WHERE p.id = auth.uid() AND s.id = fees.student_id
  )
);


-- Policies for VISITORS table
CREATE POLICY "Admins can manage all visitors." ON public.visitors FOR ALL USING (get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Staff can manage visitors." ON public.visitors FOR ALL USING (get_user_role(auth.uid()) = 'Staff');
CREATE POLICY "Students can view their own visitors." ON public.visitors FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM students s JOIN profiles p ON s.email = p.email WHERE p.id = auth.uid() AND s.id = visitors.student_id
  )
);

-- Policies for MAINTENANCE REQUESTS table
CREATE POLICY "Admins can manage all maintenance requests." ON public.maintenance_requests FOR ALL USING (get_user_role(auth.uid()) = 'Admin');
CREATE POLICY "Staff can view and update maintenance requests." ON public.maintenance_requests FOR SELECT USING (get_user_role(auth.uid()) = 'Staff');
CREATE POLICY "Staff can update maintenance requests." ON public.maintenance_requests FOR UPDATE USING (get_user_role(auth.uid()) = 'Staff');
CREATE POLICY "Students can create and view their own requests." ON public.maintenance_requests FOR ALL USING (reported_by_id = auth.uid());
