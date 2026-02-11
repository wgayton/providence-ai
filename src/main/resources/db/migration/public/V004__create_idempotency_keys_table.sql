-- ============================================================================
-- V004: Create public.idempotency_keys table
-- ============================================================================
-- Purpose: Universal idempotency enforcement for all state-changing operations
-- Schema: public (idempotency keys from all tenants)
-- Pattern: Client sends idempotency key → Server checks cache → Return cached result or execute
--
-- Mandate (from CLAUDE.md Section 25):
-- ALL state-changing REST and gRPC endpoints MUST enforce idempotency:
-- - REST: Require Idempotency-Key header for POST/PUT/PATCH/DELETE
-- - gRPC: Require idempotency-key metadata for all mutations
--
-- Benefits:
-- - Network reliability: Retries safe (no duplicate charges, double-creates, etc.)
-- - Mobile-friendly: Handles flaky connections and aggressive retry clients
-- - Financial correctness: Fund transfers are idempotent (critical!)
-- - Simplicity: No custom idempotency logic per endpoint
--
-- Idempotency key format:
-- - Client-generated UUIDv4 (e.g., 550e8400-e29b-41d4-a716-446655440000)
-- - Must be unique per (tenant_id, principal_id, command_name)
-- - Reusable across different commands (same key for "CreateProject" and "TransferFunds" is OK)
--
-- Retention:
-- - Keys expire after 24 hours (configurable)
-- - Cleanup job runs daily to delete expired keys
--
-- Used by:
-- - IdempotencyFilter (REST): Intercepts all POST/PUT/PATCH/DELETE
-- - GrpcIdempotencyInterceptor: Intercepts all gRPC mutations
-- - IdempotencyService: getCachedResponse(), cacheResponse()
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.idempotency_keys (
    -- Composite primary key: (tenant, principal, command, key)
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    principal_id UUID NOT NULL, -- User ID or service account ID
    command_name VARCHAR(100) NOT NULL, -- e.g., 'POST_/api/projects', 'CreateProject' (gRPC)
    idempotency_key VARCHAR(64) NOT NULL, -- Client-provided UUID

    -- Timing
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours',

    -- Cached response (for idempotent replay)
    -- For REST: HTTP status code + body
    -- For gRPC: gRPC status code + serialized protobuf response
    response_payload JSONB,

    -- Metadata for debugging
    request_hash VARCHAR(64), -- SHA-256 hash of request body (verify replays are identical)
    response_hash VARCHAR(64), -- SHA-256 hash of response (detect non-deterministic responses)

    PRIMARY KEY (tenant_id, principal_id, command_name, idempotency_key)
);

-- ============================================================================
-- Indexes for idempotency lookups
-- ============================================================================

-- Fast lookup for IdempotencyService.getCachedResponse()
-- (Primary key already creates index, but explicit for clarity)
-- CREATE INDEX idx_idempotency_lookup ON public.idempotency_keys(tenant_id, principal_id, command_name, idempotency_key);

-- Expiration cleanup (find expired keys to delete)
CREATE INDEX idx_idempotency_expires_at ON public.idempotency_keys(expires_at)
    WHERE expires_at < NOW(); -- Partial index: only expired keys

-- Recent keys for monitoring dashboards
CREATE INDEX idx_idempotency_created_at ON public.idempotency_keys(created_at DESC);

-- Principal activity tracking (optional, for abuse detection)
CREATE INDEX idx_idempotency_principal ON public.idempotency_keys(principal_id, created_at DESC);

-- ============================================================================
-- Automatic expiration cleanup
-- ============================================================================
-- Option 1: Manual cleanup job (via cron or scheduled task)
-- Run daily at 2 AM:
-- DELETE FROM public.idempotency_keys WHERE expires_at < NOW();

-- Option 2: Automatic cleanup via pg_cron extension
-- Requires: CREATE EXTENSION pg_cron;
-- SELECT cron.schedule('cleanup-idempotency-keys', '0 2 * * *', $$
--     DELETE FROM public.idempotency_keys WHERE expires_at < NOW()
-- $$);

-- Option 3: TTL-based cleanup via PostgreSQL 15+ (requires partitioning)
-- See partitioning section below

-- ============================================================================
-- Partitioning strategy (optional, for high-volume systems)
-- ============================================================================
-- For systems with millions of requests/day, partition by created_at
-- This enables efficient range-based expiration cleanup

-- Enable partitioning (commented out by default)
-- ALTER TABLE public.idempotency_keys PARTITION BY RANGE (created_at);

-- Create daily partitions (automate with pg_partman or custom job)
-- CREATE TABLE public.idempotency_keys_2026_02_11 PARTITION OF public.idempotency_keys
--     FOR VALUES FROM ('2026-02-11 00:00:00+00') TO ('2026-02-12 00:00:00+00');

-- DROP old partitions instead of DELETE (much faster)
-- DROP TABLE public.idempotency_keys_2026_01_15; -- Drops all keys from Jan 15

-- ============================================================================
-- Duplicate request detection: Verify request body hash
-- ============================================================================
-- To catch non-idempotent replays (same key, different request body):

