-- ============================================================================
-- V001: Create tenant-schema reference tables
-- ============================================================================
-- Purpose: Administered reference tables for tenant-scoped enum-like values
-- Schema: t_<tenant> (applied to every tenant schema)
--
-- Tables created:
-- - ref_user_statuses: User lifecycle states
-- - ref_tenant_roles: Tenant-level RBAC roles
-- - ref_group_statuses: Group lifecycle states
-- - ref_alert_types: Security alert classifications
--
-- Pattern: Each table follows the standard reference table structure:
--   code (PK), label, description, display_order, active, created_at
-- ============================================================================

-- ============================================================================
-- User Statuses Reference
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref_user_statuses (
    code VARCHAR(30) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_user_statuses (code, label, description, display_order)
VALUES
    ('PENDING_VERIFICATION', 'Pending Verification', 'Registered, awaiting OTP verification', 1),
    ('ACTIVE', 'Active', 'Verified and able to login', 2),
    ('SUSPENDED', 'Suspended', 'Disabled by administrator', 3),
    ('DEACTIVATED', 'Deactivated', 'Self-deactivated by user', 4)
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE ref_user_statuses IS
    'Administered reference table for user lifecycle statuses. FK target for users.status.';

-- ============================================================================
-- Tenant Roles Reference
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref_tenant_roles (
    code VARCHAR(50) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_tenant_roles (code, label, description, display_order)
VALUES
    ('ROLE_OWNER', 'Owner', 'Full tenant control including termination', 1),
    ('ROLE_ADMIN', 'Administrator', 'User management and configuration', 2),
    ('ROLE_USER', 'User', 'Standard authenticated user', 3)
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE ref_tenant_roles IS
    'Administered reference table for tenant-level user roles. ROLE_ prefix follows Spring Security convention.';

-- ============================================================================
-- Group Statuses Reference
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref_group_statuses (
    code VARCHAR(20) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_group_statuses (code, label, description, display_order)
VALUES
    ('ACTIVE', 'Active', 'Group is operational', 1),
    ('ARCHIVED', 'Archived', 'Group is read-only and no longer active', 2)
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE ref_group_statuses IS
    'Administered reference table for group lifecycle statuses. FK target for groups.status.';

-- ============================================================================
-- Alert Types Reference
-- ============================================================================

CREATE TABLE IF NOT EXISTS ref_alert_types (
    code VARCHAR(50) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_alert_types (code, label, description, display_order)
VALUES
    ('BRUTE_FORCE_DETECTED', 'Brute Force Detected', '3 failed login attempts on the account', 1),
    ('PASSWORD_CHANGED', 'Password Changed', 'Account password was changed', 2),
    ('NEW_DEVICE_LOGIN', 'New Device Login', 'Login from a previously unrecognized device', 3),
    ('ACCOUNT_LOCKED', 'Account Locked', 'Account locked due to failed login attempts', 4),
    ('ACCOUNT_UNLOCKED', 'Account Unlocked', 'Account unlocked after cooldown period expired', 5)
ON CONFLICT (code) DO NOTHING;

COMMENT ON TABLE ref_alert_types IS
    'Administered reference table for security alert classifications. FK target for security_alerts.alert_type.';
