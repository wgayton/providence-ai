-- ============================================================================
-- V002: Create public.outbox_events table (Debezium CDC Source)
-- ============================================================================
-- Purpose: Transactional outbox pattern for guaranteed event delivery
-- Schema: public (events from all tenants stored here)
-- Pattern: Write domain mutation + outbox event in same transaction
--
-- Flow:
-- 1. Application writes domain entity to t_<tenant> schema
-- 2. Application writes event to public.outbox_events (same transaction)
-- 3. Transaction commits → both changes are atomic
-- 4. Debezium CDC reads from outbox_events via PostgreSQL logical replication
-- 5. Debezium publishes to Kafka topic: ecap.events.<event_type>
-- 6. Consumers read from Kafka and apply projections (via inbox pattern)
--
-- Benefits:
-- - Atomic: Domain change + event emission guaranteed together
-- - Reliable: No event loss (database durability)
-- - No dual-write problem: Single transaction, no partial failures
-- - Debezium ensures at-least-once delivery to Kafka
--
-- Debezium Configuration:
-- - Connector: io.debezium.connector.postgresql.PostgresConnector
-- - Transform: io.debezium.transforms.outbox.EventRouter
-- - Topic routing: ecap.events.${routedByValue} (uses event_type)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.outbox_events (
    -- Event identifier (UUID for global uniqueness)
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Tenant that owns this event
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,

    -- Aggregate identification (DDD aggregate root)
    aggregate_type VARCHAR(100) NOT NULL, -- e.g., 'Project', 'User', 'FundTransfer'
    aggregate_id UUID NOT NULL, -- ID of the aggregate instance

    -- Event metadata
    event_type VARCHAR(100) NOT NULL, -- e.g., 'ProjectCreated', 'UserRegistered'
    event_version INT NOT NULL DEFAULT 1, -- Schema version for event payload

    -- Timing
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), -- When event occurred (business time)
    published_at TIMESTAMPTZ, -- When Debezium published to Kafka (set by Debezium)

    -- Distributed tracing and causality
    correlation_id UUID NOT NULL, -- Trace entire request flow across services
    causation_id UUID, -- ID of event that caused this event (event chain)

    -- Actor who triggered the event (for audit trail)
    actor_id UUID, -- User ID or service account ID

    -- Event payload (JSONB for flexible schema)
    -- Contains the domain event data (e.g., ProjectCreated record)
    payload JSONB NOT NULL,

    -- Metadata for operational visibility
    metadata JSONB, -- Additional context: IP address, user agent, API version, etc.

    CONSTRAINT chk_event_type_format CHECK (event_type ~ '^[A-Z][a-zA-Z0-9]*$'), -- PascalCase
    CONSTRAINT chk_aggregate_type_format CHECK (aggregate_type ~ '^[A-Z][a-zA-Z0-9]*$') -- PascalCase
);

-- ============================================================================
-- Indexes for performance and Debezium efficiency
-- ============================================================================

-- Debezium reads unpublished events in order
CREATE INDEX idx_outbox_published_at ON public.outbox_events(published_at)
    WHERE published_at IS NULL; -- Partial index: only unpublished events

-- Tenant-scoped event history queries
CREATE INDEX idx_outbox_tenant_occurred ON public.outbox_events(tenant_id, occurred_at DESC);

-- Aggregate event history (e.g., "show all events for Project X")
CREATE INDEX idx_outbox_aggregate ON public.outbox_events(aggregate_type, aggregate_id, occurred_at DESC);

-- Event type filtering for analytics
CREATE INDEX idx_outbox_event_type ON public.outbox_events(event_type, occurred_at DESC);

-- Correlation ID for distributed tracing
CREATE INDEX idx_outbox_correlation_id ON public.outbox_events(correlation_id);

-- Causation chain navigation
CREATE INDEX idx_outbox_causation_id ON public.outbox_events(causation_id)
    WHERE causation_id IS NOT NULL;

-- ============================================================================
-- Partitioning strategy (optional, for high-volume systems)
-- ============================================================================
-- For systems with millions of events, consider partitioning by occurred_at
-- This example uses monthly partitions (adjust based on volume)

-- Enable partitioning (commented out by default)
-- ALTER TABLE public.outbox_events PARTITION BY RANGE (occurred_at);

-- Create partitions (example for 2026)
-- CREATE TABLE public.outbox_events_2026_01 PARTITION OF public.outbox_events
--     FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
-- CREATE TABLE public.outbox_events_2026_02 PARTITION OF public.outbox_events
--     FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

-- ============================================================================
-- Debezium publication and replication slot
-- ============================================================================
-- These are created automatically by Debezium, but can be pre-created:

-- Create publication for outbox table
-- CREATE PUBLICATION providence_outbox_publication FOR TABLE public.outbox_events;

