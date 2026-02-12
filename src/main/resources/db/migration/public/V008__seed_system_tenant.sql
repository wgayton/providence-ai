-- ============================================================================
-- V008: Seed default System tenant and ENTERPRISE product features
-- ============================================================================
-- Purpose: Provisions the default "System" tenant used for:
--          - Internal platform operations
--          - Integration test baseline
--          - ENTERPRISE feature reference
-- Schema: public
--
-- Idempotent: ON CONFLICT DO NOTHING prevents duplicates on restart
--
-- Related: SystemTenantProvisioner.java creates the t_system schema and
--          runs tenant migrations after this seed completes.
-- ============================================================================

-- System tenant: default internal tenant (slug = 'system')
INSERT INTO public.tenants (id, slug, name, schema_name, status, subscription_tier, max_users)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'system',
    'System',
    't_system',
    'ACTIVE',
    'ENTERPRISE',
    -1  -- unlimited users
) ON CONFLICT (slug) DO NOTHING;

-- ============================================================================
-- Seed ENTERPRISE-level product features for System tenant
-- ============================================================================
-- All platform features enabled at ENTERPRISE level

INSERT INTO public.tenant_product_features (tenant_id, feature_key, feature_level, enabled)
VALUES
    ('00000000-0000-0000-0000-000000000000', 'PROJECT', 'ENTERPRISE', TRUE),
    ('00000000-0000-0000-0000-000000000000', 'FINANCE', 'ENTERPRISE', TRUE),
    ('00000000-0000-0000-0000-000000000000', 'RESOURCE', 'ENTERPRISE', TRUE),
    ('00000000-0000-0000-0000-000000000000', 'HUMAN', 'ENTERPRISE', TRUE)
ON CONFLICT (tenant_id, feature_key) DO NOTHING;
