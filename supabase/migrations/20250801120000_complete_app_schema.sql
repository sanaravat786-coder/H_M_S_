/*
# [Complete Schema Setup for Hostel Management System]
This script sets up the entire database schema, including tables for profiles, students, rooms, fees, visitors, maintenance, and notices. It also establishes relationships, creates a function to handle new user profiles, and implements comprehensive Row Level Security (RLS) policies for data protection.

## Query Description: This script will drop existing tables if they exist to ensure a clean setup. This is a destructive action on the listed tables. It's designed to be run on a fresh database or when a full schema reset is intended. Please back up any critical data before applying this migration.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: true
- Reversible: false

## Structure Details:
- Tables created: profiles, students, rooms, fees, payments, visitors, maintenance_requests, notices.
- Types created: role, room_type, room_status, fee_status, maintenance_status, visitor_status, audience_type.
- Functions created: public.handle_new_user.
- Triggers created: on_auth_user_created on auth.users.

## Security Implications:
- RLS Status: Enabled on all application tables.
- Policy Changes: Yes, policies are created for all tables to enforce access control based on user roles (Admin, Staff, Student).
- Auth Requirements: Policies rely on `auth.uid()` and a custom `get_my_claim` function to determine user roles.

## Performance Impact:
- Indexes: Primary keys and foreign keys will be indexed automatically.
- Triggers: A trigger is added to `auth.users` which runs once on user creation.
- Estimated Impact: Low performance impact on a new database.
*/

--
-- Extension: pgcrypto
--
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

--
-- Custom Types for Enum-like behavior
--
CREATE TYPE public.role AS ENUM ('Admin', 'Student', 'Staff');
CREATE TYPE public.room_type AS ENUM ('Single', 'Double', 'Triple');
CREATE TYPE public.room_status AS ENUM ('Vacant', 'Occupied', 'Maintenance');
CREATE TYPE public.fee_status AS ENUM ('Paid', 'Due', 'Overdue');
CREATE TYPE public.maintenance_status AS ENUM ('Pending', 'In Progress', 'Resolved');
CREATE TYPE public.visitor_status AS ENUM ('In', 'Out');
CREATE TYPE public.audience_type AS ENUM ('all', 'students', 'staff');

--
-- Drop existing tables in reverse order of dependency
--
DROP TABLE IF EXISTS public.payments;
DROP TABLE IF EXISTS public.fees;
DROP TABLE IF EXISTS public.visitors;
DROP TABLE IF EXISTS public.maintenance_requests;
DROP TABLE IF EXISTS public.notices;
DROP TABLE IF EXISTS public.students;
DROP TABLE IF EXISTS public.rooms;
DROP TABLE IF EXISTS public.profiles;

--
-- Table: profiles
-- Stores public-facing user data.
--
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role public.role NOT NULL DEFAULT 'Student'::public.role
);
COMMENT ON TABLE public.profiles IS 'Stores public user data, linked to authentication.';

--
-- Table: rooms
-- Stores information about hostel rooms.
--
CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number TEXT NOT NULL UNIQUE,
    type public.room_type NOT NULL,
    status public.room_status NOT NULL DEFAULT 'Vacant'::public.room_status,
    occupants INT NOT NULL DEFAULT 0 CHECK (occupants >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.rooms IS 'Manages hostel rooms, their types, and status.';

--
-- Table: students
-- Stores detailed information about students.
--
CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
    full_name TEXT NOT NULL,
    email TEXT UNIQUE,
    course TEXT,
    contact TEXT,
    room_id UUID REFERENCES public.rooms(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.students IS 'Contains detailed records for each student.';

--
-- Table: fees
-- Manages fee records for students.
--
CREATE TABLE public.fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    due_date DATE NOT NULL,
    status public.fee_status NOT NULL DEFAULT 'Due'::public.fee_status,
    payment_date TIMESTAMPTZ,
    created_at TIMESTTAMPZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.fees IS 'Tracks student fee payments and statuses.';

--
-- Table: payments
-- Logs individual payment transactions.
--
CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fee_id UUID NOT NULL REFERENCES public.fees(id) ON DELETE CASCADE,
    amount NUMERIC(10, 2) NOT NULL,
    paid_on TIMESTAMPTZ NOT NULL DEFAULT now(),
    payment_method TEXT
);
COMMENT ON TABLE public.payments IS 'Records payment transactions for fees.';

--
-- Table: visitors
-- Logs visitor entries and exits.
--
CREATE TABLE public.visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    visitor_name TEXT NOT NULL,
    check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_out_time TIMESTAMPTZ,
    status public.visitor_status NOT NULL DEFAULT 'In'::public.visitor_status
);
COMMENT ON TABLE public.visitors IS 'Maintains a log of visitors for students.';