CREATE OR REPLACE FUNCTION check_idempotency_request_hash()
RETURNS TRIGGER AS $$
BEGIN
    -- If key exists with different request_hash, warn
    IF NEW.request_hash IS NOT NULL THEN
        PERFORM 1 FROM public.idempotency_keys
        WHERE tenant_id = NEW.tenant_id
          AND principal_id = NEW.principal_id
          AND command_name = NEW.command_name
          AND idempotency_key = NEW.idempotency_key
          AND request_hash != NEW.request_hash;

        IF FOUND THEN
            RAISE WARNING 'Idempotency key reused with different request body. Key: %, Command: %',
                NEW.idempotency_key, NEW.command_name;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_request_hash
    BEFORE INSERT ON public.idempotency_keys
    FOR EACH ROW
    EXECUTE FUNCTION check_idempotency_request_hash();

-- ============================================================================
-- Non-deterministic response detection (optional)
-- ============================================================================
-- If the same request produces different responses, log a warning

-- CREATE OR REPLACE FUNCTION detect_non_deterministic_response()
-- RETURNS TRIGGER AS $$
-- DECLARE
--     existing_hash VARCHAR(64);
-- BEGIN
--     IF NEW.response_hash IS NOT NULL THEN
--         SELECT response_hash INTO existing_hash
--         FROM public.idempotency_keys
--         WHERE tenant_id = NEW.tenant_id
--           AND principal_id = NEW.principal_id
--           AND command_name = NEW.command_name
--           AND idempotency_key = NEW.idempotency_key
--         LIMIT 1;
--
--         IF existing_hash IS NOT NULL AND existing_hash != NEW.response_hash THEN
--             RAISE WARNING 'Non-deterministic response detected! Key: %, Command: %, Expected hash: %, Got: %',
--                 NEW.idempotency_key, NEW.command_name, existing_hash, NEW.response_hash;
--         END IF;
--     END IF;
--
--     RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE TRIGGER trg_detect_non_deterministic
--     BEFORE UPDATE ON public.idempotency_keys
--     FOR EACH ROW
--     EXECUTE FUNCTION detect_non_deterministic_response();

-- ============================================================================
-- Metrics and monitoring
-- ============================================================================
-- Track idempotency key usage for operational visibility

-- CREATE TABLE public.idempotency_metrics (
--     tenant_id UUID NOT NULL,
--     command_name VARCHAR(100) NOT NULL,
--     date DATE NOT NULL DEFAULT CURRENT_DATE,
--     total_requests BIGINT DEFAULT 0,
--     cached_responses BIGINT DEFAULT 0, -- Idempotent replays
--     cache_hit_rate NUMERIC(5, 2), -- Percentage
--     PRIMARY KEY (tenant_id, command_name, date)
-- );

-- ============================================================================
-- Comments for database documentation
-- ============================================================================

COMMENT ON TABLE public.idempotency_keys IS
    'Universal idempotency enforcement for all state-changing operations. Caches responses for 24 hours. Prevents duplicate charges, double-creates, and retry storms.';

COMMENT ON COLUMN public.idempotency_keys.tenant_id IS
    'Tenant that owns this idempotency key. Foreign key to public.tenants(id).';

COMMENT ON COLUMN public.idempotency_keys.principal_id IS
    'User or service account that initiated the request. Ensures keys are scoped per actor.';

COMMENT ON COLUMN public.idempotency_keys.command_name IS
    'Command identifier. For REST: HTTP_METHOD + path (e.g., POST_/api/projects). For gRPC: full method name (e.g., providence.project.v1.ProjectService/CreateProject).';

COMMENT ON COLUMN public.idempotency_keys.idempotency_key IS
    'Client-provided UUIDv4. Must be unique per (tenant_id, principal_id, command_name). Typically: Idempotency-Key header (REST) or idempotency-key metadata (gRPC).';

COMMENT ON COLUMN public.idempotency_keys.created_at IS
    'Timestamp when key was first used. Used for expiration calculation.';

COMMENT ON COLUMN public.idempotency_keys.expires_at IS
    'Expiration timestamp (default: 24 hours after created_at). Expired keys are deleted by cleanup job.';

COMMENT ON COLUMN public.idempotency_keys.response_payload IS
    'Cached response as JSONB. For REST: {"statusCode": 201, "body": {...}}. For gRPC: {"status": "OK", "response": {...}}.';

COMMENT ON COLUMN public.idempotency_keys.request_hash IS
    'SHA-256 hash of request body. Used to detect non-idempotent replays (same key, different request).';

COMMENT ON COLUMN public.idempotency_keys.response_hash IS
    'SHA-256 hash of response. Used to detect non-deterministic responses (same request, different response).';

-- ============================================================================
-- Sample data for development (commented out for production)
-- ============================================================================

-- INSERT INTO public.idempotency_keys (
--     tenant_id, principal_id, command_name, idempotency_key, created_at, expires_at, response_payload
-- ) VALUES (
--     '11111111-1111-1111-1111-111111111111', -- acme tenant
--     gen_random_uuid(), -- user ID
--     'POST_/api/projects',
--     '550e8400-e29b-41d4-a716-446655440000',
--     NOW(),
--     NOW() + INTERVAL '24 hours',
--     jsonb_build_object(
--         'statusCode', 201,
--         'body', jsonb_build_object(
--             'id', gen_random_uuid(),
--             'name', 'Project Alpha',
--             'status', 'ACTIVE'
--         )
--     )
-- );

-- Test idempotent replay:
-- SELECT response_payload FROM public.idempotency_keys
-- WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
--   AND principal_id = '<user_id>'
--   AND command_name = 'POST_/api/projects'
--   AND idempotency_key = '550e8400-e29b-41d4-a716-446655440000'
--   AND expires_at > NOW();
