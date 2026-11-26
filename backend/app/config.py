"""Runtime settings, read from CLASSLINK_* environment variables."""

from __future__ import annotations

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CLASSLINK_", env_file=".env", extra="ignore")

    environment: str = "development"
    database_url: str = Field(min_length=1)

    # User tokens. Set supabase_url to verify asymmetric keys (ES256, RS256) from the
    # project's JWKS endpoint. Set jwt_secret to also accept legacy HS256 tokens.
    # At least one of the two is required.
    supabase_url: str | None = Field(default=None, pattern=r"^https?://[^\s/]+/?$")
    jwt_secret: str | None = Field(default=None, min_length=16)
    jwt_audience: str = "authenticated"
    jwks_cache_seconds: int = Field(default=600, ge=30, le=86400)
    token_hmac_secret: str = Field(min_length=16)

    # Rotating BLE token policy.
    token_period_seconds: int = Field(default=15, ge=5, le=120)
    token_grace_epochs: int = Field(default=1, ge=0, le=4)

    # Claim policy.
    challenge_ttl_seconds: int = Field(default=120, ge=10, le=600)
    claim_max_age_seconds: int = Field(default=60, ge=5, le=600)

    # Accounts that receive the teacher role when they create a profile.
    teacher_emails: list[str] = Field(default_factory=list)
    cors_origins: list[str] = Field(default_factory=list)

    @model_validator(mode="after")
    def _need_a_token_verifier(self) -> Settings:
        if self.supabase_url is None and self.jwt_secret is None:
            raise ValueError("set CLASSLINK_SUPABASE_URL, CLASSLINK_JWT_SECRET, or both")
        return self

    @property
    def jwt_issuer(self) -> str | None:
        """Supabase puts `<project url>/auth/v1` in the `iss` claim."""
        return f"{self.supabase_url.rstrip('/')}/auth/v1" if self.supabase_url else None

    @property
    def jwks_url(self) -> str | None:
        return f"{self.jwt_issuer}/.well-known/jwks.json" if self.jwt_issuer else None

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"
