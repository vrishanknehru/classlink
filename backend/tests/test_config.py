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


@pytest.mark.parametrize("missing", ["database_url", "token_hmac_secret"])
def test_service_refuses_to_start_without_required_secrets(
    missing: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    for var in ("DATABASE_URL", "JWT_SECRET", "SUPABASE_URL", "TOKEN_HMAC_SECRET"):
        monkeypatch.delenv(f"CLASSLINK_{var}", raising=False)
    kwargs = {k: v for k, v in GOOD.items() if k != missing}
    with pytest.raises(ValidationError):
        Settings(_env_file=None, **kwargs)  # type: ignore[arg-type]


def test_service_needs_a_way_to_verify_user_tokens(monkeypatch: pytest.MonkeyPatch) -> None:
    for var in ("JWT_SECRET", "SUPABASE_URL"):
        monkeypatch.delenv(f"CLASSLINK_{var}", raising=False)
    no_verifier = {k: v for k, v in GOOD.items() if k != "jwt_secret"}
    with pytest.raises(ValidationError, match="SUPABASE_URL"):
        Settings(_env_file=None, **no_verifier)  # type: ignore[arg-type]
    jwks_only = Settings(_env_file=None, **no_verifier, supabase_url="https://abcd.supabase.co")  # type: ignore[arg-type]
    assert jwks_only.jwt_secret is None


def test_supabase_url_must_be_a_bare_origin() -> None:
    with pytest.raises(ValidationError):
        Settings(**GOOD, supabase_url="abcd.supabase.co")
    with pytest.raises(ValidationError):
        Settings(**GOOD, supabase_url="https://abcd.supabase.co/auth/v1")


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
