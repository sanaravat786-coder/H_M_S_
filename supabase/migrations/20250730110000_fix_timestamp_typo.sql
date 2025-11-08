/*
# [Corrected Initial Schema Setup]
This migration script corrects a typo in a previous version and establishes the complete database schema for the Hostel Management System. It includes table creations, relationships, and Row Level Security (RLS) policies.

## Query Description: This script will:
1. Create tables: profiles, rooms, students, fees, payments, visitors, maintenance_requests, and notices.
2. Define primary keys, foreign keys, and other constraints.
3. Set up a trigger to automatically create a user profile upon sign-up.
4. Implement Row Level Security policies to ensure data is only accessible by authorized users based on their roles (Admin, Staff, Student).
5. Add a helper function to read user roles from JWT claims for use in RLS policies.

This is a foundational script. It is safe to run on a new database, but could cause issues if tables with these names already exist without the correct structure.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: true
- Reversible: false

## Security Implications:
- RLS Status: Enabled for all tables.
- Policy Changes: Yes, this script defines all the initial RLS policies.
- Auth Requirements: Policies rely on Supabase Auth and JWT claims for user roles.
*/

-- =================================================================
-- Helper function to get user role from JWT claims
-- =================================================================
CREATE OR REPLACE FUNCTION public.get_my_claim(claim TEXT) RETURNS JSONB AS $$
  SELECT coalesce(current_setting('request.jwt.claims', true)::jsonb ->> claim, null)::jsonb;
$$ LANGUAGE SQL STABLE;

-- =================================================================
-- 1. PROFILES TABLE
-- Stores public user data, linked to auth.users.
-- =================================================================
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role TEXT NOT NULL DEFAULT 'Student'::text,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- RLS for profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Public profiles are viewable by everyone." ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can insert their own profile." ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update their own profile." ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Function and Trigger to create profile on new user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (new.id, new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'role');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if it exists to prevent errors on re-run
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- =================================================================
-- 2. ROOMS TABLE
-- =================================================================
CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL, -- e.g., 'Single', 'Double'
    status TEXT NOT NULL DEFAULT 'Vacant', -- 'Vacant', 'Occupied', 'Maintenance'
    occupants INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS for rooms
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin/Staff can manage rooms." ON public.rooms FOR ALL
    USING (get_my_claim('role') = '"Admin"' OR get_my_claim('role') = '"Staff"');
CREATE POLICY "Authenticated users can view rooms." ON public.rooms FOR SELECT
    USING (auth.role() = 'authenticated');

-- =================================================================
-- 3. STUDENTS TABLE
-- =================================================================
CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    course TEXT,
    contact TEXT,
    room_id UUID REFERENCES public.rooms(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS for students
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin/Staff can manage students." ON public.students FOR ALL
    USING (get_my_claim('role') = '"Admin"' OR get_my_claim('role') = '"Staff"');
CREATE POLICY "Students can view their own record." ON public.students FOR SELECT
    USING (get_my_claim('role') = '"Student"' AND email = auth.email());

-- =================================================================
-- 4. FEES TABLE
-- =================================================================
CREATE TABLE public.fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    due_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'Due', -- 'Due', 'Paid', 'Overdue'
    payment_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS for fees
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin/Staff can manage fees." ON public.fees FOR ALL
    USING (get_my_claim('role') = '"Admin"' OR get_my_claim('role') = '"Staff"');
CREATE POLICY "Students can view their own fees." ON public.fees FOR SELECT
    USING (get_my_claim('role') = '"Student"' AND student_id = (SELECT s.id FROM public.students s WHERE s.email = auth.email()));

-- =================================================================
-- 5. PAYMENTS TABLE
-- =================================================================
CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fee_id UUID NOT NULL REFERENCES public.fees(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    paid_on TIMESTAMPTZ NOT NULL DEFAULT now(),
    payment_method TEXT
);

-- RLS for payments
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin/Staff can manage payments." ON public.payments FOR ALL
    USING (get_my_claim('role') = '"Admin"' OR get_my_claim('role') = '"Staff"');
CREATE POLICY "Students can view their own payments." ON public.payments FOR SELECT
    USING (get_my_claim('role') = '"Student"' AND fee_id IN (SELECT f.id FROM public.fees f JOIN public.students s ON f.student_id = s.id WHERE s.email = auth.email()));

-- =================================================================
-- 6. VISITORS TABLE
-- =================================================================
CREATE TABLE public.visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_name TEXT NOT NULL,
    student_id UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ NOT NULL DEFAULT now(),
    check_out_time TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'In' -- 'In', 'Out'
);

-- RLS for visitors
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin/Staff can manage visitors." ON public.visitors FOR ALL
    USING (get_my_claim('role') = '"Admin"' OR get_my_claim('role') = '"Staff"');
CREATE POLICY "Students can view their own visitors." ON public.visitors FOR SELECT
    USING (get_my_claim('role') = '"Student"' AND student_id = (SELECT s.id FROM public.students s WHERE s.email = auth.email()));

-- =================================================================
-- 7. MAINTENANCE REQUESTS TABLE
-- =================================================================
CREATE TABLE public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue TEXT NOT NULL,
    room_number TEXT,
    reported_by_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'Pending', -- 'Pending', 'In Progress', 'Resolved'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS for maintenance
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin/Staff can manage maintenance requests." ON public.maintenance_requests FOR ALL
    USING (get_my_claim('role') = '"Admin"' OR get_my_claim('role') = '"Staff"');
CREATE POLICY "Users can create and view their own requests." ON public.maintenance_requests FOR ALL
    USING (auth.uid() = reported_by_id);

-- =================================================================
-- 8. NOTICES TABLE
-- =================================================================
CREATE TABLE public.notices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    created_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    audience TEXT NOT NULL DEFAULT 'all', -- 'all', 'students', 'staff'
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- RLS for notices
ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin/Staff can manage notices." ON public.notices FOR ALL
    USING (get_my_claim('role') = '"Admin"' OR get_my_claim('role') = '"Staff"');
CREATE POLICY "Notices are viewable based on audience." ON public.notices FOR SELECT
    USING (
        audience = 'all' OR
        (audience = 'students' AND get_my_claim('role') = '"Student"') OR
        (audience = 'staff' AND get_my_claim('role') = '"Staff"') OR
        (get_my_claim('role') = '"Admin"')
    );
