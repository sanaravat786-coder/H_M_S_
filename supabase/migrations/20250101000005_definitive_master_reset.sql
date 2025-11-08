-- =================================================================
-- == Full Database Reset and Schema Creation
-- == This script will drop all existing custom objects and
-- == rebuild the entire schema from a clean slate.
-- ==
-- == WARNING: This is a destructive operation and will
-- == remove all data in the public schema.
-- =================================================================

-- Step 1: Drop existing objects in reverse order of dependency.
-- Using CASCADE to handle complex dependencies and avoid errors.

-- Drop the trigger on auth.users first as it depends on the handle_new_user function.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop functions. CASCADE will handle dependent policies.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.get_user_role() CASCADE;

-- Drop tables. CASCADE will handle foreign keys and other dependencies.
DROP TABLE IF EXISTS public.maintenance_requests;
DROP TABLE IF EXISTS public.visitors;
DROP TABLE IF EXISTS public.fees;
DROP TABLE IF EXISTS public.rooms;
DROP TABLE IF EXISTS public.students;
DROP TABLE IF EXISTS public.profiles;

-- Drop custom types.
DROP TYPE IF EXISTS public.user_role;
DROP TYPE IF EXISTS public.room_type;
DROP TYPE IF EXISTS public.room_status;
DROP TYPE IF EXISTS public.fee_status;
DROP TYPE IF EXISTS public.visitor_status;
DROP TYPE IF EXISTS public.maintenance_status;

-- Step 2: Recreate the schema from a clean slate.

-- Create custom ENUM types for status fields
CREATE TYPE public.user_role AS ENUM ('Admin', 'Student', 'Staff');
CREATE TYPE public.room_type AS ENUM ('Single', 'Double', 'Triple');
CREATE TYPE public.room_status AS ENUM ('Vacant', 'Occupied', 'Maintenance');
CREATE TYPE public.fee_status AS ENUM ('Paid', 'Due', 'Overdue');
CREATE TYPE public.visitor_status AS ENUM ('In', 'Out');
CREATE TYPE public.maintenance_status AS ENUM ('Pending', 'In Progress', 'Resolved');

-- Create profiles table to store public user data
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  role user_role NOT NULL DEFAULT 'Student'
);
COMMENT ON TABLE public.profiles IS 'Stores public profile information for each user.';

-- Create students table
CREATE TABLE public.students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  course TEXT,
  contact TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.students IS 'Stores information about each student in the hostel.';

-- Create rooms table
CREATE TABLE public.rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_number INT NOT NULL UNIQUE,
  type room_type NOT NULL,
  status room_status NOT NULL DEFAULT 'Vacant',
  occupants INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.rooms IS 'Manages hostel rooms, their types, and occupancy status.';

-- Create fees table
CREATE TABLE public.fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  amount DECIMAL(10, 2) NOT NULL,
  due_date DATE NOT NULL,
  status fee_status NOT NULL DEFAULT 'Due',
  payment_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.fees IS 'Tracks fee payments for each student.';

-- Create visitors table
CREATE TABLE public.visitors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  visitor_name TEXT NOT NULL,
  student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
  check_out_time TIMESTAMPTZ,
  status visitor_status NOT NULL DEFAULT 'In',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.visitors IS 'Logs visitor entries and exits.';

-- Create maintenance_requests table
CREATE TABLE public.maintenance_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  issue TEXT NOT NULL,
  room_number INT NOT NULL,
  reported_by_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  status maintenance_status NOT NULL DEFAULT 'Pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.maintenance_requests IS 'Tracks maintenance issues reported by students.';

-- Step 3: Set up database functions and triggers.

-- Function to get user role securely from auth metadata
-- This version avoids recursion by not querying the profiles table.
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS public.user_role AS $$
BEGIN
  RETURN (auth.jwt()->>'user_metadata')::jsonb->>'role';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Set a secure search path for the function to address security warnings.
ALTER FUNCTION public.get_user_role() SET search_path = public;


-- Function to create a new profile when a user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    (new.raw_user_meta_data->>'role')::public.user_role
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Set a secure search path for the function.
ALTER FUNCTION public.handle_new_user() SET search_path = public;

-- Trigger to call handle_new_user on new user creation in auth.users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Step 4: Set up Row Level Security (RLS) policies.

-- Enable RLS for all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;

-- RLS Policies for 'profiles'
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Admins can manage all profiles" ON public.profiles FOR ALL USING (public.get_user_role() = 'Admin');

-- RLS Policies for 'students'
CREATE POLICY "Admins and Staff can view all students" ON public.students FOR SELECT USING (public.get_user_role() IN ('Admin', 'Staff'));
CREATE POLICY "Admins can manage students" ON public.students FOR ALL USING (public.get_user_role() = 'Admin');

-- RLS Policies for 'rooms'
CREATE POLICY "Authenticated users can view rooms" ON public.rooms FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins can manage rooms" ON public.rooms FOR ALL USING (public.get_user_role() = 'Admin');

-- RLS Policies for 'fees'
CREATE POLICY "Admins and Staff can view all fees" ON public.fees FOR SELECT USING (public.get_user_role() IN ('Admin', 'Staff'));
CREATE POLICY "Students can view their own fees" ON public.fees FOR SELECT USING (EXISTS (SELECT 1 FROM students WHERE students.id = fees.student_id AND students.email = auth.email()));
CREATE POLICY "Admins can manage fees" ON public.fees FOR ALL USING (public.get_user_role() = 'Admin');

-- RLS Policies for 'visitors'
CREATE POLICY "Admins and Staff can view all visitors" ON public.visitors FOR SELECT USING (public.get_user_role() IN ('Admin', 'Staff'));
CREATE POLICY "Students can view their own visitors" ON public.visitors FOR SELECT USING (EXISTS (SELECT 1 FROM students WHERE students.id = visitors.student_id AND students.email = auth.email()));
CREATE POLICY "Admins can manage visitors" ON public.visitors FOR ALL USING (public.get_user_role() = 'Admin');

-- RLS Policies for 'maintenance_requests'
CREATE POLICY "Authenticated users can view all requests" ON public.maintenance_requests FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Students can create their own requests" ON public.maintenance_requests FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM students WHERE students.id = maintenance_requests.reported_by_id AND students.email = auth.email()));
CREATE POLICY "Admins and Staff can manage requests" ON public.maintenance_requests FOR ALL USING (public.get_user_role() IN ('Admin', 'Staff'));
