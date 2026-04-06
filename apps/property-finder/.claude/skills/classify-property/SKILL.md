---
name: classify-property
description: Use this skill when adding or modifying property classification rules, debugging why a parcel got a specific label, or calibrating classifier thresholds. Triggers on phrases like "add classification rule", "why is this property abandoned", "tune classifier threshold", "reclassify".
---

# Classify Property

Use this skill to work with the property classification engine
(`backend/app/services/classification.py`).

## Classification Labels

| Label | Meaning |
|---|---|
| `ABANDONED` | Unoccupied + neglected + delinquent |
| `DISTRESSED` | Financial/physical distress signals |
| `LOT_VALUE_ONLY` | Structure has negligible value |
| `ACTIVE` | None of the above |

See [docs/PROPERTY_CLASSIFICATION.md](../../docs/PROPERTY_CLASSIFICATION.md)
for full rule definitions.

## Adding a Rule

1. **Define the rule signature**
   ```python
   def rule_<name>(prop: Property, sig: Signals) -> Classification | None
   ```
   - Returns `None` if rule does not apply
   - Returns `Classification(label, confidence, reasons)` if it does

2. **Keep rules pure**
   - No DB calls, no API calls
   - All inputs via `Property` + `Signals` dataclasses

3. **Register in `RULES` list** in `classification.py`

4. **Add golden test**
   - `backend/tests/services/test_classification.py`
   - Fixture parcel + expected label + expected reasons

5. **Validate against golden set**
   ```bash
   uv run pytest backend/tests/services/test_classification.py -v
   uv run python -m app.services.classification --validate-golden
   ```

## Debugging a Classification

Given a `parcel_uid`:

1. Load the property + signals:
   ```sql
   SELECT * FROM properties WHERE parcel_uid = '...';
   SELECT * FROM property_signals WHERE parcel_uid = '...' ORDER BY captured_at DESC;
   ```

2. Run classifier with `--explain`:
   ```bash
   uv run python -m app.services.classification \
     --parcel-uid <uid> --explain
   ```
   Prints every rule evaluation with pass/fail and contributing values.

3. Compare against expected label from golden set.

## Tuning Thresholds

When changing a threshold (e.g., improvement ratio cutoff):

1. Run full golden-set validation BEFORE change → record metrics
2. Make change
3. Run full golden-set validation AFTER change
4. Report delta: precision/recall per label
5. If ABANDONED precision drops below 0.85, revert

## Never Do

- Don't hard-code county-specific thresholds in rules (use `counties.config` JSON)
- Don't call Claude/Voyage from within a classification rule (keep rules fast + deterministic)
- Don't mutate `Property` or `Signals` inputs
