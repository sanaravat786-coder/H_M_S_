/*
# [Fix Missing Fee Status Type and Function]
[This migration ensures the custom type `fee_status` exists and then correctly recreates the `process_fee_payment` function that depends on it. This resolves a "type does not exist" error during migration.]

## Query Description: [This operation first safely creates the `fee_status` ENUM type ('Due', 'Paid', 'Overdue') if it's missing. It then drops the previous, faulty version of the `process_fee_payment` function and recreates it with the correct type reference. This is a low-risk, corrective action that is essential for the fee payment functionality to work. No existing data will be affected.]

## Metadata:
- Schema-Category: ["Structural", "Safe"]
- Impact-Level: ["Low"]
- Requires-Backup: [false]
- Reversible: [false]

## Structure Details:
- Types Created: `public.fee_status`
- Functions Dropped: `public.process_fee_payment`
- Functions Created: `public.process_fee_payment`

## Security Implications:
- RLS Status: [No Change]
- Policy Changes: [No]
- Auth Requirements: [Function is SECURITY DEFINER]

## Performance Impact:
- Indexes: [None]
- Triggers: [None]
- Estimated Impact: [Negligible. This is a one-time schema and function correction.]
*/

-- Step 1: Ensure the fee_status ENUM type exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'fee_status' AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) THEN
        CREATE TYPE public.fee_status AS ENUM (
            'Due',
            'Paid',
            'Overdue'
        );
    END IF;
END$$;

-- Step 2: Drop the old, faulty function if it exists
DROP FUNCTION IF EXISTS public.process_fee_payment(uuid);

-- Step 3: Recreate the function with the correct type and security settings
CREATE OR REPLACE FUNCTION public.process_fee_payment(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student_id uuid;
  v_fee_amount numeric;
  v_fee_status public.fee_status;
BEGIN
  -- Check if the fee exists and get its details
  SELECT student_id, amount, status INTO v_student_id, v_fee_amount, v_fee_status
  FROM public.fees
  WHERE id = p_fee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fee record not found for ID: %', p_fee_id;
  END IF;

  -- Check if the fee is already paid
  IF v_fee_status = 'Paid' THEN
    RAISE EXCEPTION 'This fee has already been paid.';
  END IF;

  -- Start a transaction
  BEGIN
    -- Update the fee status to 'Paid' and set the payment date
    UPDATE public.fees
    SET 
      status = 'Paid',
      payment_date = now()
    WHERE id = p_fee_id;

    -- Insert a record into the payments table
    INSERT INTO public.payments (fee_id, student_id, amount, paid_on, payment_method)
    VALUES (p_fee_id, v_student_id, v_fee_amount, now(), 'Online');
  EXCEPTION
    WHEN OTHERS THEN
      -- If any error occurs, the transaction will be rolled back automatically.
      RAISE EXCEPTION 'An error occurred during payment processing: %', SQLERRM;
  END;
END;
$$;

-- Grant execution rights to the authenticated role
GRANT EXECUTE ON FUNCTION public.process_fee_payment(uuid) TO authenticated;
