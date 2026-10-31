-- 1. PROFILES

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id)
        ON DELETE CASCADE,

    full_name TEXT,
    email TEXT UNIQUE,

    role TEXT NOT NULL DEFAULT 'customer'
        CHECK (role IN ('admin', 'staff', 'customer')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. PRODUCTS

CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,
    description TEXT,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. PRODUCT VARIANTS

CREATE TABLE public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    product_id UUID NOT NULL
        REFERENCES public.products(id) ON DELETE CASCADE,

    name TEXT NOT NULL,
    sku TEXT UNIQUE,

    price NUMERIC(12,2) NOT NULL
        CHECK (price >= 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. SUBSCRIPTION PLANS

CREATE TABLE public.subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,
    description TEXT,

    price NUMERIC(12,2) NOT NULL
        CHECK (price >= 0),

    currency TEXT NOT NULL DEFAULT 'INR',

    billing_interval TEXT NOT NULL
        CHECK (
            billing_interval IN (
                'day',
                'week',
                'month',
                'year'
            )
        ),

    interval_count INTEGER NOT NULL DEFAULT 1
        CHECK (interval_count > 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 5. SUBSCRIPTIONS

CREATE TABLE public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    customer_id UUID NOT NULL
        REFERENCES auth.users(id),

    plan_id UUID NOT NULL
        REFERENCES public.subscription_plans(id),

    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (
            status IN (
                'pending',
                'active',
                'paused',
                'cancelled',
                'expired'
            )
        ),

    start_date TIMESTAMPTZ,

    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,

    next_billing_date TIMESTAMPTZ,

    cancelled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (
        current_period_end IS NULL
        OR current_period_start IS NULL
        OR current_period_end > current_period_start
    )
);


-- 6. SUBSCRIPTION ITEMS

CREATE TABLE public.subscription_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    subscription_id UUID NOT NULL
        REFERENCES public.subscriptions(id) ON DELETE CASCADE,

    variant_id UUID NOT NULL
        REFERENCES public.product_variants(id),

    quantity INTEGER NOT NULL DEFAULT 1
        CHECK (quantity > 0),

    unit_price NUMERIC(12,2) NOT NULL
        CHECK (unit_price >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (subscription_id, variant_id)
);


-- 7. INVOICES

CREATE TABLE public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_number TEXT NOT NULL UNIQUE,

    subscription_id UUID NOT NULL
        REFERENCES public.subscriptions(id),

    customer_id UUID NOT NULL
        REFERENCES auth.users(id),

    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,

    subtotal NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (subtotal >= 0),

    discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),

    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),

    total NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (total >= 0),

    amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (amount_paid >= 0 AND amount_paid <= total),

    currency TEXT NOT NULL DEFAULT 'INR',

    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (
            status IN (
                'draft',
                'unpaid',
                'partially_paid',
                'paid',
                'overdue',
                'cancelled'
            )
        ),

    issue_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (billing_period_end > billing_period_start),
    CHECK (discount_amount <= subtotal),

    UNIQUE (
        subscription_id,
        billing_period_start,
        billing_period_end
    )
);


-- 8. INVOICE ITEMS

CREATE TABLE public.invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_id UUID NOT NULL
        REFERENCES public.invoices(id) ON DELETE CASCADE,

    description TEXT NOT NULL,

    quantity INTEGER NOT NULL
        CHECK (quantity > 0),

    unit_price NUMERIC(12,2) NOT NULL
        CHECK (unit_price >= 0),

    tax_rate NUMERIC(5,2) NOT NULL DEFAULT 0
        CHECK (tax_rate >= 0 AND tax_rate <= 100),

    line_subtotal NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (line_subtotal >= 0),

    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),

    line_total NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (line_total >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 9. DISCOUNTS

CREATE TABLE public.discounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,

    code TEXT NOT NULL UNIQUE,

    description TEXT,

    discount_type TEXT NOT NULL
        CHECK (
            discount_type IN (
                'percentage',
                'fixed'
            )
        ),

    discount_value NUMERIC(12,2) NOT NULL
        CHECK (discount_value > 0),

    max_discount NUMERIC(12,2)
        CHECK (max_discount IS NULL OR max_discount >= 0),

    minimum_purchase NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (minimum_purchase >= 0),

    valid_from TIMESTAMPTZ,
    valid_until TIMESTAMPTZ,

    usage_limit INTEGER
        CHECK (usage_limit IS NULL OR usage_limit > 0),

    used_count INTEGER NOT NULL DEFAULT 0
        CHECK (used_count >= 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (
        valid_until IS NULL
        OR valid_from IS NULL
        OR valid_until > valid_from
    ),

    CHECK (
        usage_limit IS NULL
        OR used_count <= usage_limit
    )
);


-- 10. SUBSCRIPTION DISCOUNTS

CREATE TABLE public.subscription_discounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    subscription_id UUID NOT NULL
        REFERENCES public.subscriptions(id) ON DELETE CASCADE,

    discount_id UUID NOT NULL
        REFERENCES public.discounts(id),

    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (subscription_id, discount_id)
);


