"""Pydantic DTOs for API requests/responses."""
from datetime import date, datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field

Classification = Literal["ABANDONED", "DISTRESSED", "LOT_VALUE_ONLY", "ACTIVE"]


class PropertyResponse(BaseModel):
    parcel_uid: str
    county: str
    parcel_id: str
    acreage: Decimal | None
    land_value_usd: Decimal | None
    improvement_value_usd: Decimal | None
    total_value_usd: Decimal | None
    last_sale_date: date | None
    last_sale_price_usd: Decimal | None
    structure_year_built: int | None
    classification: Classification
    classification_confidence: float
    classification_reasons: list[str]
    ai_summary: str | None
    centroid_lat: float | None
    centroid_lon: float | None


class SearchRequest(BaseModel):
    query: str = Field(min_length=1, max_length=500)
    limit: int = Field(default=50, ge=1, le=200)


class SearchFilters(BaseModel):
    classifications: list[Classification] | None = None
    max_price_usd: float | None = None
    min_acreage: float | None = None
    max_acreage: float | None = None
    counties: list[str] | None = None
    semantic_query: str
    structure_age_min_years: int | None = None


class SearchResponse(BaseModel):
    query: str
    filters: SearchFilters
    results: list[PropertyResponse]
    total: int
    generated_at: datetime
