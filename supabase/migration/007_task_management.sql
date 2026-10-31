-- =========================================================
-- 007_tax_management.sql
-- Admin-only tax rule management
-- =========================================================


-- =========================================================
-- 1. CREATE TAX RULE
-- =========================================================

CREATE OR REPLACE FUNCTION public.create_tax_rule(
    p_name TEXT,
    p_rate NUMERIC,
    p_product_id UUID DEFAULT NULL,
    p_valid_from DATE DEFAULT CURRENT_DATE,
    p_valid_until DATE DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tax_id UUID;
BEGIN
    -- Admin authorization
    IF auth.uid() IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only admins can create tax rules'
            USING ERRCODE = '42501';
    END IF;

    -- Validate tax name
    IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
        RAISE EXCEPTION 'Tax name cannot be empty';
    END IF;

    -- Validate tax rate
    IF p_rate IS NULL OR p_rate < 0 OR p_rate > 100 THEN
        RAISE EXCEPTION 'Tax rate must be between 0 and 100';
    END IF;

    -- Validate start date
    IF p_valid_from IS NULL THEN
        RAISE EXCEPTION 'Tax valid_from date is required';
    END IF;

    -- Validate date range
    IF p_valid_until IS NOT NULL
       AND p_valid_until < p_valid_from THEN
        RAISE EXCEPTION 'valid_until cannot be earlier than valid_from';
    END IF;

    INSERT INTO public.taxes (
        name,
        rate,
        product_id,
        valid_from,
        valid_until,
        is_active
    )
    VALUES (
        TRIM(p_name),
        p_rate,
        p_product_id,
        p_valid_from,
        p_valid_until,
        TRUE
    )
    RETURNING id INTO v_tax_id;

    RETURN v_tax_id;
END;
$$;


-- =========================================================
-- 2. UPDATE TAX RULE
-- =========================================================

CREATE OR REPLACE FUNCTION public.update_tax_rule(
    p_tax_id UUID,
    p_name TEXT,
    p_rate NUMERIC,
    p_product_id UUID,
    p_valid_from DATE,
    p_valid_until DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tax_id UUID;
BEGIN
    -- Admin authorization
    IF auth.uid() IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only admins can update tax rules'
            USING ERRCODE = '42501';
    END IF;

    -- Validate tax ID
    IF p_tax_id IS NULL THEN
        RAISE EXCEPTION 'Tax ID is required';
    END IF;

    -- Validate tax name
    IF p_name IS NULL OR LENGTH(TRIM(p_name)) = 0 THEN
        RAISE EXCEPTION 'Tax name cannot be empty';
    END IF;

    -- Validate tax rate
    IF p_rate IS NULL OR p_rate < 0 OR p_rate > 100 THEN
        RAISE EXCEPTION 'Tax rate must be between 0 and 100';
    END IF;

    -- Validate start date
    IF p_valid_from IS NULL THEN
        RAISE EXCEPTION 'Tax valid_from date is required';
    END IF;

    -- Validate date range
    IF p_valid_until IS NOT NULL
       AND p_valid_until < p_valid_from THEN
        RAISE EXCEPTION 'valid_until cannot be earlier than valid_from';
    END IF;

    UPDATE public.taxes
    SET
        name = TRIM(p_name),
        rate = p_rate,
        product_id = p_product_id,
        valid_from = p_valid_from,
        valid_until = p_valid_until,
        updated_at = NOW()
    WHERE id = p_tax_id
    RETURNING id INTO v_tax_id;

    IF v_tax_id IS NULL THEN
        RAISE EXCEPTION 'Tax rule not found';
    END IF;

    RETURN v_tax_id;
END;
$$;


-- =========================================================
-- 3. ACTIVATE / DEACTIVATE TAX RULE
-- =========================================================

CREATE OR REPLACE FUNCTION public.set_tax_rule_active(
    p_tax_id UUID,
    p_is_active BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_tax_id UUID;
BEGIN
    -- Admin authorization
    IF auth.uid() IS NULL OR NOT public.is_admin() THEN
        RAISE EXCEPTION 'Only admins can change tax rule status'
            USING ERRCODE = '42501';
    END IF;

    -- Validate inputs
    IF p_tax_id IS NULL THEN
        RAISE EXCEPTION 'Tax ID is required';
    END IF;

    IF p_is_active IS NULL THEN
        RAISE EXCEPTION 'is_active value is required';
    END IF;

    UPDATE public.taxes
    SET
        is_active = p_is_active,
        updated_at = NOW()
    WHERE id = p_tax_id
    RETURNING id INTO v_tax_id;

    IF v_tax_id IS NULL THEN
        RAISE EXCEPTION 'Tax rule not found';
    END IF;

    RETURN v_tax_id;
END;
$$;


-- =========================================================
-- 4. FUNCTION PERMISSIONS
-- =========================================================

REVOKE ALL ON FUNCTION public.create_tax_rule(
    TEXT, NUMERIC, UUID, DATE, DATE
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.update_tax_rule(
    UUID, TEXT, NUMERIC, UUID, DATE, DATE
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.set_tax_rule_active(
    UUID, BOOLEAN
) FROM PUBLIC;


GRANT EXECUTE ON FUNCTION public.create_tax_rule(
    TEXT, NUMERIC, UUID, DATE, DATE
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.update_tax_rule(
    UUID, TEXT, NUMERIC, UUID, DATE, DATE
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.set_tax_rule_active(
    UUID, BOOLEAN
) TO authenticated;