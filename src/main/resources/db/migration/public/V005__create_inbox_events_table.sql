-- ============================================================================
-- V005: Create public.inbox_events table
-- ============================================================================
-- Purpose: Inbox pattern for exactly-once event processing
-- Schema: public (inbox events from all tenants and all consumers)
-- Pattern: Check inbox before processing → Mark processed → Apply business logic
--
-- Problem:
-- - Kafka guarantees at-least-once delivery (events may be redelivered)
-- - Consumer crashes, rebalances, or retries can cause duplicate processing
-- - Example: "Send notification" event processed twice → user gets 2 emails
-- - Example: "Credit account" event processed twice → double payment!
--
-- Solution (Inbox Pattern):
-- 1. Consumer receives event from Kafka
-- 2. Check if event_id exists in inbox_events for this (tenant_id, consumer_name)
-- 3. If exists → Skip (already processed)
-- 4. If NOT exists → Insert into inbox_events, apply business logic, commit transaction
-- 5. Result: Exactly-once effects (even with at-least-once delivery)
--
-- Used by:
-- - ProjectEventConsumer: @KafkaListener for ecap.events.ProjectCreated
-- - NotificationSender: @KafkaListener for notification events
-- - ProjectionUpdater: @KafkaListener for read model updates
-- - Any Kafka consumer that needs exactly-once semantics
--
-- Inbox pattern vs. Kafka transactions:
-- - Kafka transactions: Exactly-once delivery within Kafka (expensive, complex)
-- - Inbox pattern: Exactly-once effects (simpler, works with any message broker)
-- - Trade-off: Inbox requires database write per event (acceptable for most workloads)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.inbox_events (
    -- Composite primary key: (tenant, consumer, event_id)
    tenant_id UUID NOT NULL, -- Tenant that owns this event
    consumer_name VARCHAR(100) NOT NULL, -- Consumer identifier (e.g., 'NotificationSender', 'ProjectionUpdater')
    event_id UUID NOT NULL, -- Event identifier from Kafka message header

    -- Timing
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Metadata for debugging and monitoring
    kafka_topic VARCHAR(255), -- Kafka topic (e.g., 'ecap.events.ProjectCreated')
    kafka_partition INT, -- Kafka partition number
    kafka_offset BIGINT, -- Kafka offset within partition
    retry_count INT DEFAULT 0, -- Number of retry attempts before success

    PRIMARY KEY (tenant_id, consumer_name, event_id)
);

-- ============================================================================
-- Indexes for inbox lookups
-- ============================================================================

-- Fast lookup for InboxService.isProcessed()
-- (Primary key already creates index, but explicit for clarity)
-- CREATE INDEX idx_inbox_lookup ON public.inbox_events(tenant_id, consumer_name, event_id);

-- Consumer progress tracking (for monitoring dashboards)
CREATE INDEX idx_inbox_consumer_processed ON public.inbox_events(consumer_name, processed_at DESC);

-- Recent events for debugging
CREATE INDEX idx_inbox_processed_at ON public.inbox_events(processed_at DESC);

-- Kafka offset tracking (optional, for manual replay)
CREATE INDEX idx_inbox_kafka_offset ON public.inbox_events(kafka_topic, kafka_partition, kafka_offset);

-- ============================================================================
-- Retention policy: Cleanup old inbox events
-- ============================================================================
-- Inbox events should be retained long enough to handle:
-- - Consumer lag (e.g., 24 hours behind)
-- - Consumer reprocessing (e.g., re-read Kafka from earliest offset)
-- - Typical retention: 30-90 days (longer than Kafka retention)

-- Option 1: Manual cleanup job (via cron or scheduled task)
-- DELETE FROM public.inbox_events WHERE processed_at < NOW() - INTERVAL '90 days';

-- Option 2: Automatic cleanup via pg_cron extension
-- SELECT cron.schedule('cleanup-inbox-events', '0 3 * * *', $$
--     DELETE FROM public.inbox_events WHERE processed_at < NOW() - INTERVAL '90 days'
-- $$);

-- Option 3: Partition by processed_at and drop old partitions (most efficient)
-- See partitioning section below

-- ============================================================================
-- Partitioning strategy (optional, for high-volume systems)
-- ============================================================================
-- For systems processing millions of events/day, partition by processed_at

-- Enable partitioning (commented out by default)
-- ALTER TABLE public.inbox_events PARTITION BY RANGE (processed_at);

-- Create monthly partitions
-- CREATE TABLE public.inbox_events_2026_02 PARTITION OF public.inbox_events
--     FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

-- DROP old partitions instead of DELETE (much faster)
-- DROP TABLE public.inbox_events_2025_11; -- Drops all events from Nov 2025

-- ============================================================================
-- Metrics: Consumer lag and processing rate
-- ============================================================================
-- Track how fast consumers are processing events

