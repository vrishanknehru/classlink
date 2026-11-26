"""Authentication: Supabase issued JWTs, checked by the app's TokenVerifier."""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Annotated
from uuid import UUID

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth_tokens import InvalidToken, SigningKeysUnavailable, TokenVerifier
from app.config import Settings
from app.db import Database
from app.domain import Profile, Role

_bearer = HTTPBearer(auto_error=False)
_log = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class AuthUser:
    id: UUID
    email: str | None


def get_settings(request: Request) -> Settings:
    settings: Settings = request.app.state.settings
    return settings


def get_db(request: Request) -> Database:
    db: Database = request.app.state.db
    return db


def get_now(request: Request) -> datetime:
    clock = request.app.state.clock
    now: datetime = clock()
    return now


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status.HTTP_401_UNAUTHORIZED, detail=detail, headers={"WWW-Authenticate": "Bearer"}
    )


def get_token_verifier(request: Request) -> TokenVerifier:
    verifier: TokenVerifier = request.app.state.token_verifier
    return verifier


def current_user(
    verifier: Annotated[TokenVerifier, Depends(get_token_verifier)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> AuthUser:
    if credentials is None:
        raise _unauthorized("missing bearer token")
    try:
        claims = verifier.verify(credentials.credentials)
        user_id = UUID(str(claims["sub"]))
    except SigningKeysUnavailable as exc:
        _log.error("cannot fetch Supabase signing keys: %s", exc)
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="auth_keys_unavailable"
        ) from exc
    except (InvalidToken, ValueError) as exc:
        raise _unauthorized("invalid or expired token") from exc
    email = claims.get("email")
    return AuthUser(id=user_id, email=email.lower() if isinstance(email, str) else None)


def current_profile(
    user: Annotated[AuthUser, Depends(current_user)],
    db: Annotated[Database, Depends(get_db)],
) -> Profile:
    profile = db.get_profile(user.id)
    if profile is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="profile_required")
    return profile


def require_teacher(profile: Annotated[Profile, Depends(current_profile)]) -> Profile:
    if profile.role is not Role.TEACHER:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="teacher_only")
    return profile


def require_student(profile: Annotated[Profile, Depends(current_profile)]) -> Profile:
    if profile.role is not Role.STUDENT:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="student_only")
    return profile
