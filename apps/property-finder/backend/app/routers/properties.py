"""Property listing and profile endpoints."""
from fastapi import APIRouter, HTTPException

from app.schemas import PropertyResponse

router = APIRouter()


@router.get("/{parcel_uid}", response_model=PropertyResponse)
async def get_property(parcel_uid: str) -> PropertyResponse:
    """Return a property profile with AI-generated summary."""
    # TODO: load from DB, regenerate summary if signals_updated_at > summary_generated_at
    raise HTTPException(status_code=501, detail="Not implemented")


@router.get("", response_model=list[PropertyResponse])
async def list_properties(
    county: str | None = None,
    classification: str | None = None,
    limit: int = 50,
) -> list[PropertyResponse]:
    """List properties with basic filters (no NL search)."""
    # TODO: implement SQL filter query
    raise HTTPException(status_code=501, detail="Not implemented")
