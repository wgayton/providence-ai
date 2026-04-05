# Property Finder — AI-Powered Abandoned Property Search

An analytics platform for discovering abandoned, distressed, and lot-value-only
rural properties across North Carolina. Combines county parcel data, tax
delinquency records, USPS vacancy indicators, and aerial imagery with ML
classification and Claude-powered natural language search.

## Core Capabilities

- **Multi-source data ingestion** — NC OneMap, county GIS, tax delinquency lists, HUD USPS vacancy, NAIP imagery
- **Property classification** — Distressed / Abandoned / Lot-Value-Only / Active
- **Natural language search** — "abandoned farmhouse under $50k with 5+ acres in Wilkes County"
- **AI-generated property profiles** — narrative summaries synthesized from structured signals
- **Geospatial analytics** — PostGIS-backed parcel intelligence

## Tech Stack

| Layer | Technology |
|---|---|
| Backend | Python 3.12 + FastAPI |
| Database | PostgreSQL 17 + PostGIS + pgvector |
| ETL | Prefect |
| AI | Claude API (claude-sonnet-4-6) + Voyage embeddings |
| ML | XGBoost (tabular), PyTorch (imagery) |
| Frontend | Next.js 15 + React 19 + MapLibre GL |
| Cache | Redis |
| Storage | S3 / Cloudflare R2 |

## Project Layout

```
property-finder/
├── backend/
│   ├── app/
│   │   ├── main.py               # FastAPI entry
│   │   ├── models.py             # SQLAlchemy ORM
│   │   ├── schemas.py            # Pydantic DTOs
│   │   ├── routers/              # HTTP endpoints
│   │   │   ├── properties.py
│   │   │   └── search.py
│   │   ├── services/             # Business logic
│   │   │   ├── classification.py
│   │   │   └── ai_search.py
│   │   └── etl/                  # Ingest flows (Prefect)
│   └── db/migrations/            # SQL migrations
├── frontend/                     # Next.js app
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_SOURCES.md
│   └── PROPERTY_CLASSIFICATION.md
├── .claude/
│   └── skills/                   # Claude Code workflow skills
├── docker-compose.yml
└── .env.example
```

## Quick Start

```bash
# 1. Start infrastructure
docker compose up -d

# 2. Install backend deps
cd backend && uv sync

# 3. Run migrations
uv run alembic upgrade head

# 4. Start API
uv run uvicorn app.main:app --reload

# 5. Start frontend
cd ../frontend && pnpm install && pnpm dev
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Data Sources](docs/DATA_SOURCES.md)
- [Property Classification](docs/PROPERTY_CLASSIFICATION.md)
- [Claude Context](CLAUDE.md)
