-- V001__init.sql
-- Initial schema for Property Finder

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Counties registry
CREATE TABLE counties (
    fips_code       CHAR(5) PRIMARY KEY,              -- e.g., '37193' (Wilkes)
    name            TEXT NOT NULL,
    slug            TEXT NOT NULL UNIQUE,
    state_code      CHAR(2) NOT NULL DEFAULT 'NC',
    scraper_config  JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Core property entity
CREATE TABLE properties (
    parcel_uid              CHAR(64) PRIMARY KEY,     -- sha256(fips || parcel_id)
    county_fips             CHAR(5) NOT NULL REFERENCES counties(fips_code),
    parcel_id               TEXT NOT NULL,
    geometry                GEOMETRY(MultiPolygon, 4326) NOT NULL,
    centroid                GEOGRAPHY(Point, 4326),
    acreage                 NUMERIC(10,4),
    land_value_usd          NUMERIC(14,2),
    improvement_value_usd   NUMERIC(14,2),
    total_value_usd         NUMERIC(14,2),
    last_sale_date          DATE,
    last_sale_price_usd     NUMERIC(14,2),
    structure_year_built    INTEGER,
    land_use_code           TEXT,
    -- AI summary cache
    ai_summary              TEXT,
    summary_generated_at    TIMESTAMPTZ,
    signals_updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Timestamps
    first_seen_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (county_fips, parcel_id)
);
CREATE INDEX idx_properties_geom ON properties USING GIST (geometry);
CREATE INDEX idx_properties_centroid ON properties USING GIST (centroid);
CREATE INDEX idx_properties_filters ON properties (county_fips, total_value_usd, acreage);

-- Time-series signals per property
CREATE TABLE property_signals (
    id                      BIGSERIAL PRIMARY KEY,
    parcel_uid              CHAR(64) NOT NULL REFERENCES properties(parcel_uid) ON DELETE CASCADE,
    tax_delinquent_years    INTEGER,
    tax_amount_owed_usd     NUMERIC(14,2),
    absentee_owner          BOOLEAN,
    usps_vacancy_rate       NUMERIC(5,4),
    overgrowth_score        NUMERIC(5,4),
    permit_count_10yr       INTEGER,
    captured_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_signals_parcel ON property_signals (parcel_uid, captured_at DESC);

-- Classification history
CREATE TABLE property_classifications (
    id              BIGSERIAL PRIMARY KEY,
    parcel_uid      CHAR(64) NOT NULL REFERENCES properties(parcel_uid) ON DELETE CASCADE,
    label           TEXT NOT NULL CHECK (label IN ('ABANDONED','DISTRESSED','LOT_VALUE_ONLY','ACTIVE')),
    confidence      NUMERIC(4,3) NOT NULL,
    reasons         JSONB NOT NULL DEFAULT '[]',
    classifier_ver  TEXT NOT NULL,
    classified_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_classifications_current ON property_classifications (parcel_uid, classified_at DESC);
CREATE INDEX idx_classifications_label ON property_classifications (label, confidence DESC);

-- Vector embeddings for semantic search
CREATE TABLE property_embeddings (
    parcel_uid      CHAR(64) PRIMARY KEY REFERENCES properties(parcel_uid) ON DELETE CASCADE,
    embedding       VECTOR(1024) NOT NULL,          -- voyage-3-large
    source_text     TEXT NOT NULL,
    model           TEXT NOT NULL DEFAULT 'voyage-3-large',
    generated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_embeddings_ann ON property_embeddings
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- ETL run log
CREATE TABLE ingest_runs (
    id              BIGSERIAL PRIMARY KEY,
    flow_name       TEXT NOT NULL,
    county_fips     CHAR(5) REFERENCES counties(fips_code),
    status          TEXT NOT NULL CHECK (status IN ('RUNNING','SUCCESS','FAILED')),
    rows_fetched    INTEGER,
    rows_matched    INTEGER,
    rows_unmatched  INTEGER,
    error_message   TEXT,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at    TIMESTAMPTZ
);
CREATE INDEX idx_ingest_runs_flow ON ingest_runs (flow_name, started_at DESC);

-- Staging tables
CREATE TABLE staging_parcels (
    id              BIGSERIAL PRIMARY KEY,
    county_fips     CHAR(5) NOT NULL,
    raw_parcel_id   TEXT NOT NULL,
    raw_data        JSONB NOT NULL,
    ingest_run_id   BIGINT REFERENCES ingest_runs(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE staging_tax_delinquency (
    id              BIGSERIAL PRIMARY KEY,
    county_fips     CHAR(5) NOT NULL,
    raw_parcel_id   TEXT NOT NULL,
    years_delinquent INTEGER,
    amount_owed_usd NUMERIC(14,2),
    last_payment    DATE,
    raw_data        JSONB NOT NULL,
    ingest_run_id   BIGINT REFERENCES ingest_runs(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
