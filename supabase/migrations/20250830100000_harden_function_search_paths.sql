/*
# [Hardening] Set Secure Search Path for All Functions
This migration hardens the security of all custom database functions by explicitly setting their `search_path`. This mitigates the "Function Search Path Mutable" security advisory by preventing potential search path hijacking attacks.

## Query Description: This operation modifies the configuration of existing functions to enhance security. It does not alter the logic or data structures. The change is safe and reversible, but it's a critical security best practice. By locking down the search path, we ensure that functions only look for objects (like tables or other functions) in schemas we explicitly trust (`extensions` and `public`).

## Metadata:
- Schema-Category: "Security"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Modifies the `search_path` for the following functions:
  - `handle_new_user()`
  - `update_room_occupancy(uuid)`
  - `allocate_room(uuid, uuid)`
  - `get_unallocated_students()`
  - `universal_search(text)`
  - `get_or_create_session(date, text, text, integer)`
  - `bulk_mark_attendance(uuid, jsonb)`
  - `student_attendance_calendar(uuid, integer, integer)`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None
- Mitigates: Search Path Hijacking (CWE-426)

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. May slightly improve performance by reducing schema lookup paths.
*/

-- Set a secure search path for all custom functions to address security advisories.
-- This prevents search path hijacking attacks.

ALTER FUNCTION public.handle_new_user()
SET search_path = 'extensions', 'public';

ALTER FUNCTION public.update_room_occupancy(p_room_id uuid)
SET search_path = 'extensions', 'public';

ALTER FUNCTION public.allocate_room(p_student_id uuid, p_room_id uuid)
SET search_path = 'extensions', 'public';

ALTER FUNCTION public.get_unallocated_students()
SET search_path = 'extensions', 'public';

ALTER FUNCTION public.universal_search(p_search_term text)
SET search_path = 'extensions', 'public';

ALTER FUNCTION public.get_or_create_session(p_date date, p_type text, p_course text, p_year integer)
SET search_path = 'extensions', 'public';

ALTER FUNCTION public.bulk_mark_attendance(p_session_id uuid, p_records jsonb)
SET search_path = 'extensions', 'public';

ALTER FUNCTION public.student_attendance_calendar(p_student_id uuid, p_month integer, p_year integer)
SET search_path = 'extensions', 'public';
