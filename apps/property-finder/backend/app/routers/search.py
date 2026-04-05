"""Natural language search endpoint."""
from datetime import datetime, UTC

from fastapi import APIRouter, HTTPException

from app.schemas import SearchRequest, SearchResponse

router = APIRouter()


@router.post("", response_model=SearchResponse)
async def search(request: SearchRequest) -> SearchResponse:
    """
    Natural-language property search.

    Flow:
      1. Claude translates query → SearchFilters
      2. Voyage embeds semantic_query → 1024-dim vector
      3. Hybrid SQL + pgvector search
      4. Return ranked PropertyResponse list
    """
    # TODO: wire up ai_search.AiSearchService
    _ = request
    _ = datetime.now(UTC)
    raise HTTPException(status_code=501, detail="Not implemented")