-- Create replication slot (Debezium will use this)
-- SELECT pg_create_logical_replication_slot('providence_outbox_slot', 'pgoutput');

-- ============================================================================
-- Trigger: Mark published_at when Debezium processes event
-- ============================================================================
-- Note: Debezium does NOT automatically update published_at.
-- This trigger is optional and updates published_at based on a custom flag.
-- Alternative: Use Debezium's tombstone feature or external job to update.

-- CREATE OR REPLACE FUNCTION mark_outbox_published()
-- RETURNS TRIGGER AS $$
-- BEGIN
--     IF NEW.published_at IS NOT NULL AND OLD.published_at IS NULL THEN
--         -- Event just got published
--         RAISE NOTICE 'Event published: %', NEW.id;
--     END IF;
--     RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE TRIGGER trg_outbox_published
--     AFTER UPDATE ON public.outbox_events
--     FOR EACH ROW
--     WHEN (OLD.published_at IS NULL AND NEW.published_at IS NOT NULL)
--     EXECUTE FUNCTION mark_outbox_published();

-- ============================================================================
-- Retention policy: Archive old events
-- ============================================================================
-- Outbox events should be archived or deleted after Kafka retention period
-- Example: Delete events older than 90 days that have been published

-- Option 1: Manual cleanup job (run via cron or scheduled task)
-- DELETE FROM public.outbox_events
-- WHERE published_at < NOW() - INTERVAL '90 days';

-- Option 2: Automatic cleanup via pg_cron extension
-- SELECT cron.schedule('cleanup-outbox-events', '0 2 * * *', $$
--     DELETE FROM public.outbox_events
--     WHERE published_at < NOW() - INTERVAL '90 days'
-- $$);

-- ============================================================================
-- Comments for database documentation
-- ============================================================================

COMMENT ON TABLE public.outbox_events IS
    'Transactional outbox for event-driven architecture. Debezium CDC reads from this table and publishes to Kafka. Guarantees atomic domain mutation + event emission.';

COMMENT ON COLUMN public.outbox_events.id IS
    'Event identifier (UUID). Used as Kafka message key and for deduplication in inbox pattern.';

COMMENT ON COLUMN public.outbox_events.tenant_id IS
    'Tenant that owns this event. Foreign key to public.tenants(id).';

COMMENT ON COLUMN public.outbox_events.aggregate_type IS
    'DDD aggregate root type (e.g., Project, User). Used for event routing and filtering.';

COMMENT ON COLUMN public.outbox_events.aggregate_id IS
    'ID of the aggregate instance. Used as Kafka partition key for ordering guarantees.';

COMMENT ON COLUMN public.outbox_events.event_type IS
    'Event type in PascalCase (e.g., ProjectCreated). Debezium routes to Kafka topic: ecap.events.<event_type>.';

COMMENT ON COLUMN public.outbox_events.event_version IS
    'Schema version for payload. Increment when adding breaking changes. Consumers use this for backward compatibility.';

COMMENT ON COLUMN public.outbox_events.occurred_at IS
    'Business time when event occurred (not when it was written to DB). Set by application.';

COMMENT ON COLUMN public.outbox_events.published_at IS
    'Timestamp when Debezium published to Kafka. NULL = not yet published.';

COMMENT ON COLUMN public.outbox_events.correlation_id IS
    'Trace ID for distributed tracing. Propagated from HTTP X-Correlation-Id header or gRPC metadata.';

COMMENT ON COLUMN public.outbox_events.causation_id IS
    'ID of event that caused this event. Used for event chain navigation (e.g., PaymentReceived → InvoicePaid).';

COMMENT ON COLUMN public.outbox_events.actor_id IS
    'User or service account that triggered this event. Used for audit trail and authorization.';

COMMENT ON COLUMN public.outbox_events.payload IS
    'Event payload as JSONB. Contains the domain event record (e.g., {"projectId": "...", "name": "..."}).';

COMMENT ON COLUMN public.outbox_events.metadata IS
    'Additional operational metadata: IP address, user agent, API version, client ID, etc.';

-- ============================================================================
-- Sample data for development (commented out for production)
-- ============================================================================

-- INSERT INTO public.outbox_events (
--     id, tenant_id, aggregate_type, aggregate_id, event_type, event_version,
--     occurred_at, correlation_id, actor_id, payload
-- ) VALUES (
--     gen_random_uuid(),
--     '11111111-1111-1111-1111-111111111111', -- acme tenant
--     'Project',
--     gen_random_uuid(),
--     'ProjectCreated',
--     1,
--     NOW(),
--     gen_random_uuid(),
--     gen_random_uuid(),
--     '{"projectId": "550e8400-e29b-41d4-a716-446655440000", "name": "Project Alpha", "description": "Initial project"}'::jsonb
-- );
