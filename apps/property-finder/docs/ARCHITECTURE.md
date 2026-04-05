# Architecture

## System Overview

```
┌────────────────────────────────────────────────────────────┐
│  Next.js Frontend                                          │
│  • Map UI (MapLibre GL)                                    │
│  • NL search bar + filters                                 │
│  • Property profile pages                                  │
└────────────────────────┬───────────────────────────────────┘
                         │ HTTPS / JSON
┌────────────────────────▼───────────────────────────────────┐
│  FastAPI Backend                                           │
│  ├── /api/v1/search        NL search → Claude → SQL        │
│  ├── /api/v1/properties    List/filter + GeoJSON           │
│  ├── /api/v1/properties/{id}  Profile + AI summary         │
│  └── /api/v1/classify      Re-classify endpoint            │
└──────┬───────────┬──────────────┬──────────┬───────────────┘
       │           │              │          │
       ▼           ▼              ▼          ▼
  ┌────────┐ ┌────────┐  ┌─────────────┐ ┌────────┐
  │Postgres│ │pgvector│  │  Claude API │ │ Redis  │
  │+PostGIS│ │ embeds │  │  Voyage AI  │ │ cache  │
  └────────┘ └────────┘  └─────────────┘ └────────┘
       ▲
       │
┌──────┴──────────────────────────┐
│  Prefect ETL Flows              │
│  ├── nc_onemap_parcels_sync     │
│  ├── <county>_tax_delinquency   │
│  ├── hud_usps_vacancy_sync      │
│  ├── naip_imagery_sync          │
│  └── classify_properties_nightly│
└─────────────────────────────────┘
```

## Data Flow

1. **Ingest** — Prefect flows pull raw data → `staging_*` tables
2. **Transform** — SQL promotes staged rows to `properties` + `property_signals`
3. **Classify** — Classification service scores each property, writes to `property_classifications`
4. **Embed** — Voyage embeds property feature text, stored in `property_embeddings`
5. **Serve** — FastAPI reads classified + embedded rows for search/profile endpoints
6. **AI Layer** — Claude translates NL queries, generates profile summaries on demand

## Component Responsibilities

### Backend Services

| Service | Responsibility |
|---|---|
| `classification.py` | Apply rule/ML classifiers, return labels + confidence |
| `ai_search.py` | Claude NL→structured query, hybrid SQL+vector search |
| `profile_generator.py` | Compose property narrative via Claude |
| `embeddings.py` | Voyage embedding calls, pgvector writes |
| `signals.py` | Compute derived signals (improvement ratio, absentee flag) |

### ETL Flows

| Flow | Frequency | Source |
|---|---|---|
| `nc_onemap_parcels_sync` | Quarterly | NC OneMap statewide parcel layer |
| `<county>_tax_delinquency` | Monthly | County tax collector sites |
| `hud_usps_vacancy_sync` | Quarterly | HUD User USPS dataset |
| `naip_imagery_sync` | Annually | USDA NAIP aerial imagery |
| `classify_properties_nightly` | Nightly | Internal — re-classify on signal changes |

## Deployment Topology

- **API**: Fly.io / Railway (2+ instances behind LB)
- **Frontend**: Vercel
- **Database**: Managed Postgres (Supabase / Neon / RDS) with PostGIS + pgvector
- **ETL**: Prefect Cloud workers on Fly machines
- **Object Storage**: Cloudflare R2 (imagery tiles, raw scraped artifacts)
- **Cache**: Upstash Redis

## Security

- API keys for Claude/Voyage in env vars, never committed
- Rate limiting on search endpoints (10 req/min per IP unauthenticated)
- CORS restricted to known frontend origins
- PII never logged (owner names, addresses stripped from Claude prompts)
- Read-only DB user for API; separate write user for ETL
