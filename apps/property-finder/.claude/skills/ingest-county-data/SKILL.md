---
name: ingest-county-data
description: Use this skill when adding a new county data source, building a tax delinquency scraper, or extending parcel ingestion for Property Finder. Triggers on phrases like "add county scraper", "ingest Wilkes tax data", "new county ETL flow".
---

# Add a County Data Source

Use this skill to add a new county's parcel + tax delinquency ingestion to the
Property Finder ETL pipeline.

## Steps

1. **Research the county data source**
   - Find the tax collector website and delinquency list URL
   - Check robots.txt and terms of service
   - Identify data format: HTML table, PDF, CSV download, ArcGIS REST endpoint
   - Note: some counties charge for data — flag if paywalled

2. **Register the county**
   - Add row to `counties` table with FIPS code, name, scraper config JSON
   - Example config:
     ```json
     {
       "tax_url": "https://wilkescountync.gov/tax/delinquent",
       "format": "html_table",
       "rate_limit_per_sec": 1,
       "selectors": {...}
     }
     ```

3. **Create the Prefect flow**
   - File: `backend/app/etl/flows/{county_slug}_tax_scrape.py`
   - Use `httpx.AsyncClient` with rate limiting
   - Write raw fetched content to R2 under `raw/{county}/{date}/`
   - Parse into `staging_tax_delinquency` table
   - Register flow in `backend/app/etl/registry.py`

4. **Normalize parcel IDs**
   - Strip whitespace, dashes, uppercase
   - Compute `parcel_uid = sha256(county_fips || normalized_parcel_id)`
   - Match against `properties` table on `parcel_uid`

5. **Write tests**
   - Record fixtures with `vcrpy` (never hit live sites in CI)
   - Golden test: fixture file → expected staging rows
   - Location: `backend/tests/etl/test_{county_slug}_scraper.py`

6. **Dry-run and validate**
   - Run flow locally against 10-row sample
   - Verify: row counts, null rates, parcel_uid matches in `properties`
   - Check ingest_runs table for clean completion

## Rules

- Respect rate limits; default 1 req/sec with exponential backoff on 429
- Never commit scraped PII (owner names) to fixture files — redact
- Idempotency: flow MUST be safe to re-run; use upserts keyed on `parcel_uid`
- Log summary stats (rows fetched, matched, unmatched) to `ingest_runs`

## Output

Report:
- Flow file path
- Counties table row added
- Test coverage
- Sample of 5 matched properties with their delinquency data
