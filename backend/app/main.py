"""Application factory."""

from __future__ import annotations

from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import accounts, attendance, sessions
from app.config import Settings
from app.db import Database


def _utc_now() -> datetime:
    return datetime.now(UTC)


def create_app(
    settings: Settings | None = None,
    db: Database | None = None,
    clock: Callable[[], datetime] | None = None,
) -> FastAPI:
    cfg = settings or Settings()
    database = db or Database(cfg.database_url)

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        database.open()
        try:
            yield
        finally:
            database.close()

    app = FastAPI(title="ClassLink API", version="0.1.0", lifespan=lifespan)
    app.state.settings = cfg
    app.state.db = database
    app.state.clock = clock or _utc_now

    if cfg.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=cfg.cors_origins,
            allow_methods=["GET", "POST", "PUT"],
            allow_headers=["Authorization", "Content-Type"],
        )

    @app.get("/healthz", tags=["ops"])
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz", tags=["ops"])
    def readyz() -> dict[str, str]:
        return {"status": "ready" if database.ping() else "unavailable"}

    app.include_router(accounts.router)
    app.include_router(sessions.router)
    app.include_router(attendance.router)
    return app


def app_from_env() -> FastAPI:
    """Entry point for `uvicorn app.main:app_from_env --factory`."""
    return create_app()
