-- 1. GENERATE INVOICE

CREATE OR REPLACE FUNCTION public.generate_invoice(
    p_subscription_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_subscription RECORD;
    v_existing_invoice UUID;
    v_invoice_id UUID;

    v_invoice_number TEXT;
    v_issue_date DATE := CURRENT_DATE;
    v_due_date DATE;

    v_period_start DATE;
    v_period_end DATE;

    v_subtotal NUMERIC(12,2) := 0;
    v_tax_total NUMERIC(12,2) := 0;
    v_grand_total NUMERIC(12,2) := 0;

    v_line_subtotal NUMERIC(12,2);
    v_line_tax NUMERIC(12,2);
    v_line_total NUMERIC(12,2);

    v_tax_id UUID;
    v_tax_name TEXT;
    v_tax_rate NUMERIC(5,2);

    v_item RECORD;
BEGIN

    -- 1. Validate subscription ID
    IF p_subscription_id IS NULL THEN
        RAISE EXCEPTION 'Subscription ID is required';
    END IF;

    -- 2. Lock subscription to prevent duplicate generation
    SELECT
        s.id,
        s.customer_id,
        s.status,
        s.current_period_start,
        s.current_period_end,
        s.payment_terms,
        sp.currency
    INTO v_subscription
    FROM public.subscriptions s
    JOIN public.subscription_plans sp
        ON sp.id = s.plan_id
    WHERE s.id = p_subscription_id
    FOR UPDATE OF s;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Subscription not found';
    END IF;

    IF v_subscription.status <> 'active' THEN
        RAISE EXCEPTION 'Only active subscriptions can be invoiced';
    END IF;

    IF v_subscription.current_period_start IS NULL
       OR v_subscription.current_period_end IS NULL THEN
        RAISE EXCEPTION 'Subscription billing period is not configured';
    END IF;

    v_period_start :=
        v_subscription.current_period_start::DATE;

    v_period_end :=
        v_subscription.current_period_end::DATE;

    IF v_period_end <= v_period_start THEN
        RAISE EXCEPTION 'Invalid subscription billing period';
    END IF;

    -- 3. Check whether invoice already exists
    SELECT id
    INTO v_existing_invoice
    FROM public.invoices
    WHERE subscription_id = p_subscription_id
      AND billing_period_start = v_period_start
      AND billing_period_end = v_period_end;

    IF FOUND THEN
        RETURN v_existing_invoice;
    END IF;

    -- 4. Calculate due date using admin-configured payment terms
    v_due_date :=
        v_issue_date + v_subscription.payment_terms;

    -- 5. Generate unique invoice number
    v_invoice_number :=
        'INV-' ||
        TO_CHAR(v_issue_date, 'YYYYMMDD') ||
        '-' ||
        UPPER(SUBSTRING(
            REPLACE(gen_random_uuid()::TEXT, '-', '')
            FROM 1 FOR 8
        ));

    -- 6. Create invoice
    INSERT INTO public.invoices (
        invoice_number,
        subscription_id,
        customer_id,
        billing_period_start,
        billing_period_end,
        subtotal,
        discount_amount,
        tax_amount,
        total,
        amount_paid,
        currency,
        status,
        issue_date,
        due_date
    )
    VALUES (
        v_invoice_number,
        p_subscription_id,
        v_subscription.customer_id,
        v_period_start,
        v_period_end,
        0,
        0,
        0,
        0,
        0,
        v_subscription.currency,
        'draft',
        v_issue_date,
        v_due_date
    )
    RETURNING id INTO v_invoice_id;

    -- 7. Generate invoice lines from subscription items
    FOR v_item IN
        SELECT
            si.id,
            si.quantity,
            si.unit_price,
            pv.name AS variant_name,
            p.name AS product_name,
            p.id AS product_id,
            si.tax_id
        FROM public.subscription_items si
        JOIN public.product_variants pv
            ON pv.id = si.variant_id
        JOIN public.products p
            ON p.id = pv.product_id
        WHERE si.subscription_id = p_subscription_id
        ORDER BY si.id
    LOOP

        v_line_subtotal :=
            ROUND(v_item.quantity * v_item.unit_price, 2);

        -- Default tax: zero
        v_tax_id := NULL;
        v_tax_name := NULL;
        v_tax_rate := 0;

        -- 8. First preference: explicitly assigned tax
        IF v_item.tax_id IS NOT NULL THEN
            SELECT t.id, t.name, t.rate
            INTO v_tax_id, v_tax_name, v_tax_rate
            FROM public.taxes t
            WHERE t.id = v_item.tax_id
              AND t.is_active = TRUE
              AND t.valid_from <= v_issue_date
              AND (
                  t.valid_until IS NULL
                  OR t.valid_until >= v_issue_date
              );
        END IF;

        -- 9. Second preference: product-specific tax
        IF v_tax_id IS NULL THEN
            SELECT t.id, t.name, t.rate
            INTO v_tax_id, v_tax_name, v_tax_rate
            FROM public.taxes t
            WHERE t.product_id = v_item.product_id
              AND t.is_active = TRUE
              AND t.valid_from <= v_issue_date
              AND (
                  t.valid_until IS NULL
                  OR t.valid_until >= v_issue_date
              )
            ORDER BY t.valid_from DESC, t.created_at DESC
            LIMIT 1;
        END IF;

        -- 10. Third preference: global tax
        IF v_tax_id IS NULL THEN
            SELECT t.id, t.name, t.rate
            INTO v_tax_id, v_tax_name, v_tax_rate
            FROM public.taxes t
            WHERE t.product_id IS NULL
              AND t.is_active = TRUE
              AND t.valid_from <= v_issue_date
              AND (
                  t.valid_until IS NULL
                  OR t.valid_until >= v_issue_date
              )
            ORDER BY t.valid_from DESC, t.created_at DESC
            LIMIT 1;
        END IF;

        -- 11. Calculate line tax and total
        v_line_tax :=
            ROUND(v_line_subtotal * COALESCE(v_tax_rate, 0) / 100, 2);

        v_line_total :=
            v_line_subtotal + v_line_tax;

        -- 12. Insert invoice item with tax snapshot
        INSERT INTO public.invoice_items (
            invoice_id,
            description,
            quantity,
            unit_price,
            tax_name,
            tax_rate,
            line_subtotal,
            tax_amount,
            line_total
        )
        VALUES (
            v_invoice_id,
            v_item.product_name || ' - ' || v_item.variant_name,
            v_item.quantity,
            v_item.unit_price,
            v_tax_name,
            COALESCE(v_tax_rate, 0),
            v_line_subtotal,
            v_line_tax,
            v_line_total
        );

        v_subtotal := v_subtotal + v_line_subtotal;
        v_tax_total := v_tax_total + v_line_tax;

    END LOOP;

    -- 13. Ensure subscription contains at least one item
    IF NOT EXISTS (
        SELECT 1
        FROM public.invoice_items
        WHERE invoice_id = v_invoice_id
    ) THEN
        RAISE EXCEPTION 'Cannot generate invoice: subscription has no items';
    END IF;

    -- 14. Calculate final invoice total
    v_grand_total := v_subtotal + v_tax_total;

    -- 15. Update invoice totals
    UPDATE public.invoices
    SET
        subtotal = v_subtotal,
        tax_amount = v_tax_total,
        total = v_grand_total,
        status = 'draft',
        updated_at = NOW()
    WHERE id = v_invoice_id;

    RETURN v_invoice_id;

END;
$$;
