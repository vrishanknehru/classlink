"""Verify Supabase access tokens.

Supabase signs user tokens with an asymmetric key (ES256 or RS256) and publishes
the public keys at `<SUPABASE_URL>/auth/v1/.well-known/jwks.json`. The keys are
fetched once and cached. Projects still on the legacy shared secret sign with
HS256; that path is used only when `CLASSLINK_JWT_SECRET` is set.
"""

from __future__ import annotations

from typing import Any

import jwt

from app.config import Settings

ASYMMETRIC_ALGORITHMS = frozenset({"ES256", "RS256"})
_REQUIRED_CLAIMS = ["exp", "sub"]


class InvalidToken(Exception):
    """The token is malformed, expired, or not signed by a trusted key."""


class SigningKeysUnavailable(Exception):
    """The JWKS endpoint could not be reached, so no token can be checked."""


class TokenVerifier:
    def __init__(
        self,
        *,
        audience: str,
        jwks_client: jwt.PyJWKClient | None = None,
        issuer: str | None = None,
        hs256_secret: str | None = None,
    ) -> None:
        if jwks_client is None and hs256_secret is None:
            raise ValueError("need a JWKS client or an HS256 secret")
        self._audience = audience
        self._jwks = jwks_client
        self._issuer = issuer
        self._secret = hs256_secret

    @classmethod
    def from_settings(cls, settings: Settings) -> TokenVerifier:
        jwks = None
        if settings.jwks_url is not None:
            jwks = jwt.PyJWKClient(
                settings.jwks_url,
                cache_jwk_set=True,
                lifespan=settings.jwks_cache_seconds,
                timeout=10,
            )
        return cls(
            audience=settings.jwt_audience,
            jwks_client=jwks,
            issuer=settings.jwt_issuer,
            hs256_secret=settings.jwt_secret,
        )

    def verify(self, token: str) -> dict[str, Any]:
        """Return the token's claims, or raise InvalidToken / SigningKeysUnavailable."""
        try:
            alg = jwt.get_unverified_header(token).get("alg")
            if alg in ASYMMETRIC_ALGORITHMS and self._jwks is not None:
                return self._verify_with_jwks(token, str(alg), self._jwks)
            if alg == "HS256" and self._secret is not None:
                claims: dict[str, Any] = jwt.decode(
                    token,
                    self._secret,
                    algorithms=["HS256"],
                    audience=self._audience,
                    options={"require": _REQUIRED_CLAIMS},
                )
                return claims
        except jwt.PyJWKClientConnectionError as exc:
            raise SigningKeysUnavailable(str(exc)) from exc
        except jwt.PyJWTError as exc:
            raise InvalidToken(str(exc)) from exc
        raise InvalidToken(f"signing algorithm not accepted: {alg!r}")

    def _verify_with_jwks(self, token: str, alg: str, jwks: jwt.PyJWKClient) -> dict[str, Any]:
        signing_key = jwks.get_signing_key_from_jwt(token)
        # The key decides the algorithm, so a token cannot pick a weaker one.
        if signing_key.algorithm_name != alg:
            raise InvalidToken("token algorithm does not match its key")
        claims: dict[str, Any] = jwt.decode(
            token,
            signing_key.key,
            algorithms=[alg],
            audience=self._audience,
            issuer=self._issuer,
            options={"require": [*_REQUIRED_CLAIMS, "iss"] if self._issuer else _REQUIRED_CLAIMS},
        )
        return claims