-- 11. PAYMENTS

CREATE TABLE public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_id UUID NOT NULL
        REFERENCES public.invoices(id),

    customer_id UUID NOT NULL
        REFERENCES auth.users(id),

    amount NUMERIC(12,2) NOT NULL
        CHECK (amount > 0),

    currency TEXT NOT NULL DEFAULT 'INR',

    payment_method TEXT NOT NULL
        CHECK (
            payment_method IN (
                'upi',
                'card',
                'bank_transfer',
                'cash',
                'other'
            )
        ),

    payment_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (
            payment_status IN (
                'pending',
                'successful',
                'failed',
                'refunded'
            )
        ),

    transaction_reference TEXT,

    paid_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 12. PAYMENT TRANSACTIONS

CREATE TABLE public.payment_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    payment_id UUID NOT NULL
        REFERENCES public.payments(id) ON DELETE CASCADE,

    gateway_name TEXT,

    gateway_transaction_id TEXT UNIQUE,

    response_data JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- INDEXES

-- Profiles
CREATE INDEX idx_profiles_role
ON public.profiles(role);

-- Products
CREATE INDEX idx_product_variants_product
ON public.product_variants(product_id);

-- Plans
CREATE INDEX idx_subscription_plans_active
ON public.subscription_plans(is_active);

-- Subscriptions
CREATE INDEX idx_subscriptions_customer
ON public.subscriptions(customer_id);

CREATE INDEX idx_subscriptions_plan
ON public.subscriptions(plan_id);

CREATE INDEX idx_subscriptions_status
ON public.subscriptions(status);

CREATE INDEX idx_subscriptions_billing_date
ON public.subscriptions(next_billing_date);

-- Subscription items
CREATE INDEX idx_subscription_items_subscription
ON public.subscription_items(subscription_id);

-- Invoices
CREATE INDEX idx_invoices_customer
ON public.invoices(customer_id);

CREATE INDEX idx_invoices_subscription
ON public.invoices(subscription_id);

CREATE INDEX idx_invoices_status
ON public.invoices(status);

CREATE INDEX idx_invoices_due_date
ON public.invoices(due_date);

-- Invoice items
CREATE INDEX idx_invoice_items_invoice
ON public.invoice_items(invoice_id);

-- Discounts
CREATE INDEX idx_discounts_active
ON public.discounts(is_active);

-- Subscription discounts
CREATE INDEX idx_subscription_discounts_subscription
ON public.subscription_discounts(subscription_id);

-- Payments
CREATE INDEX idx_payments_invoice
ON public.payments(invoice_id);

CREATE INDEX idx_payments_customer
ON public.payments(customer_id);

CREATE INDEX idx_payments_status
ON public.payments(payment_status);

-- Payment transactions
CREATE INDEX idx_payment_transactions_payment
ON public.payment_transactions(payment_id);


-- UPDATED_AT AUTOMATION

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


CREATE TRIGGER set_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_products_updated_at
BEFORE UPDATE ON public.products
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_product_variants_updated_at
BEFORE UPDATE ON public.product_variants
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_subscription_plans_updated_at
BEFORE UPDATE ON public.subscription_plans
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_subscriptions_updated_at
BEFORE UPDATE ON public.subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_subscription_items_updated_at
BEFORE UPDATE ON public.subscription_items
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_invoices_updated_at
BEFORE UPDATE ON public.invoices
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_discounts_updated_at
BEFORE UPDATE ON public.discounts
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_payments_updated_at
BEFORE UPDATE ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();