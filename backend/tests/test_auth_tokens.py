"""User token verification: JWKS (ES256, RS256) and the HS256 fallback."""

from __future__ import annotations

import json
import time
from collections.abc import Callable
from typing import Any
from uuid import uuid4

import jwt
import psycopg
import pytest
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi.testclient import TestClient

from app.auth_tokens import InvalidToken, SigningKeysUnavailable, TokenVerifier
from app.config import Settings
from app.db import Database
from app.main import create_app
from tests.conftest import JWT_SECRET, FakeClock

SUPABASE_URL = "https://abcd.supabase.co"
ISSUER = f"{SUPABASE_URL}/auth/v1"
AUD = "authenticated"

PrivateKey = ec.EllipticCurvePrivateKey | rsa.RSAPrivateKey


def _jwk(private: PrivateKey, kid: str, alg: str) -> dict[str, Any]:
    algo = jwt.get_algorithm_by_name(alg)
    jwk: dict[str, Any] = json.loads(algo.to_jwk(private.public_key()))
    return {**jwk, "kid": kid, "alg": alg, "use": "sig"}


class StaticJwks(jwt.PyJWKClient):
    """A JWKS client that serves fixed keys instead of calling the network."""

    def __init__(self, keys: list[dict[str, Any]], *, reachable: bool = True) -> None:
        super().__init__(f"{ISSUER}/.well-known/jwks.json", cache_jwk_set=True, lifespan=600)
        self.keys = keys
        self.reachable = reachable
        self.fetches = 0

    def fetch_data(self) -> Any:
        self.fetches += 1
        if not self.reachable:
            raise jwt.PyJWKClientConnectionError("connection refused")
        return {"keys": self.keys}


EC_KEY = ec.generate_private_key(ec.SECP256R1())
RSA_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
KEYS = [_jwk(EC_KEY, "ec-1", "ES256"), _jwk(RSA_KEY, "rsa-1", "RS256")]


def _claims(**overrides: Any) -> dict[str, Any]:
    base = {
        "sub": str(uuid4()),
        "email": "ada@example.edu",
        "aud": AUD,
        "iss": ISSUER,
        "exp": int(time.time()) + 3600,
    }
    return {**base, **overrides}


def _sign(key: PrivateKey | str, alg: str, kid: str | None, **claims: Any) -> str:
    headers = {"kid": kid} if kid else None
    return jwt.encode(_claims(**claims), key, algorithm=alg, headers=headers)


def _verifier(
    jwks: StaticJwks | None = None, secret: str | None = None
) -> tuple[TokenVerifier, StaticJwks]:
    client = jwks or StaticJwks(KEYS)
    return TokenVerifier(
        audience=AUD, jwks_client=client, issuer=ISSUER, hs256_secret=secret
    ), client


@pytest.mark.parametrize(
    ("key", "alg", "kid"), [(EC_KEY, "ES256", "ec-1"), (RSA_KEY, "RS256", "rsa-1")]
)
def test_asymmetric_tokens_from_jwks_are_accepted(key: PrivateKey, alg: str, kid: str) -> None:
    verifier, _ = _verifier()
    user_id = str(uuid4())
    assert verifier.verify(_sign(key, alg, kid, sub=user_id))["sub"] == user_id


def test_jwks_is_fetched_once_and_cached() -> None:
    verifier, jwks = _verifier()
    for _ in range(3):
        verifier.verify(_sign(EC_KEY, "ES256", "ec-1"))
    assert jwks.fetches == 1


def test_token_signed_with_a_wrong_key_is_rejected() -> None:
    stranger = ec.generate_private_key(ec.SECP256R1())
    verifier, _ = _verifier()
    with pytest.raises(InvalidToken):
        verifier.verify(_sign(stranger, "ES256", "ec-1"))


def test_unknown_key_id_is_rejected() -> None:
    verifier, _ = _verifier()
    with pytest.raises(InvalidToken):
        verifier.verify(_sign(EC_KEY, "ES256", "not-a-published-key"))


def test_token_cannot_claim_a_different_algorithm_than_its_key() -> None:
    verifier, _ = _verifier()
    # Signed with RSA but labelled with the EC key's id.
    with pytest.raises(InvalidToken):
        verifier.verify(_sign(RSA_KEY, "RS256", "ec-1"))


def test_wrong_issuer_and_audience_are_rejected() -> None:
    verifier, _ = _verifier()
    with pytest.raises(InvalidToken):
        verifier.verify(_sign(EC_KEY, "ES256", "ec-1", iss="https://evil.supabase.co/auth/v1"))
    with pytest.raises(InvalidToken):
        verifier.verify(_sign(EC_KEY, "ES256", "ec-1", aud="anon"))