-- CREATE TABLE public.inbox_metrics (
--     consumer_name VARCHAR(100) NOT NULL,
--     tenant_id UUID NOT NULL,
--     date DATE NOT NULL DEFAULT CURRENT_DATE,
--     events_processed BIGINT DEFAULT 0,
--     avg_processing_time_ms INT,
--     max_retry_count INT,
--     PRIMARY KEY (consumer_name, tenant_id, date)
-- );

-- CREATE OR REPLACE FUNCTION update_inbox_metrics()
-- RETURNS TRIGGER AS $$
-- BEGIN
--     INSERT INTO public.inbox_metrics (consumer_name, tenant_id, date, events_processed)
--     VALUES (NEW.consumer_name, NEW.tenant_id, CURRENT_DATE, 1)
--     ON CONFLICT (consumer_name, tenant_id, date)
--     DO UPDATE SET events_processed = inbox_metrics.events_processed + 1;
--     RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- CREATE TRIGGER trg_inbox_metrics
--     AFTER INSERT ON public.inbox_events
--     FOR EACH ROW
--     EXECUTE FUNCTION update_inbox_metrics();

-- ============================================================================
-- Dead-letter queue (DLQ) tracking
-- ============================================================================
-- Track events that failed processing after max retries

-- CREATE TABLE public.inbox_dead_letter_queue (
--     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     tenant_id UUID NOT NULL,
--     consumer_name VARCHAR(100) NOT NULL,
--     event_id UUID NOT NULL,
--     kafka_topic VARCHAR(255),
--     kafka_partition INT,
--     kafka_offset BIGINT,
--     event_payload JSONB,
--     error_message TEXT,
--     retry_count INT,
--     failed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- );

-- ============================================================================
-- Duplicate event detection: Warn on reprocessing attempts
-- ============================================================================
-- If a consumer tries to process an event that's already in inbox, log a warning

CREATE OR REPLACE FUNCTION warn_duplicate_event()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'Duplicate event detected (already processed). Consumer: %, Event ID: %, Tenant: %',
        NEW.consumer_name, NEW.event_id, NEW.tenant_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_warn_duplicate_event
    BEFORE INSERT ON public.inbox_events
    FOR EACH ROW
    EXECUTE FUNCTION warn_duplicate_event();

-- ============================================================================
-- Exactly-once guarantee verification
-- ============================================================================
-- Test query to verify exactly-once semantics

-- Count events processed multiple times (should be 0)
-- SELECT event_id, COUNT(*) as process_count
-- FROM public.inbox_events
-- WHERE consumer_name = 'NotificationSender'
-- GROUP BY event_id
-- HAVING COUNT(*) > 1;

-- ============================================================================
-- Comments for database documentation
-- ============================================================================

COMMENT ON TABLE public.inbox_events IS
    'Inbox pattern for exactly-once event processing. Prevents duplicate Kafka event processing. Primary key ensures each event is processed once per consumer.';

COMMENT ON COLUMN public.inbox_events.tenant_id IS
    'Tenant that owns this event. Used for tenant-scoped deduplication.';

COMMENT ON COLUMN public.inbox_events.consumer_name IS
    'Consumer identifier (e.g., NotificationSender, ProjectionUpdater). Different consumers can process the same event independently.';

COMMENT ON COLUMN public.inbox_events.event_id IS
    'Event identifier from Kafka message header (matches public.outbox_events.id). Used for deduplication.';

COMMENT ON COLUMN public.inbox_events.processed_at IS
    'Timestamp when event was successfully processed. Used for retention cleanup.';

COMMENT ON COLUMN public.inbox_events.kafka_topic IS
    'Kafka topic where event was consumed from (e.g., ecap.events.ProjectCreated). Used for debugging.';

COMMENT ON COLUMN public.inbox_events.kafka_partition IS
    'Kafka partition number. Used with offset for manual replay.';

COMMENT ON COLUMN public.inbox_events.kafka_offset IS
    'Kafka offset within partition. Used for consumer lag tracking.';

COMMENT ON COLUMN public.inbox_events.retry_count IS
    'Number of retry attempts before success. Used for monitoring flaky operations.';

-- ============================================================================
-- Sample data for development (commented out for production)
-- ============================================================================

-- INSERT INTO public.inbox_events (
--     tenant_id, consumer_name, event_id, processed_at,
--     kafka_topic, kafka_partition, kafka_offset, retry_count
-- ) VALUES (
--     '11111111-1111-1111-1111-111111111111', -- acme tenant
--     'NotificationSender',
--     gen_random_uuid(),
--     NOW(),
--     'ecap.events.ProjectCreated',
--     0,
--     12345,
--     0
-- );

-- Test inbox deduplication:
-- SELECT EXISTS (
--     SELECT 1 FROM public.inbox_events
--     WHERE tenant_id = '11111111-1111-1111-1111-111111111111'
--       AND consumer_name = 'NotificationSender'
--       AND event_id = '<event_id_from_kafka>'
-- ) AS is_already_processed;
