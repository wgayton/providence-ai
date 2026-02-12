-- ============================================================================
-- V006: Create public.ref_feature_levels table
-- ============================================================================
-- Purpose: Administered reference table for subscription feature levels
-- Schema: public (shared across all tenants)
-- Controls rate limits, user counts, and feature depth per tier
--
-- Used by:
-- - public.tenant_product_features: defines what level each tenant has
-- - Spring Security: authority format FEATURE_<KEY>_<LEVEL>
-- - FeatureHierarchyVoter: ENTERPRISE > MAX > PRO > STANDARD
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.ref_feature_levels (
    code VARCHAR(20) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default feature levels (ordered by capability)
INSERT INTO public.ref_feature_levels (code, label, description, display_order)
VALUES
    ('STANDARD', 'Standard', 'Base tier with core functionality', 1),
    ('PRO', 'Professional', 'Enhanced tier with advanced features and higher limits', 2),
    ('MAX', 'Max', 'Premium tier with maximum feature depth', 3),
    ('ENTERPRISE', 'Enterprise', 'Full platform access with unlimited capacity', 4)
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.ref_feature_levels IS
    'Administered reference table for subscription feature levels. Controls the hierarchy: STANDARD < PRO < MAX < ENTERPRISE.';

COMMENT ON COLUMN public.ref_feature_levels.code IS
    'Unique feature level code (e.g., STANDARD, PRO, MAX, ENTERPRISE). Used in FEATURE_<KEY>_<LEVEL> authority format.';

COMMENT ON COLUMN public.ref_feature_levels.display_order IS
    'Numeric ordering for hierarchy comparison. Higher = more capable.';

COMMENT ON COLUMN public.ref_feature_levels.active IS
    'Whether this level is currently available for assignment. FALSE = deprecated but existing references preserved.';
