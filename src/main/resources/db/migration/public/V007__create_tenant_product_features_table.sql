-- ============================================================================
-- V007: Create public.tenant_product_features table
-- ============================================================================
-- Purpose: Defines what product features each tenant has enabled at their
--          subscription tier level
-- Schema: public (cross-tenant infrastructure)
--
-- Used by:
-- - Spring Security authority resolution: FEATURE_<key>_<level>
-- - SystemTenantProvisioner: seeds ENTERPRISE features for system tenant
-- - Subscription management: upgrade/downgrade feature levels
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tenant_product_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,

    -- Feature identifier (e.g., 'PROJECT', 'FINANCE', 'RESOURCE', 'HUMAN')
    feature_key VARCHAR(100) NOT NULL,

    -- Subscription level — references administered ref_feature_levels table
    feature_level VARCHAR(20) NOT NULL
        REFERENCES public.ref_feature_levels(code),

    -- Whether this feature is currently active for the tenant
    enabled BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Each tenant has at most one entry per feature key
    CONSTRAINT uq_tenant_feature UNIQUE (tenant_id, feature_key),

    -- Feature key must be UPPER_SNAKE_CASE
    CONSTRAINT chk_feature_key_format CHECK (feature_key ~ '^[A-Z][A-Z0-9_]*$')
);

-- ============================================================================
-- Indexes
-- ============================================================================

-- Fast lookup of active features for a tenant (authority resolution)
CREATE INDEX idx_tenant_features_tenant ON public.tenant_product_features(tenant_id)
    WHERE enabled = TRUE;

-- ============================================================================
-- Trigger: Auto-update updated_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_tenant_product_features_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tenant_product_features_updated_at
    BEFORE UPDATE ON public.tenant_product_features
    FOR EACH ROW
    EXECUTE FUNCTION update_tenant_product_features_updated_at();

-- ============================================================================
-- Comments
-- ============================================================================

COMMENT ON TABLE public.tenant_product_features IS
    'Defines what product features each tenant has enabled. Used for Spring Security authority resolution: FEATURE_<key>_<level>.';

COMMENT ON COLUMN public.tenant_product_features.feature_key IS
    'Feature identifier in UPPER_SNAKE_CASE (e.g., PROJECT, FINANCE, RESOURCE, HUMAN).';

COMMENT ON COLUMN public.tenant_product_features.feature_level IS
    'Subscription level for this feature. References ref_feature_levels (STANDARD, PRO, MAX, ENTERPRISE).';
