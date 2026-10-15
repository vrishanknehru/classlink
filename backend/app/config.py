"""Runtime settings, read from CLASSLINK_* environment variables."""

from __future__ import annotations

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CLASSLINK_", env_file=".env", extra="ignore")

    environment: str = "development"
    database_url: str = Field(min_length=1)
    jwt_secret: str = Field(min_length=16)
    jwt_audience: str = "authenticated"
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

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"
