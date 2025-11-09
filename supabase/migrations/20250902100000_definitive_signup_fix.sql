/*
# Definitive Sign-Up and Profile Creation Fix
This script overhauls the user profile creation process. It creates/updates the 'profiles' table, enables Row Level Security (RLS), defines secure policies, and sets up a trigger on the 'auth.users' table. This ensures that a new profile is automatically and safely created for every new user who signs up.

## Query Description: 
This operation reconfigures core user profile management. It creates a new 'profiles' table if it doesn't exist and sets up a trigger to automatically populate it upon user sign-up. While designed to be safe and non-destructive ('create if not exists'), applying it to a live database could alter existing trigger behavior. It is recommended to back up your database before applying this migration.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "High"
- Requires-Backup: true
- Reversible: true

## Structure Details:
- public.profiles: table created/updated. Columns: id, email, full_name, role, created_at.
- public.handle_new_user: function created/replaced.
- auth.users: trigger on_auth_user_created created/replaced.

## Security Implications:
- RLS Status: Enabled on public.profiles.
- Policy Changes: Yes. `profiles_select_own` and `profiles_update_own` policies are created if they don't exist. No public INSERT policy is created, which is a key security feature.
- Auth Requirements: The trigger `handle_new_user` runs with `SECURITY DEFINER` privileges to bypass RLS for system-level inserts.

## Performance Impact:
- Indexes: `profiles_pkey` (primary key) and `profiles_email_key` (unique) are created.
- Triggers: One `AFTER INSERT` trigger is added to `auth.users`.
- Estimated Impact: Negligible impact on read/write performance. The trigger adds a small, single-insert overhead to the sign-up process, which is standard practice.
*/

-- 0) Preflight: ensure required extensions
create extension if not exists pgcrypto with schema public;

-- 1) PROFILES table (id must match auth.users.id)
create table if not exists public.profiles (
  id uuid primary key,                       -- equals auth.users.id
  email text unique,                         -- optional mirror
  full_name text not null default '',
  role text not null default 'student' check (role in ('admin','staff','student')),
  created_at timestamptz not null default now()
);

-- 2) Enable RLS on profiles
alter table public.profiles enable row level security;

-- 3) Policies (minimum viable + secure)
-- 3a) Users can select their own profile
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='profiles' and policyname='profiles_select_own'
  ) then
    create policy profiles_select_own
      on public.profiles
      for select
      using (id = auth.uid());
  end if;
end $$;

-- 3b) Users can update only their own profile (optional)
do $$ begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='profiles' and policyname='profiles_update_own'
  ) then
    create policy profiles_update_own
      on public.profiles
      for update
      using (id = auth.uid())
      with check (id = auth.uid());
  end if;
end $$;

-- 3c) Allow inserts from our SECURITY DEFINER function only (no direct client inserts)
-- We DO NOT add a public INSERT policy; the trigger function will bypass RLS.

-- 4) Post-signup trigger function (runs under elevated privileges)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'role','student'); -- default role
  v_full_name text := coalesce(new.raw_user_meta_data->>'full_name','');
begin
  -- Normalize/validate role
  if v_role not in ('admin','staff','student') then
    v_role := 'student';
  end if;

  -- Insert corresponding profile row (bypass RLS via SECURITY DEFINER)
  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, v_full_name, v_role)
  on conflict (id) do nothing;

  return new;
end;
$$;

-- 5) Ensure the definer is the database owner (supabase admin). Grant execute to auth role.
revoke all on function public.handle_new_user() from public;
grant execute on function public.handle_new_user() to postgres, authenticated, anon;

-- 6) Trigger on auth.users AFTER INSERT
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- 7) Sanity checks for common constraint pitfalls
--    Make sure profiles.email is nullable or unique on real emails; avoid blocking inserts on null/dup.
alter table public.profiles alter column email drop not null;
