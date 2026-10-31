
-- 002_RLS_POLICIES.SQL

BEGIN;

-- ENABLE ROW LEVEL SECURITY

ALTER TABLE public.products
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.product_variants
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subscription_plans
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subscriptions
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.subscription_items
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.invoices
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.invoice_items
ENABLE ROW LEVEL SECURITY;


-- PUBLIC PRODUCT CATALOG

CREATE POLICY "Anyone can view active products"
ON public.products
FOR SELECT
TO anon, authenticated
USING (is_active = TRUE);


CREATE POLICY "Anyone can view active variants"
ON public.product_variants
FOR SELECT
TO anon, authenticated
USING (is_active = TRUE);


CREATE POLICY "Anyone can view active plans"
ON public.subscription_plans
FOR SELECT
TO anon, authenticated
USING (is_active = TRUE);


-- USER SUBSCRIPTIONS

CREATE POLICY "Users can view their own subscriptions"
ON public.subscriptions
FOR SELECT
TO authenticated
USING (
    customer_id = (SELECT auth.uid())
);


-- USER SUBSCRIPTION ITEMS

CREATE POLICY "Users can view their own subscription items"
ON public.subscription_items
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.subscriptions s
        WHERE s.id = subscription_items.subscription_id
        AND s.customer_id = (SELECT auth.uid())
    )
);


-- USER INVOICES

CREATE POLICY "Users can view their own invoices"
ON public.invoices
FOR SELECT
TO authenticated
USING (
    customer_id = (SELECT auth.uid())
);


-- USER INVOICE ITEMS

CREATE POLICY "Users can view their own invoice items"
ON public.invoice_items
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.invoices i
        WHERE i.id = invoice_items.invoice_id
        AND i.customer_id = (SELECT auth.uid())
    )
);

COMMIT;
