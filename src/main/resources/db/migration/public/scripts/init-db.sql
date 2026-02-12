-- ============================================================================
-- Providence AI - Database Initialization Script
-- ============================================================================
-- This script runs automatically when the PostgreSQL container starts.
-- It configures logical replication for Debezium CDC.
--
-- Location: /docker-entrypoint-initdb.d/init-db.sql (auto-executed)
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create publication for Debezium (outbox pattern)
-- This allows Debezium to read from public.outbox_events via logical replication
CREATE PUBLICATION providence_outbox_publication FOR TABLE public.outbox_events;

-- Create replication slot for Debezium
-- Debezium will use this slot to track its position in the WAL
SELECT pg_create_logical_replication_slot('providence_outbox_slot', 'pgoutput');

-- Grant necessary permissions for Debezium user
GRANT SELECT ON public.outbox_events TO providence;
GRANT USAGE ON SCHEMA public TO providence;

-- Log initialization complete
DO $$
BEGIN
    RAISE NOTICE 'Providence AI database initialized successfully';
    RAISE NOTICE 'Logical replication enabled for Debezium CDC';
    RAISE NOTICE 'Publication: providence_outbox_publication';
    RAISE NOTICE 'Replication slot: providence_outbox_slot';
END $$;
