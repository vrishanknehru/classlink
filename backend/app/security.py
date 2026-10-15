"""Authentication: Supabase issued JWTs, verified with the project JWT secret (HS256)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import Settings
from app.db import Database
from app.domain import Profile, Role

_bearer = HTTPBearer(auto_error=False)


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


def current_user(
    settings: Annotated[Settings, Depends(get_settings)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> AuthUser:
    if credentials is None:
        raise _unauthorized("missing bearer token")
    try:
        claims = jwt.decode(
            credentials.credentials,
            settings.jwt_secret,
            algorithms=["HS256"],
            audience=settings.jwt_audience,
            options={"require": ["exp", "sub"]},
        )
        user_id = UUID(str(claims["sub"]))
    except (jwt.PyJWTError, ValueError) as exc:
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
