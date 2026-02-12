-- ============================================================================
-- V003: Create public.audit_log table
-- ============================================================================
-- Purpose: Immutable audit trail for compliance and security
-- Schema: public (audit events from all tenants)
-- Retention: NEVER delete (archive to cold storage after 7 years)
--
-- Requirements:
-- - Enterprise audit survivability (SOC 2, GDPR, HIPAA compliance)
-- - Immutable: NO UPDATE or DELETE operations allowed
-- - Complete: Log ALL privilege changes and financial transactions
-- - Traceable: Correlation ID for distributed request tracing
-- - Tamper-evident: Hash chain or append-only log verification
--
-- Audit event types:
-- - USER_REGISTERED, USER_ROLE_ASSIGNED, USER_SUSPENDED
-- - PROJECT_CREATED, PROJECT_ARCHIVED, PROJECT_DELETED
-- - FUND_TRANSFER_CREATED, BUDGET_APPROVED, PAYMENT_PROCESSED
-- - LEDGER_ENTRY_CREATED (financial transactions)
-- - API_KEY_CREATED, API_KEY_REVOKED
-- - ADMIN_ACCESS_GRANTED, ADMIN_ACCESS_REVOKED
--
-- Used by:
-- - Compliance audits (SOC 2, GDPR data access logs)
-- - Security forensics (who did what, when)
-- - Billing reconciliation (financial event replay)
-- - Customer support (debugging user issues)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.audit_log (
    -- Event identifier (UUID for global uniqueness)
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Tenant that owns this audit event
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,

    -- Event classification
    event_type VARCHAR(100) NOT NULL, -- e.g., 'USER_ROLE_ASSIGNED', 'FUND_TRANSFER_CREATED'

    -- Aggregate identification (what was changed)
    aggregate_type VARCHAR(100) NOT NULL, -- e.g., 'User', 'Project', 'FundTransfer'
    aggregate_id UUID NOT NULL, -- ID of the affected entity

    -- Actor who performed the action
    actor_id UUID NOT NULL, -- User ID or service account ID
    actor_type VARCHAR(50) NOT NULL DEFAULT 'USER', -- 'USER', 'SERVICE', 'SYSTEM'

    -- Timing (immutable timestamp)
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Distributed tracing
    correlation_id UUID NOT NULL, -- Trace ID from HTTP/gRPC request

    -- Network context for security analysis
    ip_address INET, -- Client IP address (IPv4 or IPv6)
    user_agent TEXT, -- HTTP User-Agent header

    -- Event payload (JSONB for flexible audit data)
    -- Before state: What the entity looked like before the change
    -- After state: What the entity looks like after the change
    -- Changes: Diff of what changed (for sensitive data, only log field names, not values)
    payload JSONB NOT NULL,

    -- Additional metadata
    metadata JSONB, -- Request ID, API version, client ID, etc.

    CONSTRAINT chk_event_type_uppercase CHECK (event_type ~ '^[A-Z_]+$'), -- UPPER_SNAKE_CASE
    CONSTRAINT chk_actor_type_valid CHECK (actor_type IN ('USER', 'SERVICE', 'SYSTEM', 'ANONYMOUS'))
);

-- ============================================================================
-- Indexes for audit queries
-- ============================================================================

-- Tenant-scoped audit history (most common query)
CREATE INDEX idx_audit_tenant_occurred ON public.audit_log(tenant_id, occurred_at DESC);

-- Aggregate history (e.g., "show all changes to Project X")
CREATE INDEX idx_audit_aggregate ON public.audit_log(tenant_id, aggregate_type, aggregate_id, occurred_at DESC);

-- Actor activity tracking (e.g., "what did User Y do?")
CREATE INDEX idx_audit_actor ON public.audit_log(tenant_id, actor_id, occurred_at DESC);

-- Event type filtering for compliance reports
CREATE INDEX idx_audit_event_type ON public.audit_log(event_type, occurred_at DESC);

-- Correlation ID for distributed tracing
CREATE INDEX idx_audit_correlation_id ON public.audit_log(correlation_id);

-- IP-based security analysis
CREATE INDEX idx_audit_ip_address ON public.audit_log(ip_address, occurred_at DESC)
    WHERE ip_address IS NOT NULL;

-- Recent audit events (hot partition)
CREATE INDEX idx_audit_recent ON public.audit_log(occurred_at DESC)
    WHERE occurred_at > NOW() - INTERVAL '30 days';

-- ============================================================================
-- Immutability enforcement: Prevent UPDATE and DELETE
-- ============================================================================

CREATE OR REPLACE FUNCTION prevent_audit_log_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit log is immutable. UPDATE and DELETE operations are prohibited. Event ID: %', OLD.id;
    RETURN NULL; -- Prevent operation
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_audit_update
    BEFORE UPDATE ON public.audit_log
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_log_modification();

CREATE TRIGGER trg_prevent_audit_delete
    BEFORE DELETE ON public.audit_log
    FOR EACH ROW
    EXECUTE FUNCTION prevent_audit_log_modification();

-- ============================================================================
-- Tamper-evident logging (optional, for high-security environments)
-- ============================================================================
-- Hash chain: Each audit event includes a hash of the previous event
-- This makes it impossible to tamper with audit logs without detection

-- ALTER TABLE public.audit_log ADD COLUMN previous_hash VARCHAR(64);
-- ALTER TABLE public.audit_log ADD COLUMN current_hash VARCHAR(64);

