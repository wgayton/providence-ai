---
name: ai-search
description: Use this skill when building, debugging, or extending the natural language property search. Triggers on phrases like "NL search", "query translation", "search endpoint", "hybrid search", "pgvector search", "fix search results".
---

# AI-Powered Natural Language Search

Use this skill to work with the hybrid NL search system
(`backend/app/services/ai_search.py`).

## Goal

Accept free-form queries like:
> "abandoned farmhouse under $50k with 5+ acres in the NC mountains"

And return ranked properties via hybrid SQL filtering + semantic vector search.

## Pipeline

```
User query
   │
   ├─► Claude (structured output)
   │     → classification filters
   │     → price/acreage/county filters
   │     → semantic query text
   │
   ├─► Voyage (embed semantic query)
   │     → 1024-dim vector
   │
   ├─► PostgreSQL
   │     1. Apply SQL filters
   │     2. pgvector ANN search within filtered set
   │     3. Combine scores
   │
   └─► Return top 50 ranked results
```

## Claude Structured Output Schema

Use Claude tool-use to force structured output:

```python
search_tool = {
  "name": "execute_property_search",
  "input_schema": {
    "type": "object",
    "properties": {
      "classifications": {
        "type": "array",
        "items": {"enum": ["ABANDONED","DISTRESSED","LOT_VALUE_ONLY","ACTIVE"]}
      },
      "max_price_usd": {"type": "number"},
      "min_acreage": {"type": "number"},
      "max_acreage": {"type": "number"},
      "counties": {"type": "array", "items": {"type": "string"}},
      "semantic_query": {"type": "string"},
      "structure_age_min_years": {"type": "integer"}
    },
    "required": ["semantic_query"]
  }
}
```

## Hybrid Scoring

```sql
SELECT
  p.*,
  (1 - (e.embedding <=> :query_vector)) AS semantic_score,
  c.confidence AS classification_confidence,
  (0.6 * (1 - (e.embedding <=> :query_vector)))
    + (0.4 * c.confidence) AS combined_score
FROM properties p
JOIN property_embeddings e USING (parcel_uid)
JOIN property_classifications c USING (parcel_uid)
WHERE c.label = ANY(:classifications)
  AND p.total_value_usd <= :max_price
  AND p.acreage >= :min_acreage
  AND p.county = ANY(:counties)
ORDER BY combined_score DESC
LIMIT 50;
```

## Rules

- **Cache** Claude query-translation responses by raw query string (15 min TTL)
- **Log structured filter only** — never log raw SQL or PII
- **Default classifications** to `['ABANDONED','DISTRESSED','LOT_VALUE_ONLY']` if user didn't specify
- **Limit semantic_query length** to 200 chars before embedding
- **Fallback** to pure SQL search if Voyage API fails

## Debugging

Given a user query that returned wrong results:

1. Log the Claude structured output — verify filters match intent
2. Log embedded vector dimension (must be 1024)
3. Run SQL manually with extracted filters
4. Check `EXPLAIN ANALYZE` on the hybrid query — verify ivfflat index hit
5. If semantic score is low for obvious matches, check property text used for embedding

## Index Requirements

```sql
CREATE INDEX ON property_embeddings USING ivfflat (embedding vector_cosine_ops)
WITH (lists = 100);
CREATE INDEX ON properties (county, total_value_usd, acreage);
CREATE INDEX ON property_classifications (label, confidence DESC);
```
