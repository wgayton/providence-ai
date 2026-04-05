# Property Classification

## Taxonomy

Properties are classified into one of four labels with a confidence score
(0.0–1.0) and a list of contributing reasons.

### ABANDONED (highest signal)
Structure appears unoccupied and neglected; owner has ceased financial obligations.

**Required signals (ALL):**
- Tax delinquent ≥ 3 consecutive years
- HUD USPS vacancy rate in tract > 15%
- Improvement value / land value ratio < 0.20
- Owner mailing address ≠ site address (absentee)

**Optional boost signals:**
- No building permits in 10+ years
- NAIP overgrowth score > 0.6
- Structure age > 60 years

**Confidence formula:**
```
base = 0.70
+ 0.05 per year delinquent beyond 3 (cap 0.15)
+ 0.10 if overgrowth score > 0.6
+ 0.05 if no permits in 10 yrs
```

### DISTRESSED
Signs of financial or physical distress, but not fully abandoned.

**Any ONE of:**
- Tax delinquent 1–2 years
- Absentee owner + improvement ratio < 0.30
- Recent code violations (if data available)
- Pre-foreclosure filings

### LOT_VALUE_ONLY
Structure has negligible value; buyer is effectively purchasing land.

**Any ONE of:**
- Improvement value ≤ $5,000
- Structure age > 80 yrs AND no permits in 20 yrs
- Land value ≥ 90% of total assessed value

### ACTIVE
None of the above conditions met. Default label.

## Classification Algorithm

```python
def classify(property: Property, signals: Signals) -> Classification:
    candidates = []
    for rule in RULES:
        result = rule.evaluate(property, signals)
        if result:
            candidates.append(result)  # (label, confidence, reasons)

    if not candidates:
        return Classification(label="ACTIVE", confidence=1.0, reasons=[])

    # Priority order: ABANDONED > DISTRESSED > LOT_VALUE_ONLY
    # Within label, highest confidence wins
    return max(candidates, key=lambda c: (LABEL_PRIORITY[c.label], c.confidence))
```

## Rule Implementation Pattern

Each rule is a pure function:

```python
def rule_abandoned_full(prop: Property, sig: Signals) -> Classification | None:
    reasons = []
    if sig.tax_delinquent_years < 3:
        return None
    reasons.append(f"delinquent {sig.tax_delinquent_years} yrs")

    if sig.usps_vacancy_rate <= 0.15:
        return None
    reasons.append(f"tract vacancy {sig.usps_vacancy_rate:.0%}")

    ratio = prop.improvement_value / max(prop.land_value, 1)
    if ratio >= 0.20:
        return None
    reasons.append(f"improvement ratio {ratio:.2f}")

    if prop.owner_mail_addr == prop.site_addr:
        return None
    reasons.append("absentee owner")

    confidence = 0.70
    confidence += min(0.15, 0.05 * (sig.tax_delinquent_years - 3))
    if sig.overgrowth_score and sig.overgrowth_score > 0.6:
        confidence += 0.10
        reasons.append(f"overgrowth {sig.overgrowth_score:.2f}")

    return Classification("ABANDONED", min(confidence, 1.0), reasons)
```

## Validation & Calibration

- Maintain a **golden set** of 200+ manually-labeled parcels per label
- Track precision/recall per label on each classifier release
- Target: precision ≥ 0.85 for ABANDONED (false positives erode user trust)
- Review misclassifications monthly; tune thresholds or add rules

## ML Upgrade Path (Phase 5)

Replace rule scores with XGBoost classifier trained on:
- All structured features above
- NAIP-derived features (roof damage, overgrowth, debris)
- Temporal features (years since last sale, permit count trend)

Keep rule engine as **fallback** and **explanation layer** for ML predictions.
