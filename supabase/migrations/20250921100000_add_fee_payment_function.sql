/*
# [Function] Process Fee Payment
This function handles the payment of a specific fee record by a student. It updates the fee status to 'Paid' and records the transaction in the 'payments' table. This operation is designed to be atomic.

## Query Description:
This function will:
1. Verify that the fee record exists and belongs to the specified student.
2. Update the `fees` table, setting the `status` to 'Paid' and `payment_date` to the current timestamp.
3. Insert a new record into the `payments` table with the details of the transaction.
This operation is safe and does not involve data loss. It only modifies records related to the specific fee being paid.

## Metadata:
- Schema-Category: "Data"
- Impact-Level: "Low"
- Requires-Backup: false
- Reversible: false

## Structure Details:
- Tables affected: `fees` (UPDATE), `payments` (INSERT)

## Security Implications:
- RLS Status: Enabled on both tables.
- Policy Changes: No.
- Auth Requirements: The function should be called by an authenticated user. It internally checks if the fee belongs to the calling user.
- The function is set with `SECURITY DEFINER` to ensure it can update tables correctly, while the logic inside maintains user-level security.

## Performance Impact:
- Indexes: Assumes primary key indexes on `fees.id` and `student_id`.
- Triggers: No new triggers are added.
- Estimated Impact: Low. The function performs targeted UPDATE and INSERT operations based on primary keys.
*/
CREATE OR REPLACE FUNCTION public.process_fee_payment(p_fee_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_student_id uuid;
  v_fee_amount numeric;
  v_fee_status fee_status_enum;
BEGIN
  -- Get the student_id from the session
  v_student_id := auth.uid();

  -- Check if the fee exists, belongs to the user, and is not already paid
  SELECT amount, status INTO v_fee_amount, v_fee_status
  FROM public.fees
  WHERE id = p_fee_id AND student_id = v_student_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fee not found or access denied.';
  END IF;

  IF v_fee_status = 'Paid' THEN
    RAISE EXCEPTION 'This fee has already been paid.';
  END IF;

  -- Update the fee record
  UPDATE public.fees
  SET
    status = 'Paid',
    payment_date = now()
  WHERE id = p_fee_id;

  -- Insert into payments table
  INSERT INTO public.payments(fee_id, student_id, amount, paid_on)
  VALUES (p_fee_id, v_student_id, v_fee_amount, now());

END;
$$;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.process_fee_payment(uuid) TO authenticated;
