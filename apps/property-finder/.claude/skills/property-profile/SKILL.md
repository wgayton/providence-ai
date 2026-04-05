---
name: property-profile
description: Use this skill when generating, debugging, or modifying AI property profile summaries. Triggers on phrases like "generate profile summary", "property summary prompt", "AI profile generation", "profile caching".
---

# Property Profile Generation

Use this skill to work with Claude-powered property profile summaries
(`backend/app/services/profile_generator.py`).

## Purpose

Generate a 2–3 paragraph narrative summary of a property for buyer-facing UI,
synthesizing structured signals into readable investment context.

## Flow

1. On `GET /api/v1/properties/{id}`:
   - Check `properties.ai_summary` + `summary_generated_at`
   - If `signals_updated_at > summary_generated_at` → regenerate
   - Otherwise return cached summary

2. On regeneration:
   - Load property + latest signals + classification
   - Build anonymized prompt (NO owner PII)
   - Call Claude `claude-sonnet-4-6` with prompt caching on system
   - Store result in `properties.ai_summary`

## Prompt Shape

**System prompt (cached):**
```
You are a real-estate analyst describing rural NC properties to investors.
Output 2-3 paragraphs covering: classification rationale, investment angle,
risks/caveats. Neutral tone. Never speculate beyond provided signals. Never
include owner names or addresses.
```

**User prompt (per-property):**
```json
{
  "county": "Wilkes",
  "acreage": 4.2,
  "classification": "ABANDONED",
  "confidence": 0.82,
  "reasons": ["delinquent 5 yrs", "absentee owner", "improvement ratio 0.08"],
  "land_value_usd": 18000,
  "improvement_value_usd": 1500,
  "last_sale_year": 1998,
  "last_sale_price_usd": 42000,
  "tract_vacancy_rate": 0.22
}
```

## PII Redaction Rules (CRITICAL)

Before sending to Claude, strip:
- Owner name
- Owner mailing address (street + unit)
- Site street address (keep county + general area only)
- Parcel ID
- Any phone/email

Pass only anonymized structured signals. If a field could be re-identifying,
round or bucket it (e.g., `acreage: 4.2` is fine; `lat/lon: 36.123, -81.456`
must be rounded to 2 decimals or dropped).

## Caching Strategy

- **Prompt cache** on system prompt (ttl: 1h default, saves ~90% on tokens)
- **Summary cache** in `properties.ai_summary` (invalidate on signal change)
- **Batch generation**: nightly job generates summaries for top 1000 newly-classified abandoned properties

## Token Budget

- Max input: ~500 tokens (structured data is small)
- Max output: 1024 tokens
- Expected cost: ~$0.005 per summary uncached, ~$0.0005 cached

## Debugging

If a summary looks wrong:
1. Dump the exact user prompt payload
2. Verify PII redaction worked
3. Check classification reasons are accurate
4. Re-run with `--verbose` to see raw Claude response
