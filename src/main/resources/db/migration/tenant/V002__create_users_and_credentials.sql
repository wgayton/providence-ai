-- ============================================================================
-- V002: Create users, credentials, and user_profiles tables (tenant schema)
-- ============================================================================
-- PROV-109: Credential/Profile Separation Enforcement
--
-- Physical separation between credential data and profile data prevents
-- accidental leakage through API responses, logging, or serialization.
--
-- Structure:
--   users         → Identity anchor (minimal aggregate root)
--   credentials   → Authentication-only data (NEVER exposed in profile APIs)
--   user_profiles → Personal info (safe for API responses)
--
-- Join only by user_id FK — no bidirectional or composite joins.
-- ============================================================================

-- ===========================================
-- Users — Identity Anchor (Aggregate Root)
-- ===========================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- User lifecycle — references administered ref_user_statuses table
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING_VERIFICATION'
        REFERENCES ref_user_statuses(code),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_status ON users(status) WHERE status = 'ACTIVE';

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_users_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_users_updated_at();

-- ===========================================
-- Credentials — Login Data (NEVER in APIs)
-- ===========================================
-- SEPARATE from user_profiles to prevent accidental credential leakage.
-- Contains ONLY authentication-related data.
CREATE TABLE IF NOT EXISTS credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- Login identifier — must be a valid email address (unique within tenant)
    email VARCHAR(255) NOT NULL UNIQUE,

    -- bcrypt/argon2 password hash (NEVER store plaintext)
    password_hash VARCHAR(255) NOT NULL,

    -- OTP verification
    otp_secret VARCHAR(255),          -- TOTP secret for OTP generation
    otp_verified_at TIMESTAMPTZ,      -- NULL = not yet verified

    -- Brute-force protection
    failed_attempt_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,         -- NULL = not locked
    last_failed_at TIMESTAMPTZ,

    -- Password lifecycle
    password_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_credentials_email ON credentials(email);
CREATE INDEX idx_credentials_user_id ON credentials(user_id);
CREATE INDEX idx_credentials_locked ON credentials(user_id)
    WHERE locked_until IS NOT NULL AND locked_until > NOW();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_credentials_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_credentials_updated_at
    BEFORE UPDATE ON credentials
    FOR EACH ROW
    EXECUTE FUNCTION update_credentials_updated_at();

-- ===========================================
-- User Profiles — Personal Information
-- ===========================================
-- Profile information SEPARATE from credentials.
-- Safe to expose in API responses without risk of credential leakage.
CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- Identity
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    display_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),

    -- Preferences
    timezone VARCHAR(50) DEFAULT 'UTC',
    locale VARCHAR(10) DEFAULT 'en-US',

    -- Metadata
    bio TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_profiles_email ON user_profiles(email);
CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_user_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_user_profiles_updated_at();

-- ===========================================
-- Comments
-- ===========================================
COMMENT ON TABLE users IS
    'Identity anchor — aggregate root. Deliberately minimal: no credentials, no profile data.';

COMMENT ON TABLE credentials IS
    'Authentication-only data. NEVER exposed in profile APIs. Joined to users by user_id only.';

COMMENT ON TABLE user_profiles IS
    'Personal info safe for API responses. Physically separate from credentials to prevent leakage.';
