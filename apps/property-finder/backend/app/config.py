"""Application configuration."""
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/property_finder"
    redis_url: str = "redis://localhost:6379/0"

    anthropic_api_key: str = ""
    voyage_api_key: str = ""

    claude_model: str = "claude-sonnet-4-6"
    claude_fast_model: str = "claude-haiku-4-5-20251001"
    voyage_model: str = "voyage-3-large"
    embedding_dim: int = 1024

    cors_origins: list[str] = ["http://localhost:3000"]
    search_cache_ttl_seconds: int = 900


settings = Settings()
