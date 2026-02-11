-- ============================================================================
-- V001: Create public.tenants table
-- ============================================================================
-- Purpose: Central registry for all tenants in the multi-tenant SaaS platform
-- Schema: public (visible to all tenants)
-- Isolation: Each tenant gets a dedicated PostgreSQL schema (t_<slug>)
--
-- This table is the single source of truth for:
-- - Tenant identification (id, slug)
-- - Schema mapping (slug → schema_name)
-- - Tenant lifecycle (status: ACTIVE, SUSPENDED, DELETED)
-- - Audit trail (created_at, updated_at)
--
-- Used by:
-- - TenantResolutionFilter: Resolve subdomain → tenant_id
-- - TenantMigrationManager: Discover all tenants for Flyway migrations
-- - Hibernate MultiTenantConnectionProvider: Map tenant_id → schema_name
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.tenants (
    -- Primary identifier (UUID for global uniqueness across systems)
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- URL-safe slug for subdomain routing (e.g., 'acme' → acme.api.providence.ai)
    -- Must be unique, lowercase, alphanumeric + hyphens only
    -- Max 50 chars to fit in DNS label limits (63 chars)
    slug VARCHAR(50) NOT NULL UNIQUE,

    -- Human-readable tenant name (e.g., 'Acme Corporation')
    name VARCHAR(100) NOT NULL,

    -- PostgreSQL schema name where tenant's data resides (e.g., 't_acme')
    -- Pattern: 't_<slug>' (max 63 chars for PostgreSQL identifier limit)
    schema_name VARCHAR(63) NOT NULL UNIQUE,

    -- Tenant lifecycle status
    -- ACTIVE: Normal operations, all features available
    -- SUSPENDED: Temporarily disabled (e.g., payment failure), read-only access
    -- DELETED: Soft-deleted, schema preserved for compliance period
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('ACTIVE', 'SUSPENDED', 'DELETED')),

    -- Audit timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Business metadata (optional)
    subscription_tier VARCHAR(50), -- e.g., 'FREE', 'PROFESSIONAL', 'ENTERPRISE'
    max_users INT, -- User limit for this tenant
    max_storage_gb INT, -- Storage limit in GB

    -- Contact information for account management
    contact_email VARCHAR(255),
    contact_phone VARCHAR(50)
);

-- ============================================================================
-- Indexes for performance
-- ============================================================================

-- Fast slug lookup for subdomain resolution
CREATE INDEX idx_tenants_slug ON public.tenants(slug)
    WHERE status = 'ACTIVE'; -- Partial index: only active tenants

-- Fast status filtering for admin dashboards
CREATE INDEX idx_tenants_status ON public.tenants(status);

-- Fast schema_name lookup for Hibernate tenant resolver
CREATE INDEX idx_tenants_schema_name ON public.tenants(schema_name)
    WHERE status = 'ACTIVE';

-- ============================================================================
-- Constraints and validation
-- ============================================================================

-- Ensure slug follows naming conventions
ALTER TABLE public.tenants
    ADD CONSTRAINT chk_slug_format
    CHECK (slug ~ '^[a-z0-9][a-z0-9-]*[a-z0-9]$'); -- Start/end with alphanumeric, hyphens allowed

-- Ensure schema_name follows pattern
ALTER TABLE public.tenants
    ADD CONSTRAINT chk_schema_name_format
    CHECK (schema_name ~ '^t_[a-z0-9][a-z0-9_]*$'); -- Must start with 't_'

-- ============================================================================
-- Trigger: Auto-update updated_at timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_tenants_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON public.tenants
    FOR EACH ROW
    EXECUTE FUNCTION update_tenants_updated_at();

-- ============================================================================
-- Row-Level Security (RLS) - Future-proofing
-- ============================================================================
-- Note: Public schema tables are not subject to tenant isolation.
-- RLS can be enabled if we need to restrict admin access to specific tenants.

-- Enable RLS (commented out by default)
-- ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

-- Allow superusers to see all tenants
-- CREATE POLICY tenants_superuser_policy ON public.tenants
--     FOR ALL TO current_user
--     USING (current_setting('app.is_superuser', true)::boolean = true);

-- ============================================================================
-- Comments for database documentation
-- ============================================================================

COMMENT ON TABLE public.tenants IS
    'Central registry for all tenants in the multi-tenant SaaS platform. Each tenant has a dedicated PostgreSQL schema (t_<slug>) for complete data isolation.';

COMMENT ON COLUMN public.tenants.id IS
    'Primary identifier (UUID). Used in JWT claims, foreign keys, and audit logs.';

COMMENT ON COLUMN public.tenants.slug IS
    'URL-safe identifier for subdomain routing (e.g., acme.api.providence.ai). Must be unique and immutable.';

COMMENT ON COLUMN public.tenants.schema_name IS
    'PostgreSQL schema where tenant data resides (e.g., t_acme). Set via SET search_path in Hibernate connection provider.';

COMMENT ON COLUMN public.tenants.status IS
    'Tenant lifecycle: ACTIVE (normal), SUSPENDED (temporary disable), DELETED (soft-delete).';

COMMENT ON COLUMN public.tenants.subscription_tier IS
    'Subscription plan: FREE, PROFESSIONAL, ENTERPRISE. Used for feature gating and rate limiting.';

-- ============================================================================
-- Sample data for development (commented out for production)
-- ============================================================================

-- INSERT INTO public.tenants (id, slug, name, schema_name, status, subscription_tier)
-- VALUES
--     ('11111111-1111-1111-1111-111111111111', 'acme', 'Acme Corporation', 't_acme', 'ACTIVE', 'ENTERPRISE'),
--     ('22222222-2222-2222-2222-222222222222', 'globex', 'Globex Corporation', 't_globex', 'ACTIVE', 'PROFESSIONAL'),
--     ('33333333-3333-3333-3333-333333333333', 'initech', 'Initech', 't_initech', 'SUSPENDED', 'FREE');
