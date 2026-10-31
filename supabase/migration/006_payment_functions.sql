-- 006_PAYMENT_FUNCTIONS.SQL

BEGIN;

-- =========================================
-- FUNCTION: RECORD PAYMENT
-- =========================================

CREATE OR REPLACE FUNCTION public.record_payment(
    p_invoice_id UUID,
    p_amount NUMERIC(12,2),
    p_payment_method TEXT,
    p_transaction_reference TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_invoice RECORD;
    v_payment_id UUID;
    v_new_amount_paid NUMERIC(12,2);
    v_balance NUMERIC(12,2);
    v_new_status TEXT;
BEGIN

    -- 1. Validate authentication

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;


    -- 2. Validate input

    IF p_invoice_id IS NULL THEN
        RAISE EXCEPTION 'Invoice ID is required';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Payment amount must be greater than zero';
    END IF;

    IF p_payment_method NOT IN (
        'upi',
        'card',
        'bank_transfer',
        'cash',
        'other'
    ) THEN
        RAISE EXCEPTION 'Invalid payment method';
    END IF;


    -- 3. Fetch and lock invoice
    -- Only the invoice owner can record a payment.

    SELECT
        i.id,
        i.customer_id,
        i.total,
        i.amount_paid,
        i.currency,
        i.status
    INTO v_invoice
    FROM public.invoices i
    WHERE i.id = p_invoice_id
      AND i.customer_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found or access denied';
    END IF;


    -- 4. Reject invoices that cannot accept payments

    IF v_invoice.status IN ('draft', 'cancelled', 'paid') THEN
        RAISE EXCEPTION
            'This invoice cannot accept payments';
    END IF;


    -- 5. Calculate outstanding balance

    v_balance :=
        v_invoice.total - v_invoice.amount_paid;

    IF v_balance <= 0 THEN
        RAISE EXCEPTION 'Invoice has no outstanding balance';
    END IF;

    IF p_amount > v_balance THEN
        RAISE EXCEPTION
            'Payment exceeds outstanding balance of %',
            v_balance;
    END IF;


    -- 6. Calculate updated amount paid

    v_new_amount_paid :=
        v_invoice.amount_paid + p_amount;


    -- 7. Determine new invoice status

    IF v_new_amount_paid = v_invoice.total THEN
        v_new_status := 'paid';
    ELSE
        v_new_status := 'partially_paid';
    END IF;


    -- 8. Insert payment record

    INSERT INTO public.payments (
        invoice_id,
        customer_id,
        amount,
        currency,
        payment_method,
        payment_status,
        transaction_reference,
        paid_at
    )
    VALUES (
        v_invoice.id,
        v_invoice.customer_id,
        p_amount,
        v_invoice.currency,
        p_payment_method,
        'successful',
        p_transaction_reference,
        NOW()
    )
    RETURNING id INTO v_payment_id;


    -- 9. Update invoice

    UPDATE public.invoices
    SET
        amount_paid = v_new_amount_paid,
        status = v_new_status,
        updated_at = NOW()
    WHERE id = v_invoice.id;


    -- 10. Return payment ID

    RETURN v_payment_id;

END;
$$;


-- =========================================
-- SECURITY: FUNCTION PERMISSIONS
-- =========================================

REVOKE ALL ON FUNCTION public.record_payment(
    UUID,
    NUMERIC,
    TEXT,
    TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.record_payment(
    UUID,
    NUMERIC,
    TEXT,
    TEXT
) FROM anon;

GRANT EXECUTE ON FUNCTION public.record_payment(
    UUID,
    NUMERIC,
    TEXT,
    TEXT
) TO authenticated;

COMMIT;
