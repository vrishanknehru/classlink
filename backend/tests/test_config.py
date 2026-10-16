import pytest
from pydantic import ValidationError

from app.config import Settings

GOOD = dict(
    database_url="postgresql://u:p@h/db",
    jwt_secret="j" * 32,
    token_hmac_secret="h" * 32,
)


def test_valid_settings_load_with_safe_defaults() -> None:
    s = Settings(**GOOD)
    assert s.token_period_seconds == 15
    assert s.challenge_ttl_seconds == 120
    assert s.claim_max_age_seconds == 60
    assert not s.is_production


@pytest.mark.parametrize("missing", ["database_url", "jwt_secret", "token_hmac_secret"])
def test_service_refuses_to_start_without_required_secrets(
    missing: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    for var in ("DATABASE_URL", "JWT_SECRET", "TOKEN_HMAC_SECRET"):
        monkeypatch.delenv(f"CLASSLINK_{var}", raising=False)
    kwargs = {k: v for k, v in GOOD.items() if k != missing}
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **kwargs)  # type: ignore[arg-type]


def test_short_secrets_are_rejected() -> None:
    with pytest.raises(ValidationError):
        Settings(**{**GOOD, "token_hmac_secret": "short"})
    with pytest.raises(ValidationError):
        Settings(**{**GOOD, "jwt_secret": "short"})


def test_token_period_is_bounded() -> None:
    with pytest.raises(ValidationError):
        Settings(**GOOD, token_period_seconds=1)
    with pytest.raises(ValidationError):
        Settings(**GOOD, token_period_seconds=600)
