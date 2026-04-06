# Property Finder — Claude Code Context

Auto-loaded context for Claude Code sessions in this subdirectory.

## Project

**Property Finder** — AI-powered search platform for abandoned, distressed, and
lot-only rural properties in North Carolina. Built on PostGIS parcel data,
Claude natural-language search, and ML classification.

## Technology Stack

- **Language:** Python 3.12+ (type hints required, use `|` unions, avoid `Optional`)
- **API:** FastAPI with async endpoints
- **ORM:** SQLAlchemy 2.x (async) + GeoAlchemy2 for PostGIS
- **Validation:** Pydantic v2
- **DB:** PostgreSQL 17 + PostGIS 3.4 + pgvector
- **AI:** Anthropic SDK (`claude-sonnet-4-6`) for NL search + profile generation
- **Embeddings:** Voyage AI (`voyage-3-large`, 1024 dims)
- **ETL:** Prefect 3.x flows
- **Frontend:** Next.js 15 + React 19 + MapLibre GL JS + Tailwind + shadcn/ui

## Domain Model

The **PropertyProfile** is the core aggregate. Every parcel ingested becomes a
profile with derived signals and a classification label.

### Classification Taxonomy

| Label | Definition |
|---|---|
| `ABANDONED` | Tax delinquent 3+ yrs AND USPS vacant AND improvement value < 20% of land value |
| `DISTRESSED` | Tax delinquent 1-2 yrs OR absentee owner + low maintenance signals |
| `LOT_VALUE_ONLY` | Improvement value ≤ $5k OR structure age > 80 yrs with no recent permits |
| `ACTIVE` | None of the above |

See [docs/PROPERTY_CLASSIFICATION.md](docs/PROPERTY_CLASSIFICATION.md) for full rules.

## Architectural Patterns

### 1. Data Ingestion — Prefect Flows
- Each county has its own scraper flow (tax delinquency is per-county)
- Statewide parcels come from NC OneMap quarterly
- Flows are idempotent: re-running doesn't create duplicates
- All flows write to `staging_*` tables; transformations promote to `properties`

### 2. Classification — Pluggable Rules Engine
- Start with rule-based classifier in `services/classification.py`
- Each rule returns `(label, confidence, reasons[])`
- Highest-confidence label wins
- ML classifier (XGBoost) plugs into same interface in Phase 5

### 3. AI Search — Claude + pgvector Hybrid
- NL query → Claude structured output → SQL filter predicates
- Same query → Voyage embedding → pgvector ANN search
- Results re-ranked by combined structured + semantic score

### 4. Property Profiles — Lazy AI Summaries
- Summaries generated on first view, cached in `properties.ai_summary`
- Invalidated when underlying signals change (`signals_updated_at > summary_generated_at`)
- Use Claude with structured property data; do NOT include raw owner PII in prompts

## Critical Rules

1. **Use `Decimal` for money** — never `float`. Store cents as `INTEGER` or use `NUMERIC(14,2)`.
2. **Use `BigDecimal`-equivalent for acreage** — `NUMERIC(10,4)`.
3. **All geometries in EPSG:4326 (WGS84)** — project to EPSG:2264 (NC State Plane ft) for area calcs.
4. **PII redaction** — strip owner names/addresses from all Claude prompts; pass only anonymized signals.
5. **Idempotent ingest** — use `(county_fips, parcel_id)` as natural key for upserts.
6. **Rate limiting** — respect county site robots.txt; default to 1 req/sec, backoff on 429.
7. **Embeddings are 1024-dim** — Voyage `voyage-3-large`. Do not mix models.
8. **Never log raw SQL from NL search** — log the structured filter only.

## Database Schema (Core Tables)

```
properties              -- Core entity (one row per parcel)
property_signals        -- Time-series signals (tax status, vacancy, etc.)
property_classifications-- Classification history + confidence
property_embeddings     -- pgvector embeddings for semantic search
counties                -- County metadata + scraper config
ingest_runs             -- ETL run log (idempotency + observability)
```

All tables use `parcel_uid = sha256(county_fips || parcel_id)` as stable PK.

## File Naming Conventions

- Routers: `app/routers/<resource>.py` (plural noun)
- Services: `app/services/<domain>.py`
- Prefect flows: `app/etl/flows/<source>_<action>.py` (e.g., `wilkes_tax_scrape.py`)
- Migrations: `db/migrations/V{NNN}__{snake_case_description}.sql`

## Testing Standards

- **Unit tests:** `pytest` + `pytest-asyncio` — 80%+ coverage on services
- **Integration tests:** Testcontainers for PostGIS; real Claude calls behind `@pytest.mark.llm`
- **Ingest tests:** Record HTTP fixtures with `vcrpy`; never hit live county sites in CI
- **Classification tests:** Golden-file tests with labeled parcels

## Claude API Usage

- Model: `claude-sonnet-4-6` for search + profile generation
- Model: `claude-haiku-4-5-20251001` for cheap classification rationales
- Always use tool-use / structured outputs for NL→SQL translation
- Max tokens: 1024 for summaries, 512 for rationales
- Cache prompts with `cache_control` on system prompt (costs ~10x less)

## Common Workflows

Use skills in `.claude/skills/`:
- **ingest-county-data** — Add a new county scraper
- **classify-property** — Add/modify classification rules
- **property-profile** — Generate or debug AI property summaries
- **ai-search** — Debug NL search query translation

## NOT In Scope (Yet)

- Buying/closing workflow (out of scope for MVP)
- Multi-state support (NC only for v1)
- User accounts / saved searches (Phase 2)
- Mobile apps (web responsive only)