--
-- Table: maintenance_requests
-- Tracks maintenance issues reported by users.
--
CREATE TABLE public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reported_by_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    issue TEXT NOT NULL,
    room_number TEXT,
    status public.maintenance_status NOT NULL DEFAULT 'Pending'::public.maintenance_status,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.maintenance_requests IS 'Tracks maintenance issues and their resolution status.';

--
-- Table: notices
-- For publishing announcements.
--
CREATE TABLE public.notices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    audience public.audience_type NOT NULL DEFAULT 'all'::public.audience_type,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.notices IS 'A board for posting notices to different audiences.';

--
-- Function and Trigger to create a profile for new users
--
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    (NEW.raw_user_meta_data->>'role')::public.role
  );
  
  -- If the new user is a student, create a corresponding student record
  IF (NEW.raw_user_meta_data->>'role')::public.role = 'Student' THEN
    INSERT INTO public.students (user_id, full_name, email)
    VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name', NEW.email);
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

--
-- Trigger to call handle_new_user on user creation
--
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

--
-- Helper function to get user role from JWT claims
--
CREATE OR REPLACE FUNCTION public.get_my_claim(claim TEXT)
RETURNS TEXT AS $$
  SELECT nullif(current_setting('request.jwt.claims', true)::jsonb->>claim, '')::TEXT;
$$ LANGUAGE sql STABLE;


--
-- RLS Policies
--

-- Profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view their own profile" ON public.profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Admins can view all profiles" ON public.profiles FOR SELECT USING (get_my_claim('role') = '"Admin"');
CREATE POLICY "Users can update their own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Rooms
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "All authenticated users can view rooms" ON public.rooms FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admins can manage rooms" ON public.rooms FOR ALL USING (get_my_claim('role') = '"Admin"');

-- Students
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can view all students" ON public.students FOR SELECT USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));
CREATE POLICY "Students can view their own record" ON public.students FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Admins can manage student records" ON public.students FOR ALL USING (get_myclaim('role') = '"Admin"');
CREATE POLICY "Staff can update student records" ON public.students FOR UPDATE USING (get_myclaim('role') = '"Staff"');


-- Fees
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can view all fees" ON public.fees FOR SELECT USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));
CREATE POLICY "Students can view their own fees" ON public.fees FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.students WHERE students.id = fees.student_id AND students.user_id = auth.uid())
);
CREATE POLICY "Admins can manage fees" ON public.fees FOR ALL USING (get_my_claim('role') = '"Admin"');

-- Payments
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can view all payments" ON public.payments FOR SELECT USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));
CREATE POLICY "Admins can manage payments" ON public.payments FOR ALL USING (get_my_claim('role') = '"Admin"');

-- Visitors
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins and Staff can view all visitors" ON public.visitors FOR SELECT USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));
CREATE POLICY "Students can view their own visitors" ON public.visitors FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.students WHERE students.id = visitors.student_id AND students.user_id = auth.uid())
);
CREATE POLICY "Admins and Staff can manage visitors" ON public.visitors FOR ALL USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));

-- Maintenance Requests
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "All authenticated users can create requests" ON public.maintenance_requests FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Users can view their own requests" ON public.maintenance_requests FOR SELECT USING (auth.uid() = reported_by_id);
CREATE POLICY "Admins and Staff can view all requests" ON public.maintenance_requests FOR SELECT USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));
CREATE POLICY "Admins and Staff can update requests" ON public.maintenance_requests FOR UPDATE USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));
CREATE POLICY "Admins can delete requests" ON public.maintenance_requests FOR DELETE USING (get_my_claim('role') = '"Admin"');

-- Notices
ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "All authenticated users can view notices" ON public.notices FOR SELECT USING (
    auth.role() = 'authenticated' AND
    (
        audience = 'all' OR
        (audience = 'students' AND get_my_claim('role') = '"Student"') OR
        (audience = 'staff' AND get_my_claim('role') IN ('"Admin"', '"Staff"'))
    )
);
CREATE POLICY "Admins and Staff can manage notices" ON public.notices FOR ALL USING (get_my_claim('role') IN ('"Admin"', '"Staff"'));
