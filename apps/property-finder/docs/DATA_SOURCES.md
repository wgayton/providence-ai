# Data Sources

## Primary Sources

### 1. NC OneMap — Statewide Parcels
- **URL:** https://www.nconemap.gov
- **Format:** GeoJSON / Shapefile / ArcGIS REST
- **Refresh:** Quarterly
- **Key fields:** `PARCEL_ID`, `OWNER_NAME`, `MAIL_ADDR`, `SITE_ADDR`, `ACRES`, `LAND_VAL`, `BLDG_VAL`, `TOTAL_VAL`, `LAST_SALE_DATE`, `LAND_USE_CD`
- **License:** Public domain / open data
- **Notes:** County coverage varies in completeness; supplement with direct county pulls for target counties.

### 2. County Tax Delinquency Lists
- **Per-county scrapers required** — no statewide API
- **Typical sources:** County tax collector websites, published PDFs (NCGS § 105-369)
- **Key fields:** `parcel_id`, `years_delinquent`, `amount_owed`, `last_payment_date`
- **Refresh:** Monthly
- **Priority counties (MVP):** Wilkes, Ashe, Alleghany, Yancey, Madison (rural, high-signal)

### 3. HUD USPS Vacancy Data
- **URL:** https://www.huduser.gov/portal/datasets/usps.html
- **Format:** CSV by census tract
- **Refresh:** Quarterly
- **Key fields:** `tract_geoid`, `vacant_res_count`, `no_stat_count`, `avg_vacant_time`
- **Notes:** Tract-level only; use as rate adjustment, not per-parcel flag.

### 4. NAIP Aerial Imagery
- **URL:** USDA Geospatial Data Gateway
- **Format:** GeoTIFF (4-band RGB+NIR)
- **Resolution:** 60cm (updated biennially per state)
- **Use:** Overgrowth detection, roof condition, structure presence verification

## Supplementary Sources

### 5. NC Deeds & Registers
- Per-county deed indexes (iDocMarket, LandRecords, etc.)
- Use for: heirs' property detection, multi-owner parcels, probate flags

### 6. NC Secretary of State — Business Registry
- Detect LLC-owned parcels (common flip/hold pattern)
- Identify dormant/dissolved LLCs still holding title

### 7. OpenStreetMap
- Road network, settlement boundaries, POIs
- Derive rurality score

### 8. US Census ACS 5-Year
- Tract-level poverty, median income, population change
- Context signals for "abandoned town" detection

## Ingest Priority (MVP)

1. NC OneMap parcels — 3 pilot counties (Wilkes, Ashe, Alleghany)
2. Tax delinquency scrapers for those 3 counties
3. HUD USPS vacancy join
4. NAIP tiles for visual verification

## Data Quality Rules

- **Coordinate normalization:** All geometries → EPSG:4326 on ingest
- **Parcel ID normalization:** Strip spaces, dashes, uppercase
- **Owner name normalization:** Fold case, strip business suffixes for matching
- **Deduplication key:** `parcel_uid = sha256(county_fips || normalized_parcel_id)`
- **Staging → Promotion:** Only promote rows with valid geometry + non-null owner
