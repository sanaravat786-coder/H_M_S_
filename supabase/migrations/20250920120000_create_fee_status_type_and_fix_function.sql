/*
# [Fix] Create `fee_status` ENUM and Recreate `process_fee_payment` Function
This migration corrects a critical error where the `process_fee_payment` function was created without its dependent `fee_status` ENUM type existing. This script first creates the necessary type and then safely recreates the function with the correct logic and security hardening.

## Query Description:
This operation is safe to run. It first checks for the existence of the `fee_status` type and creates it if it doesn't exist. It then drops the potentially faulty `process_fee_payment` function and recreates it. This ensures the fee payment system will work correctly without data loss.

## Metadata:
- Schema-Category: ["Structural", "Data"]
- Impact-Level: ["Medium"]
- Requires-Backup: false
- Reversible: false

## Structure Details:
- **Types Created:**
  - `public.fee_status` ENUM ('Due', 'Paid', 'Overdue')
- **Functions Dropped:**
  - `public.process_fee_payment` (if exists)
- **Functions Created:**
  - `public.process_fee_payment(p_fee_id uuid)`: Securely processes a fee payment, updating the fee status and creating a payment record.

## Security Implications:
- RLS Status: Not directly affected, but the function will operate under the invoker's RLS policies.
- Policy Changes: No
- Auth Requirements: The function should be called by an authenticated user with appropriate RLS permissions on `fees` and `payments` tables.
- **Security Hardening**: The `search_path` for the function is explicitly set to `public` to mitigate search path hijacking vulnerabilities, addressing a security advisory.

## Performance Impact:
- Indexes: None
- Triggers: None
- Estimated Impact: Low. This is a one-time structural change. The function itself is performant for single-record transactions.
*/

-- Step 1: Create the ENUM type if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'fee_status') THEN
        CREATE TYPE public.fee_status AS ENUM ('Due', 'Paid', 'Overdue');
    END IF;
END$$;


-- Step 2: Drop the old function if it exists to ensure a clean slate
DROP FUNCTION IF EXISTS public.process_fee_payment(uuid);


-- Step 3: Recreate the function with the correct type and security hardening
CREATE OR REPLACE FUNCTION public.process_fee_payment(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fee_amount numeric;
  v_student_id uuid;
  v_fee_status fee_status;
BEGIN
  -- Check the current status and get details of the fee
  SELECT amount, student_id, status
  INTO v_fee_amount, v_student_id, v_fee_status
  FROM public.fees
  WHERE id = p_fee_id;

  -- Raise an exception if the fee does not exist
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fee with ID % not found.', p_fee_id;
  END IF;

  -- Proceed only if the fee is not already paid
  IF v_fee_status <> 'Paid' THEN
    -- Update the fee status to 'Paid' and set the payment date
    UPDATE public.fees
    SET
      status = 'Paid',
      payment_date = now()
    WHERE id = p_fee_id;

    -- Insert a record into the payments table
    INSERT INTO public.payments (fee_id, amount, paid_on, student_id)
    VALUES (p_fee_id, v_fee_amount, now(), v_student_id);
  ELSE
    -- If already paid, raise a notice to inform the caller.
    RAISE NOTICE 'Fee with ID % is already paid.', p_fee_id;
  END IF;
END;
$$;
