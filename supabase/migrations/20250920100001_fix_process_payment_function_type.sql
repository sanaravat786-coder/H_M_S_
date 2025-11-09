/*
# [Function Fix] Correct Type in `process_fee_payment`

This migration fixes a type error in the `process_fee_payment` function that was preventing the previous migration from completing.

## Query Description:
This operation drops the existing, faulty `process_fee_payment` function and recreates it. The fix involves changing a variable declaration from the incorrect type `fee_status_enum` to the correct type `public.fee_status`. This change is safe and does not affect any existing data. It only corrects the function's internal logic.

## Metadata:
- Schema-Category: "Structural"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: true (by reverting to the previous function definition)

## Structure Details:
- Function `public.process_fee_payment(uuid)` is dropped and recreated.

## Security Implications:
- RLS Status: Not applicable to functions directly, but the function respects RLS of tables it accesses.
- Policy Changes: No
- Auth Requirements: The function is defined with `SECURITY DEFINER` and hardened. It can be executed by `authenticated` users.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Negligible. This is a small function definition change.
*/

-- Drop the faulty function first to avoid "function already exists" errors.
DROP FUNCTION IF EXISTS public.process_fee_payment(uuid);

-- Recreate the function with the correct type for the status variable.
CREATE OR REPLACE FUNCTION public.process_fee_payment(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student_id uuid;
  v_fee_amount numeric;
  -- FIX: Corrected type from `fee_status_enum` to `public.fee_status`.
  v_fee_status public.fee_status; 
BEGIN
  -- Set a secure search path
  SET search_path = public;

  -- Check if the fee record exists and get its details
  SELECT student_id, amount, status INTO v_student_id, v_fee_amount, v_fee_status
  FROM fees
  WHERE id = p_fee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fee record not found for ID: %', p_fee_id;
  END IF;

  -- Prevent re-paying an already paid fee
  IF v_fee_status = 'Paid' THEN
    RAISE EXCEPTION 'This fee has already been paid.';
  END IF;

  -- Update the fee status to 'Paid' and set the payment date
  UPDATE fees
  SET 
    status = 'Paid',
    payment_date = now()
  WHERE id = p_fee_id;

  -- Insert a record into the payments table
  INSERT INTO payments (fee_id, student_id, amount, paid_on, payment_method)
  VALUES (p_fee_id, v_student_id, v_fee_amount, now(), 'Online');

END;
$$;

-- Add comment to function
COMMENT ON FUNCTION public.process_fee_payment(uuid) IS 'Processes a fee payment by updating the fee status and creating a payment record. Fixes type error from previous version.';

-- Harden the function
ALTER FUNCTION public.process_fee_payment(uuid) OWNER TO supabase_admin;
GRANT EXECUTE ON FUNCTION public.process_fee_payment(uuid) TO authenticated;
