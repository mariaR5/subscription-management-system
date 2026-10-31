-- 1. CREATE SUBSCRIPTION

CREATE OR REPLACE FUNCTION public.create_subscription(
    p_plan_id UUID,
    p_items JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_subscription_id UUID;
    v_customer_id UUID;

    v_item JSONB;
    v_variant_id UUID;
    v_quantity INTEGER;
    v_price NUMERIC(12,2);

BEGIN

    -- Get logged-in customer
    v_customer_id := auth.uid();

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'User must be logged in';
    END IF;

    -- Validate items
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'Items must be a JSON array';
    END IF;

    -- Validate subscription plan
    IF NOT EXISTS (
        SELECT 1
        FROM subscription_plans
        WHERE id = p_plan_id
          AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Invalid or inactive subscription plan';
    END IF;

    -- Create subscription
    INSERT INTO subscriptions (
        customer_id,
        plan_id,
        status
    )
    VALUES (
        v_customer_id,
        p_plan_id,
        'pending'
    )
    RETURNING id INTO v_subscription_id;

    -- Add subscription items
    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_items)
    LOOP

        IF NOT (
            v_item ? 'variant_id'
            AND v_item ? 'quantity'
        ) THEN
            RAISE EXCEPTION 'Each item needs variant_id and quantity';
        END IF;

        v_variant_id := (v_item->>'variant_id')::UUID;
        v_quantity := (v_item->>'quantity')::INTEGER;

        IF v_quantity <= 0 THEN
            RAISE EXCEPTION 'Quantity must be greater than zero';
        END IF;

        -- Get active variant price
        SELECT pv.price
        INTO v_price
        FROM product_variants pv
        JOIN products p ON p.id = pv.product_id
        WHERE pv.id = v_variant_id
          AND pv.is_active = TRUE
          AND p.is_active = TRUE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid or inactive product variant';
        END IF;

        -- Insert item with price snapshot
        INSERT INTO subscription_items (
            subscription_id,
            variant_id,
            quantity,
            unit_price
        )
        VALUES (
            v_subscription_id,
            v_variant_id,
            v_quantity,
            v_price
        );

    END LOOP;

    RETURN v_subscription_id;

END;
$$;

-- 2. UPDATE SUBSCRIPTION STATUS

CREATE OR REPLACE FUNCTION public.update_subscription_status(
    p_subscription_id UUID,
    p_new_status TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    v_subscription RECORD;

    v_now TIMESTAMPTZ := NOW();
    v_period_end TIMESTAMPTZ;
    v_is_admin BOOLEAN;

BEGIN

    -- Validate requested status
    IF p_new_status NOT IN (
        'active',
        'paused',
        'cancelled',
        'expired'
    ) THEN
        RAISE EXCEPTION 'Invalid subscription status';
    END IF;

    -- Get subscription and plan information
    SELECT
        s.*,
        sp.billing_interval,
        sp.interval_count
    INTO v_subscription
    FROM subscriptions s
    JOIN subscription_plans sp
        ON sp.id = s.plan_id
    WHERE s.id = p_subscription_id
    FOR UPDATE OF s;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Subscription not found';
    END IF;

    -- Check admin/staff role
    SELECT EXISTS (
        SELECT 1
        FROM profiles
        WHERE id = auth.uid()
          AND role IN ('admin', 'staff')
    )
    INTO v_is_admin;

    -- Authorization
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'User must be logged in';
    END IF;

    IF v_subscription.customer_id <> auth.uid()
       AND NOT v_is_admin THEN
        RAISE EXCEPTION 'Not authorized';
    END IF;

    -- Prevent invalid transitions
    IF v_subscription.status = 'pending'
       AND p_new_status NOT IN ('active', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid transition from pending';
    END IF;

    IF v_subscription.status = 'active'
       AND p_new_status NOT IN ('paused', 'cancelled', 'expired') THEN
        RAISE EXCEPTION 'Invalid transition from active';
    END IF;

    IF v_subscription.status = 'paused'
       AND p_new_status NOT IN ('active', 'cancelled') THEN
        RAISE EXCEPTION 'Invalid transition from paused';
    END IF;

    IF v_subscription.status IN ('cancelled', 'expired') THEN
        RAISE EXCEPTION 'Subscription cannot be changed';
    END IF;

    -- Activate or resume
    IF p_new_status = 'active' THEN

        -- Calculate next billing period
        v_period_end := v_now +
            CASE v_subscription.billing_interval
                WHEN 'day' THEN
                    make_interval(days => v_subscription.interval_count)
                WHEN 'week' THEN
                    make_interval(days => v_subscription.interval_count * 7)
                WHEN 'month' THEN
                    make_interval(months => v_subscription.interval_count)
                WHEN 'year' THEN
                    make_interval(years => v_subscription.interval_count)
            END;

        UPDATE subscriptions
        SET
            status = 'active',
            start_date = COALESCE(start_date, v_now),
            current_period_start = v_now,
            current_period_end = v_period_end,
            next_billing_date = v_period_end
        WHERE id = p_subscription_id;

    -- Pause
    ELSIF p_new_status = 'paused' THEN

        UPDATE subscriptions
        SET status = 'paused'
        WHERE id = p_subscription_id;

    -- Cancel
    ELSIF p_new_status = 'cancelled' THEN

        UPDATE subscriptions
        SET
            status = 'cancelled',
            cancelled_at = v_now
        WHERE id = p_subscription_id;

    -- Expire only after billing period ends
    ELSIF p_new_status = 'expired' THEN

        IF v_subscription.current_period_end IS NULL
           OR v_subscription.current_period_end > v_now THEN
            RAISE EXCEPTION 'Subscription billing period has not ended';
        END IF;

        UPDATE subscriptions
        SET status = 'expired'
        WHERE id = p_subscription_id;

    END IF;

    RETURN p_subscription_id;

END;
$$;

-- 3. GET CUSTOMER SUBSCRIPTIONS

CREATE OR REPLACE FUNCTION public.get_customer_subscriptions()
RETURNS SETOF public.subscriptions
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN

    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'User must be logged in';
    END IF;

    RETURN QUERY
    SELECT s.*
    FROM subscriptions s
    WHERE s.customer_id = auth.uid()
    ORDER BY s.created_at DESC;

END;
$$;