-- CREATE OR REPLACE FUNCTION compute_audit_hash()
-- RETURNS TRIGGER AS $$
-- DECLARE
--     prev_hash VARCHAR(64);
--     event_data TEXT;
-- BEGIN
--     -- Get hash of previous event
--     SELECT current_hash INTO prev_hash
--     FROM public.audit_log
--     WHERE tenant_id = NEW.tenant_id
--     ORDER BY occurred_at DESC
--     LIMIT 1;
--
--     -- Concatenate all audit fields
--     event_data := NEW.id || NEW.tenant_id || NEW.event_type ||
--                   NEW.aggregate_id || NEW.actor_id || NEW.occurred_at ||
--                   NEW.payload::text || COALESCE(prev_hash, '');
--
--     -- Compute SHA-256 hash
--     NEW.previous_hash := prev_hash;
--     NEW.current_hash := encode(digest(event_data, 'sha256'), 'hex');
--
--     RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE TRIGGER trg_audit_hash
--     BEFORE INSERT ON public.audit_log
--     FOR EACH ROW
--     EXECUTE FUNCTION compute_audit_hash();

-- ============================================================================
-- Partitioning strategy for long-term storage
-- ============================================================================
-- Audit logs grow indefinitely. Use partitioning for efficient archival.
-- Example: Partition by year for compliance with 7-year retention policies.

-- Enable partitioning (commented out by default)
-- ALTER TABLE public.audit_log PARTITION BY RANGE (occurred_at);

-- Create partitions (example for 2026-2033)
-- CREATE TABLE public.audit_log_2026 PARTITION OF public.audit_log
--     FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
-- CREATE TABLE public.audit_log_2027 PARTITION OF public.audit_log
--     FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');
-- ... continue for 7 years

-- ============================================================================
-- Archival strategy: Move old audit logs to cold storage
-- ============================================================================
-- After 7 years, archive to S3/Glacier or separate read-only database

-- Option 1: Export to Parquet files via pg_dump
-- pg_dump -t public.audit_log_2020 --format=custom > audit_2020.dump

-- Option 2: Export to S3 via COPY command (requires aws_s3 extension)
-- SELECT aws_s3.query_export_to_s3(
--     'SELECT * FROM public.audit_log WHERE occurred_at < ''2020-01-01''',
--     aws_commons.create_s3_uri('my-bucket', 'audit_logs/2020.parquet', 'us-east-1')
-- );

-- Option 3: Replicate to separate audit database via logical replication

-- ============================================================================
-- Retention policy: Never delete audit logs
-- ============================================================================
-- CRITICAL: Do NOT create automatic deletion jobs.
-- Audit logs must be retained for compliance (typically 7-10 years).
-- After retention period, archive to cold storage, but NEVER delete.

-- ❌ WRONG: DELETE FROM public.audit_log WHERE occurred_at < NOW() - INTERVAL '7 years';
-- ✅ RIGHT: Archive to S3/Glacier, then drop partition (keeps data accessible)

-- ============================================================================
-- Comments for database documentation
-- ============================================================================

COMMENT ON TABLE public.audit_log IS
    'Immutable audit trail for compliance and security. NEVER delete. Retention: 7+ years. Archive to cold storage after expiration.';

COMMENT ON COLUMN public.audit_log.id IS
    'Audit event identifier (UUID). Used for correlation with other systems.';

COMMENT ON COLUMN public.audit_log.tenant_id IS
    'Tenant that owns this audit event. Foreign key to public.tenants(id).';

COMMENT ON COLUMN public.audit_log.event_type IS
    'Event type in UPPER_SNAKE_CASE (e.g., USER_ROLE_ASSIGNED, FUND_TRANSFER_CREATED).';

COMMENT ON COLUMN public.audit_log.aggregate_type IS
    'Type of entity affected (e.g., User, Project, FundTransfer).';

COMMENT ON COLUMN public.audit_log.aggregate_id IS
    'ID of the affected entity. Used for aggregate-level audit history.';

COMMENT ON COLUMN public.audit_log.actor_id IS
    'User or service account that performed the action. Required for accountability.';

COMMENT ON COLUMN public.audit_log.actor_type IS
    'Type of actor: USER (human), SERVICE (API key), SYSTEM (background job), ANONYMOUS (unauthenticated).';

COMMENT ON COLUMN public.audit_log.occurred_at IS
    'Immutable timestamp when event occurred. Used for chronological ordering and compliance reporting.';

COMMENT ON COLUMN public.audit_log.correlation_id IS
    'Distributed trace ID. Correlates this audit event with outbox events and application logs.';

COMMENT ON COLUMN public.audit_log.ip_address IS
    'Client IP address (IPv4 or IPv6). Used for security analysis and fraud detection.';

COMMENT ON COLUMN public.audit_log.user_agent IS
    'HTTP User-Agent header. Used for device tracking and anomaly detection.';

COMMENT ON COLUMN public.audit_log.payload IS
    'Event payload as JSONB. Contains before/after states for sensitive operations. For PII, log field names only, not values.';

COMMENT ON COLUMN public.audit_log.metadata IS
    'Additional context: request ID, API version, client ID, OAuth scope, etc.';

-- ============================================================================
-- Sample data for development (commented out for production)
-- ============================================================================

-- INSERT INTO public.audit_log (
--     id, tenant_id, event_type, aggregate_type, aggregate_id,
--     actor_id, actor_type, occurred_at, correlation_id, ip_address, payload
-- ) VALUES (
--     gen_random_uuid(),
--     '11111111-1111-1111-1111-111111111111', -- acme tenant
--     'USER_ROLE_ASSIGNED',
--     'User',
--     gen_random_uuid(),
--     gen_random_uuid(), -- admin user
--     'USER',
--     NOW(),
--     gen_random_uuid(),
--     '192.168.1.100'::inet,
--     jsonb_build_object(
--         'userId', gen_random_uuid(),
--         'role', 'ADMIN',
--         'before', 'MEMBER',
--         'after', 'ADMIN',
--         'reason', 'Promotion to administrator'
--     )
-- );
