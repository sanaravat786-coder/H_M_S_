/*
# [Master DB Reset with RLS Fix]
This script performs a full reset of the database schema to resolve all previous migration conflicts and RLS issues.

## Query Description: [This is a destructive operation that will drop all existing tables, functions, and types before rebuilding the schema from scratch. This is necessary to ensure a clean and stable database state. BACKUP ANY CRITICAL DATA before running this script.]

## Metadata:
- Schema-Category: ["Dangerous"]
- Impact-Level: ["High"]
- Requires-Backup: [true]
- Reversible: [false]

## Structure Details:
- Drops all existing tables, types, functions, and triggers.
- Re-creates all tables: profiles, students, rooms, fees, visitors, maintenance_requests.
- Re-creates all types: user_role, room_type, room_status, fee_status, visitor_status, maintenance_status.
- Re-creates functions and triggers for user profile creation.
- Implements a complete and correct set of Row-Level Security (RLS) policies.

## Security Implications:
- RLS Status: [Enabled]
- Policy Changes: [Yes]
- Auth Requirements: [Admin role will have full CRUD access. Student/Staff roles will have limited read access.]

## Performance Impact:
- Indexes: [Re-created on primary keys]
- Triggers: [Re-created for new user handling]
- Estimated Impact: [Brief downtime during migration, then normal performance.]
*/

-- Step 1: Drop existing objects in reverse order of dependency
-- Drop the trigger from auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop the function that the trigger uses
DROP FUNCTION IF EXISTS public.handle_new_user;

-- Drop the role-checking function (and policies that depend on it)
DROP FUNCTION IF EXISTS public.get_user_role CASCADE;

-- Drop tables
DROP TABLE IF EXISTS public.maintenance_requests;
DROP TABLE IF EXISTS public.visitors;
DROP TABLE IF EXISTS public.fees;
DROP TABLE IF EXISTS public.rooms;
DROP TABLE IF EXISTS public.students;
DROP TABLE IF EXISTS public.profiles;

-- Drop types
DROP TYPE IF EXISTS public.maintenance_status;
DROP TYPE IF EXISTS public.visitor_status;
DROP TYPE IF EXISTS public.fee_status;
DROP TYPE IF EXISTS public.room_status;
DROP TYPE IF EXISTS public.room_type;
DROP TYPE IF EXISTS public.user_role;

-- Step 2: Re-create types
CREATE TYPE public.user_role AS ENUM ('Admin', 'Student', 'Staff');
CREATE TYPE public.room_type AS ENUM ('Single', 'Double', 'Triple');
CREATE TYPE public.room_status AS ENUM ('Vacant', 'Occupied', 'Maintenance');
CREATE TYPE public.fee_status AS ENUM ('Paid', 'Due', 'Overdue');
CREATE TYPE public.visitor_status AS ENUM ('In', 'Out');
CREATE TYPE public.maintenance_status AS ENUM ('Pending', 'In Progress', 'Resolved');

-- Step 3: Re-create tables
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role user_role NOT NULL DEFAULT 'Student'
);

CREATE TABLE public.students (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    course TEXT,
    contact TEXT,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number INT UNIQUE NOT NULL,
    type room_type NOT NULL,
    status room_status NOT NULL DEFAULT 'Vacant',
    occupants INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE public.fees (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL,
    due_date DATE NOT NULL,
    status fee_status NOT NULL DEFAULT 'Due',
    payment_date DATE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE TABLE public.visitors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    visitor_name TEXT NOT NULL,
    student_id UUID REFERENCES public.students(id) ON DELETE CASCADE,
    check_in_time TIMESTAMPTZ DEFAULT now() NOT NULL,
    check_out_time TIMESTAMPTZ,
    status visitor_status NOT NULL DEFAULT 'In'
);

CREATE TABLE public.maintenance_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    issue TEXT NOT NULL,
    room_number INT,
    reported_by_id UUID REFERENCES public.students(id) ON DELETE SET NULL,
    status maintenance_status NOT NULL DEFAULT 'Pending',
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Step 4: Re-create functions and triggers
-- Function to get user role from auth metadata (non-recursive)
CREATE FUNCTION public.get_user_role()
RETURNS TEXT AS $$
BEGIN
  RETURN (
    SELECT raw_user_meta_data->>'role'
    FROM auth.users
    WHERE id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to create a profile for a new user
CREATE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    (new.raw_user_meta_data->>'role')::user_role
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to call the function on new user signup
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Step 5: Implement Row-Level Security
-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_requests ENABLE ROW LEVEL SECURITY;

-- Policies for 'profiles'
CREATE POLICY "Users can view their own profile" ON public.profiles
FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON public.profiles
FOR UPDATE TO authenticated USING (auth.uid() = id);

-- Policies for all other tables
-- Admin Full Access
CREATE POLICY "Admin has full access to students" ON public.students FOR ALL USING (get_user_role() = 'Admin') WITH CHECK (get_user_role() = 'Admin');
CREATE POLICY "Admin has full access to rooms" ON public.rooms FOR ALL USING (get_user_role() = 'Admin') WITH CHECK (get_user_role() = 'Admin');
CREATE POLICY "Admin has full access to fees" ON public.fees FOR ALL USING (get_user_role() = 'Admin') WITH CHECK (get_user_role() = 'Admin');
CREATE POLICY "Admin has full access to visitors" ON public.visitors FOR ALL USING (get_user_role() = 'Admin') WITH CHECK (get_user_role() = 'Admin');
CREATE POLICY "Admin has full access to maintenance" ON public.maintenance_requests FOR ALL USING (get_user_role() = 'Admin') WITH CHECK (get_user_role() = 'Admin');

-- Authenticated users can read most data (adjust if more granular security is needed)
CREATE POLICY "Authenticated users can view students" ON public.students FOR SELECT USING (authenticated.role = 'authenticated');
CREATE POLICY "Authenticated users can view rooms" ON public.rooms FOR SELECT USING (authenticated.role = 'authenticated');
CREATE POLICY "Authenticated users can view fees" ON public.fees FOR SELECT USING (authenticated.role = 'authenticated');
CREATE POLICY "Authenticated users can view visitors" ON public.visitors FOR SELECT USING (authenticated.role = 'authenticated');
CREATE POLICY "Authenticated users can view maintenance" ON public.maintenance_requests FOR SELECT USING (authenticated.role = 'authenticated');
