-- CORE DATABASE SCHEMA

-- 1. PRODUCTS
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. PRODUCT VARIANTS
CREATE TABLE product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    product_id UUID NOT NULL
        REFERENCES products(id) ON DELETE CASCADE,

    name TEXT NOT NULL,
    sku TEXT UNIQUE,
    price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. SUBSCRIPTION PLANS
CREATE TABLE subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,
    description TEXT,

    price NUMERIC(12,2) NOT NULL CHECK (price >= 0),

    billing_interval TEXT NOT NULL
        CHECK (billing_interval IN ('day', 'week', 'month', 'year')),

    interval_count INTEGER NOT NULL DEFAULT 1
        CHECK (interval_count > 0),

    currency TEXT NOT NULL DEFAULT 'INR',
    is_active BOOLEAN DEFAULT TRUE,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. SUBSCRIPTIONS
CREATE TABLE subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    customer_id UUID NOT NULL
        REFERENCES auth.users(id),

    plan_id UUID NOT NULL
        REFERENCES subscription_plans(id),

    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'active',
            'paused',
            'cancelled',
            'expired'
        )),

    start_date TIMESTAMPTZ,
    current_period_start TIMESTAMPTZ,
    current_period_end TIMESTAMPTZ,
    next_billing_date TIMESTAMPTZ,

    cancelled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. SUBSCRIPTION ITEMS
CREATE TABLE subscription_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    subscription_id UUID NOT NULL
        REFERENCES subscriptions(id) ON DELETE CASCADE,

    variant_id UUID NOT NULL
        REFERENCES product_variants(id),

    quantity INTEGER NOT NULL DEFAULT 1
        CHECK (quantity > 0),

    unit_price NUMERIC(12,2) NOT NULL
        CHECK (unit_price >= 0),

    created_at TIMESTAMPTZ DEFAULT NOW(),

    UNIQUE (subscription_id, variant_id)
);

-- 6. INVOICES
CREATE TABLE invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_number TEXT NOT NULL UNIQUE,

    subscription_id UUID NOT NULL
        REFERENCES subscriptions(id),

    customer_id UUID NOT NULL
        REFERENCES auth.users(id),

    billing_period_start DATE NOT NULL,
    billing_period_end DATE NOT NULL,

    subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    total NUMERIC(12,2) NOT NULL DEFAULT 0,
    amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0,

    currency TEXT NOT NULL DEFAULT 'INR',

    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (status IN (
            'draft',
            'unpaid',
            'partially_paid',
            'paid',
            'overdue',
            'cancelled'
        )),

    issue_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE,

    created_at TIMESTAMPTZ DEFAULT NOW(),

    CHECK (billing_period_end >= billing_period_start),
    CHECK (subtotal >= 0),
    CHECK (discount_amount >= 0),
    CHECK (tax_amount >= 0),
    CHECK (total >= 0),
    CHECK (amount_paid >= 0),
    CHECK (amount_paid <= total),

    -- Prevent duplicate invoices for the same period
    UNIQUE (
        subscription_id,
        billing_period_start,
        billing_period_end
    )
);

-- 7. INVOICE ITEMS
CREATE TABLE invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_id UUID NOT NULL
        REFERENCES invoices(id) ON DELETE CASCADE,

    description TEXT NOT NULL,

    quantity INTEGER NOT NULL CHECK (quantity > 0),

    unit_price NUMERIC(12,2) NOT NULL
        CHECK (unit_price >= 0),

    tax_rate NUMERIC(5,2) NOT NULL DEFAULT 0
        CHECK (tax_rate >= 0 AND tax_rate <= 100),

    line_subtotal NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
    line_total NUMERIC(12,2) NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- INDEXES

CREATE INDEX idx_subscriptions_customer
ON subscriptions(customer_id);

CREATE INDEX idx_subscriptions_status
ON subscriptions(status);

CREATE INDEX idx_subscriptions_billing_date
ON subscriptions(next_billing_date);

CREATE INDEX idx_subscription_items_subscription
ON subscription_items(subscription_id);

CREATE INDEX idx_invoices_customer
ON invoices(customer_id);

CREATE INDEX idx_invoices_subscription
ON invoices(subscription_id);

CREATE INDEX idx_invoices_status
ON invoices(status);

CREATE INDEX idx_invoice_items_invoice
ON invoice_items(invoice_id);

-- UPDATED_AT TRIGGER

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_subscriptions_updated_at
BEFORE UPDATE ON subscriptions
FOR EACH ROW
EXECUTE FUNCTION update_updated_at();