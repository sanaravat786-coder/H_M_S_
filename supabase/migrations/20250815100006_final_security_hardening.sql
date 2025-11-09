/*
# [Final Security Hardening]
[This script hardens the remaining pre-existing functions by explicitly setting their `search_path`. This resolves the final security advisory warning and prevents potential schema-hijacking attacks by ensuring functions only operate within the 'public' schema.]

## Query Description:
This operation is safe and non-destructive. It modifies the metadata of existing functions without altering their logic or affecting any data. It is a recommended security best practice.

## Metadata:
- Schema-Category: ["Safe", "Structural"]
- Impact-Level: ["Low"]
- Requires-Backup: false
- Reversible: true

## Structure Details:
- Modifies the `search_path` configuration for the following functions:
  - `universal_search(text)`
  - `get_user_role(uuid)`
  - `get_unallocated_students()`
  - `allocate_room(uuid, uuid)`
  - `update_room_occupancy(uuid)`

## Security Implications:
- RLS Status: Unchanged
- Policy Changes: No
- Auth Requirements: None
- Mitigates: `[WARN] Function Search Path Mutable` security advisory.

## Performance Impact:
- Indexes: Unchanged
- Triggers: Unchanged
- Estimated Impact: None. This is a metadata change with no runtime performance impact.
*/

-- Harden the universal search function
ALTER FUNCTION universal_search(p_search_term text)
SET search_path = 'public';

-- Harden the user role utility function
ALTER FUNCTION get_user_role(p_user_id uuid)
SET search_path = 'public';

-- Harden the allocation utility functions
ALTER FUNCTION get_unallocated_students()
SET search_path = 'public';

ALTER FUNCTION allocate_room(p_student_id uuid, p_room_id uuid)
SET search_path = 'public';

ALTER FUNCTION update_room_occupancy(p_room_id uuid)
SET search_path = 'public';
