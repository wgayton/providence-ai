"""Natural language search → structured filters → hybrid SQL+vector results.

Pipeline:
  1. Claude tool-use translates free-form query → SearchFilters
  2. Voyage embeds semantic_query → 1024-dim vector
  3. Hybrid query: SQL filters + pgvector ANN + combined score
"""
from anthropic import AsyncAnthropic

from app.config import settings
from app.schemas import SearchFilters

SEARCH_TOOL = {
    "name": "execute_property_search",
    "description": "Translate a natural-language property search query into structured filters.",
    "input_schema": {
        "type": "object",
        "properties": {
            "classifications": {
                "type": "array",
                "items": {
                    "type": "string",
                    "enum": ["ABANDONED", "DISTRESSED", "LOT_VALUE_ONLY", "ACTIVE"],
                },
                "description": "Property classification labels to include.",
            },
            "max_price_usd": {"type": "number"},
            "min_acreage": {"type": "number"},
            "max_acreage": {"type": "number"},
            "counties": {
                "type": "array",
                "items": {"type": "string"},
                "description": "NC county names (e.g., 'Wilkes', 'Ashe').",
            },
            "semantic_query": {
                "type": "string",
                "description": "Cleaned query text for semantic embedding (≤200 chars).",
            },
            "structure_age_min_years": {"type": "integer"},
        },
        "required": ["semantic_query"],
    },
}

SYSTEM_PROMPT = """You translate natural-language property search queries into
structured filters for a rural NC abandoned-property database. Extract explicit
constraints (price, acreage, county, classification). Produce a concise
semantic_query capturing descriptive intent (condition, use, style). If the
user does not specify classification, default to ABANDONED+DISTRESSED+LOT_VALUE_ONLY.
Output only via the execute_property_search tool."""


class AiSearchService:
    def __init__(self) -> None:
        self._claude = AsyncAnthropic(api_key=settings.anthropic_api_key)

    async def translate_query(self, query: str) -> SearchFilters:
        """Call Claude to translate NL query to structured filters."""
        resp = await self._claude.messages.create(
            model=settings.claude_model,
            max_tokens=512,
            system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
            tools=[SEARCH_TOOL],
            tool_choice={"type": "tool", "name": "execute_property_search"},
            messages=[{"role": "user", "content": query}],
        )
        tool_use = next(b for b in resp.content if b.type == "tool_use")
        filters_data = dict(tool_use.input)
        if not filters_data.get("classifications"):
            filters_data["classifications"] = ["ABANDONED", "DISTRESSED", "LOT_VALUE_ONLY"]
        return SearchFilters(**filters_data)