def test_expired_token_is_rejected() -> None:
    verifier, _ = _verifier()
    with pytest.raises(InvalidToken):
        verifier.verify(_sign(EC_KEY, "ES256", "ec-1", exp=int(time.time()) - 10))


def test_hs256_fallback_works_only_with_a_secret() -> None:
    with_secret, _ = _verifier(secret=JWT_SECRET)
    without_secret, _ = _verifier()
    token = _sign(JWT_SECRET, "HS256", None)
    assert with_secret.verify(token)["email"] == "ada@example.edu"
    with pytest.raises(InvalidToken):
        without_secret.verify(token)


def test_hs256_token_signed_with_a_wrong_secret_is_rejected() -> None:
    verifier, _ = _verifier(secret=JWT_SECRET)
    with pytest.raises(InvalidToken):
        verifier.verify(_sign("another-secret-0123456789abcdef-x", "HS256", None))


def test_unsigned_and_garbage_tokens_are_rejected() -> None:
    verifier, _ = _verifier(secret=JWT_SECRET)
    unsigned = jwt.encode(_claims(), None, algorithm="none")  # type: ignore[arg-type]
    for token in (unsigned, "not.a.jwt", ""):
        with pytest.raises(InvalidToken):
            verifier.verify(token)


def test_unreachable_jwks_is_reported_separately() -> None:
    verifier, _ = _verifier(StaticJwks(KEYS, reachable=False))
    with pytest.raises(SigningKeysUnavailable):
        verifier.verify(_sign(EC_KEY, "ES256", "ec-1"))


def test_settings_build_the_jwks_url_from_the_supabase_url() -> None:
    s = Settings(
        _env_file=None,  # type: ignore[call-arg]
        database_url="postgresql://u:p@h/db",
        token_hmac_secret="h" * 32,
        supabase_url=f"{SUPABASE_URL}/",
    )
    assert s.jwt_secret is None
    assert s.jwt_issuer == ISSUER
    assert s.jwks_url == f"{ISSUER}/.well-known/jwks.json"


# --- Through the API ------------------------------------------------------------


@pytest.fixture
def jwks_client_factory(
    settings: Settings, db: Database, clock: FakeClock
) -> Callable[[StaticJwks], TestClient]:
    def build(jwks: StaticJwks) -> TestClient:
        cfg = settings.model_copy(update={"jwt_secret": None, "supabase_url": SUPABASE_URL})
        verifier = TokenVerifier(audience=AUD, jwks_client=jwks, issuer=ISSUER)
        return TestClient(create_app(cfg, db, clock, token_verifier=verifier))

    return build


def test_api_accepts_an_es256_supabase_token(
    jwks_client_factory: Callable[[StaticJwks], TestClient], migrated_url: str
) -> None:
    client = jwks_client_factory(StaticJwks(KEYS))
    user_id = uuid4()
    with psycopg.connect(migrated_url, autocommit=True) as conn:
        conn.execute(
            "insert into auth.users (id, email) values (%s, %s)", (user_id, "ada@example.edu")
        )
    headers = {"Authorization": f"Bearer {_sign(EC_KEY, 'ES256', 'ec-1', sub=str(user_id))}"}
    created = client.post(
        "/v1/profile",
        json={"full_name": "Ada Lovelace", "roll_number": "1024160001"},
        headers=headers,
    )
    assert created.status_code == 200, created.text
    me = client.get("/v1/me", headers=headers)
    assert me.status_code == 200, me.text
    assert me.json()["id"] == str(user_id)


def test_api_rejects_a_token_signed_with_a_wrong_key(
    jwks_client_factory: Callable[[StaticJwks], TestClient],
) -> None:
    client = jwks_client_factory(StaticJwks(KEYS))
    stranger = ec.generate_private_key(ec.SECP256R1())
    resp = client.get(
        "/v1/me", headers={"Authorization": f"Bearer {_sign(stranger, 'ES256', 'ec-1')}"}
    )
    assert resp.status_code == 401


def test_api_rejects_hs256_when_no_secret_is_configured(
    jwks_client_factory: Callable[[StaticJwks], TestClient],
) -> None:
    client = jwks_client_factory(StaticJwks(KEYS))
    token = _sign(JWT_SECRET, "HS256", None)
    assert client.get("/v1/me", headers={"Authorization": f"Bearer {token}"}).status_code == 401


def test_api_answers_503_when_signing_keys_cannot_be_fetched(
    jwks_client_factory: Callable[[StaticJwks], TestClient],
) -> None:
    client = jwks_client_factory(StaticJwks(KEYS, reachable=False))
    token = _sign(EC_KEY, "ES256", "ec-1")
    resp = client.get("/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 503
    assert resp.json()["detail"] == "auth_keys_unavailable"
