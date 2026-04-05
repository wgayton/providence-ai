"""Rule-based property classification engine.

Each rule is a pure function returning Classification|None. Rules are
evaluated in priority order; highest-confidence candidate wins.

See docs/PROPERTY_CLASSIFICATION.md for full rule definitions.
"""
from dataclasses import dataclass, field
from decimal import Decimal
from typing import Callable, Literal

CLASSIFIER_VERSION = "rules-v0.1"

Label = Literal["ABANDONED", "DISTRESSED", "LOT_VALUE_ONLY", "ACTIVE"]

LABEL_PRIORITY: dict[Label, int] = {
    "ABANDONED": 3,
    "DISTRESSED": 2,
    "LOT_VALUE_ONLY": 1,
    "ACTIVE": 0,
}


@dataclass(frozen=True)
class Property:
    parcel_uid: str
    land_value_usd: Decimal
    improvement_value_usd: Decimal
    structure_year_built: int | None
    owner_matches_site: bool  # True if owner addr == site addr


@dataclass(frozen=True)
class Signals:
    tax_delinquent_years: int
    usps_vacancy_rate: float
    overgrowth_score: float | None = None
    permit_count_10yr: int | None = None


@dataclass(frozen=True)
class Classification:
    label: Label
    confidence: float
    reasons: list[str] = field(default_factory=list)


def _improvement_ratio(prop: Property) -> float:
    land = float(prop.land_value_usd) or 1.0
    return float(prop.improvement_value_usd) / land


def rule_abandoned_full(prop: Property, sig: Signals) -> Classification | None:
    reasons: list[str] = []
    if sig.tax_delinquent_years < 3:
        return None
    reasons.append(f"delinquent {sig.tax_delinquent_years}yr")

    if sig.usps_vacancy_rate <= 0.15:
        return None
    reasons.append(f"tract vacancy {sig.usps_vacancy_rate:.0%}")

    ratio = _improvement_ratio(prop)
    if ratio >= 0.20:
        return None
    reasons.append(f"improvement ratio {ratio:.2f}")

    if prop.owner_matches_site:
        return None
    reasons.append("absentee owner")

    confidence = 0.70 + min(0.15, 0.05 * (sig.tax_delinquent_years - 3))
    if sig.overgrowth_score and sig.overgrowth_score > 0.6:
        confidence += 0.10
        reasons.append(f"overgrowth {sig.overgrowth_score:.2f}")
    if sig.permit_count_10yr == 0:
        confidence += 0.05
        reasons.append("no permits 10yr")

    return Classification("ABANDONED", min(confidence, 1.0), reasons)


def rule_distressed(prop: Property, sig: Signals) -> Classification | None:
    reasons: list[str] = []
    confidence = 0.0

    if 1 <= sig.tax_delinquent_years <= 2:
        reasons.append(f"delinquent {sig.tax_delinquent_years}yr")
        confidence = 0.60
    elif not prop.owner_matches_site and _improvement_ratio(prop) < 0.30:
        reasons.append("absentee + low improvement ratio")
        confidence = 0.55
    else:
        return None

    return Classification("DISTRESSED", confidence, reasons)


def rule_lot_value_only(prop: Property, sig: Signals) -> Classification | None:
    reasons: list[str] = []
    confidence = 0.0

    if prop.improvement_value_usd <= Decimal("5000"):
        reasons.append(f"improvement ${prop.improvement_value_usd}")
        confidence = 0.75
    elif prop.structure_year_built and (2026 - prop.structure_year_built) > 80:
        if sig.permit_count_10yr == 0:
            reasons.append(f"structure age {2026 - prop.structure_year_built}yr, no permits")
            confidence = 0.65
        else:
            return None
    else:
        return None

    return Classification("LOT_VALUE_ONLY", confidence, reasons)


RULES: list[Callable[[Property, Signals], Classification | None]] = [
    rule_abandoned_full,
    rule_distressed,
    rule_lot_value_only,
]


def classify(prop: Property, sig: Signals) -> Classification:
    candidates = [c for rule in RULES if (c := rule(prop, sig)) is not None]
    if not candidates:
        return Classification("ACTIVE", 1.0, [])
    return max(candidates, key=lambda c: (LABEL_PRIORITY[c.label], c.confidence))
