-- ============================================================================
-- V003: Create OTP verifications table (tenant schema)
-- ============================================================================
-- Supports the OTP verification lifecycle for sensitive operations
-- (password change, registration confirmation, etc.)
--
-- Flow:
--   1. Operation initiated → OTP generated → row inserted (status PENDING)
--   2. OTP delivered to user via email/SMS (PROV-110)
--   3. User submits OTP → verified → status changes to VERIFIED
--   4. Operation completes → status changes to CONSUMED
--   5. Expired OTPs cleaned up by scheduled job
-- ============================================================================

CREATE TABLE IF NOT EXISTS otp_verifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Operation context
    operation_type VARCHAR(50) NOT NULL,   -- PASSWORD_CHANGE, REGISTRATION, etc.

    -- OTP storage (BCrypt hash — plain OTP never stored)
    otp_hash VARCHAR(255) NOT NULL,

    -- Pending operation payload (e.g., new password hash for PASSWORD_CHANGE)
    payload JSONB,

    -- Lifecycle
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,              -- NULL until OTP verified
    consumed_at TIMESTAMPTZ,              -- NULL until operation completed

    -- Abuse prevention
    attempt_count INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 5,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_verifications_user_op ON otp_verifications(user_id, operation_type)
    WHERE status = 'PENDING';
CREATE INDEX idx_otp_verifications_expires ON otp_verifications(expires_at)
    WHERE status = 'PENDING';

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_otp_verifications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_otp_verifications_updated_at
    BEFORE UPDATE ON otp_verifications
    FOR EACH ROW
    EXECUTE FUNCTION update_otp_verifications_updated_at();

COMMENT ON TABLE otp_verifications IS
    'Pending OTP verifications for sensitive operations. OTP is BCrypt-hashed. Expires after 5 minutes.';
