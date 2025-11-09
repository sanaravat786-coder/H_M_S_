/*
# [Migration] Fix User Profile Creation Trigger
This script resolves the "Database error saving new user" by ensuring the `profiles` table schema is correct before creating the necessary trigger function.

## Query Description:
This operation is structural and safe. It adds a missing `email` column to the `profiles` table if it doesn't already exist. It then recreates the policies and the `handle_new_user` trigger function to correctly populate the `profiles` table upon new user sign-up. This fixes the schema mismatch that caused the previous migration to fail. No data will be lost.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by dropping the column and trigger)

## Structure Details:
- Table `public.profiles`: Adds `email` column if not exists.
- Function `public.handle_new_user`: Recreated to use the `email` column.
- Trigger `on_auth_user_created`: Recreated on `auth.users`.

## Security Implications:
- RLS Status: Enabled on `profiles`.
- Policy Changes: No, policies are re-asserted idempotently.
- Auth Requirements: The trigger function runs with `SECURITY DEFINER` to bypass RLS for system-level profile creation.

## Performance Impact:
- Indexes: A `UNIQUE` index is added to the `email` column if it's created.
- Triggers: One trigger is updated on `auth.users`.
- Estimated Impact: Negligible impact on performance.
*/

-- 0) Preflight: ensure required extensions
create extension if not exists pgcrypto with schema public;

-- 1) PROFILES table: Create if it doesn't exist, then ensure all columns are present.
create table if not exists public.profiles (
  id uuid primary key,
  created_at timestamptz not null default now()
);

-- Add/ensure columns exist to make this script safely re-runnable.
alter table public.profiles
  add column if not exists full_name text not null default '',
  add column if not exists role text not null default 'student' check (role in ('admin','staff','student')),
  add column if not exists email text unique;

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

-- 4) Post-signup trigger function (runs under elevated privileges)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(new.raw_user_meta_data->>'role','student');
  v_full_name text := coalesce(new.raw_user_meta_data->>'full_name','');
begin
  -- Normalize/validate role
  if v_role not in ('admin','staff','student') then
    v_role := 'student';
  end if;

  -- Insert corresponding profile row, or update it if it already exists.
  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, v_full_name, v_role)
  on conflict (id) do update set
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role;

  return new;
end;
$$;

-- 5) Grant execute permissions
revoke all on function public.handle_new_user() from public;
grant execute on function public.handle_new_user() to postgres, authenticated, anon;

-- 6) Trigger on auth.users AFTER INSERT
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- 7) Sanity check: Make sure profiles.email is nullable to avoid issues with different auth providers.
alter table public.profiles alter column email drop not null;
