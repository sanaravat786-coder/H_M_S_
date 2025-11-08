/*
          # [Operation Name]
          Create Complete H_M_S Database Schema

          ## Query Description: [This script sets up the entire database schema for the Hostel Management System. It creates all tables, defines relationships with foreign keys, establishes enum types for status fields, creates a user profiles table with an automatic trigger, and implements comprehensive Row-Level Security (RLS) policies for all tables. This foundational schema ensures data integrity and security across the application.]
          
          ## Metadata:
          - Schema-Category: ["Structural"]
          - Impact-Level: ["High"]
          - Requires-Backup: [true]
          - Reversible: [false]
          
          ## Structure Details:
          - Tables Created: profiles, rooms, students, fees, visitors, maintenance_requests
          - Functions Created: handle_new_user, get_user_role
          - Triggers Created: on_auth_user_created
          - RLS Policies: Enabled and defined for all tables.
          
          ## Security Implications:
          - RLS Status: [Enabled]
          - Policy Changes: [Yes]
          - Auth Requirements: [Relies on Supabase Auth roles (Admin, Staff, Student) stored in user metadata.]
          
          ## Performance Impact:
          - Indexes: [Added]
          - Triggers: [Added]
          - Estimated Impact: [Low performance impact on an empty database. Indexes are created on foreign keys to optimize query performance.]
          */

-- 1. Custom Types for Statuses (optional but good for data integrity)
CREATE TYPE public.room_status AS ENUM ('Occupied', 'Vacant', 'Maintenance');
CREATE TYPE public.fee_status AS ENUM ('Paid', 'Due', 'Overdue');
CREATE TYPE public.visitor_status AS ENUM ('In', 'Out');
CREATE TYPE public.maintenance_status AS ENUM ('Pending', 'In Progress', 'Resolved');
CREATE TYPE public.user_role AS ENUM ('Admin', 'Student', 'Staff');

-- 2. Rooms Table
CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number INT UNIQUE NOT NULL,
    type TEXT NOT NULL,
    status public.room_status NOT NULL DEFAULT 'Vacant',
    occupants INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.rooms IS 'Stores information about each hostel room.';

-- 3. Students Table
CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    course TEXT,
    contact TEXT,
    room_id UUID REFERENCES public.rooms(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.students IS 'Stores student information.';

-- 4. Fees Table
CREATE TABLE public.fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    due_date DATE NOT NULL,
    status public.fee_status NOT NULL DEFAULT 'Due',
    payment_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.fees IS 'Tracks fee payments for students.';

-- 5. Visitors Table
CREATE TABLE public.visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_name TEXT NOT NULL,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_out_time TIMESTAMPTZ,
    status public.visitor_status NOT NULL DEFAULT 'In'
);
COMMENT ON TABLE public.visitors IS 'Logs visitor entries and exits.';

-- 6. Maintenance Requests Table
CREATE TABLE public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue TEXT NOT NULL,
    room_number INT NOT NULL,
    reported_by_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    status public.maintenance_status NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.maintenance_requests IS 'Tracks maintenance issues reported by students.';

-- 7. Profiles Table for linking auth.users
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role public.user_role
);
COMMENT ON TABLE public.profiles IS 'Stores public user data and roles.';

-- 8. Trigger to create a profile for new users
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    (new.raw_user_meta_data->>'role')::public.user_role
  );
  
  -- If the user is a student, create a corresponding entry in the students table
  IF (new.raw_user_meta_data->>'role') = 'Student' THEN
    INSERT INTO public.students (user_id, full_name, email)
    VALUES (new.id, new.raw_user_meta_data->>'full_name', new.email);
  END IF;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 9. Helper function to get user role
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS public.user_role AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE;

-- 10. RLS Policies
-- Enable RLS for all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;

-- Profiles Policies
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT USING (id = auth.uid());
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT USING (public.get_user_role() = 'Admin');

-- Students Policies
CREATE POLICY "Admins can manage all students" ON public.students FOR ALL USING (public.get_user_role() = 'Admin');
CREATE POLICY "Staff can view students" ON public.students FOR SELECT USING (public.get_user_role() = 'Staff');
CREATE POLICY "Students can view their own record" ON public.students FOR SELECT USING (user_id = auth.uid());

-- Rooms Policies
CREATE POLICY "Admins can manage all rooms" ON public.rooms FOR ALL USING (public.get_user_role() = 'Admin');
CREATE POLICY "Authenticated users can view rooms" ON public.rooms FOR SELECT USING (auth.role() = 'authenticated');

-- Fees Policies
CREATE POLICY "Admins can manage all fees" ON public.fees FOR ALL USING (public.get_user_role() = 'Admin');
CREATE POLICY "Staff can view all fees" ON public.fees FOR SELECT USING (public.get_user_role() = 'Staff');
CREATE POLICY "Students can view their own fees" ON public.fees FOR SELECT USING (student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid()));

-- Visitors Policies
CREATE POLICY "Admins and Staff can manage visitors" ON public.visitors FOR ALL USING (public.get_user_role() IN ('Admin', 'Staff'));
CREATE POLICY "Students can view their own visitors" ON public.visitors FOR SELECT USING (student_id IN (SELECT id FROM public.students WHERE user_id = auth.uid()));

-- Maintenance Requests Policies
CREATE POLICY "Admins can manage all maintenance requests" ON public.maintenance_requests FOR ALL USING (public.get_user_role() = 'Admin');
CREATE POLICY "Staff can view and update maintenance requests" ON public.maintenance_requests FOR ALL USING (public.get_user_role() = 'Staff');
CREATE POLICY "Students can create and view their own requests" ON public.maintenance_requests FOR ALL USING (reported_by_id IN (SELECT id FROM public.students WHERE user_id = auth.uid()));

-- 11. Indexes for performance
CREATE INDEX ON public.students (user_id);
CREATE INDEX ON public.students (room_id);
CREATE INDEX ON public.fees (student_id);
CREATE INDEX ON public.visitors (student_id);
CREATE INDEX ON public.maintenance_requests (reported_by_id);
