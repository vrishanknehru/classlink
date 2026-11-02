"""Shared fixtures. Tests run against a real Postgres.

Set CLASSLINK_TEST_DATABASE_URL (CI does, via a service container). Without it, a
throwaway local cluster is started if Postgres binaries are installed, otherwise the
database tests are skipped.
"""

from __future__ import annotations

import base64
import glob
import os
import shutil
import socket
import subprocess
import tempfile
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

import jwt
import psycopg
import pytest
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app import crypto
from app.config import Settings
from app.db import Database
from app.main import create_app

MIGRATION = Path(__file__).resolve().parent.parent / "migrations" / "0001_init.sql"
JWT_SECRET = "test-jwt-secret-0123456789abcdef"
HMAC_SECRET = "test-hmac-secret-0123456789abcdef"
START = datetime(2026, 10, 15, 12, 0, 0, tzinfo=UTC)

# Minimal stand in for the pieces of Supabase that the migration depends on.
SUPABASE_STUB = """
create schema if not exists auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
do $$ begin
  if not exists (select from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;
grant usage on schema auth, public to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
"""


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return int(s.getsockname()[1])


def _pg_bin() -> str | None:
    found = shutil.which("initdb")
    if found:
        return str(Path(found).parent)
    candidates = sorted(glob.glob("/usr/lib/postgresql/*/bin/initdb"))
    return str(Path(candidates[-1]).parent) if candidates else None


@pytest.fixture(scope="session")
def pg_url() -> Iterator[str]:
    url = os.environ.get("CLASSLINK_TEST_DATABASE_URL")
    if url:
        yield url
        return
    bindir = _pg_bin()
    if bindir is None:
        pytest.skip("no Postgres available; set CLASSLINK_TEST_DATABASE_URL")
    root = os.geteuid() == 0
    base = Path(tempfile.mkdtemp(prefix="classlink-pg-"))
    base.chmod(0o755)
    if root:
        shutil.chown(base, user="postgres")
    prefix = ["runuser", "-u", "postgres", "--"] if root else []
    data = base / "data"
    port = _free_port()
    subprocess.run(
        [*prefix, f"{bindir}/initdb", "-D", str(data), "-A", "trust", "-U", "postgres", "-E", "UTF8"],
        check=True, capture_output=True,
    )  # fmt: skip
    subprocess.run(
        [*prefix, f"{bindir}/pg_ctl", "-D", str(data), "-w", "-l", str(base / "log"),
         "-o", f"-p {port} -k {base} -c listen_addresses=127.0.0.1", "start"],
        check=True, capture_output=True,
    )  # fmt: skip
    try:
        yield f"postgresql://postgres@127.0.0.1:{port}/postgres"
    finally:
        subprocess.run(
            [*prefix, f"{bindir}/pg_ctl", "-D", str(data), "-m", "immediate", "stop"],
            capture_output=True,
        )
        shutil.rmtree(base, ignore_errors=True)


@pytest.fixture(scope="session")
def migrated_url(pg_url: str) -> str:
    deadline = time.time() + 20
    while True:
        try:
            conn = psycopg.connect(pg_url, autocommit=True)
            break
        except psycopg.OperationalError:
            if time.time() > deadline:
                raise
            time.sleep(0.3)
    with conn:
        conn.execute("drop schema if exists public cascade")
        conn.execute("drop schema if exists auth cascade")
        conn.execute("create schema public")
        conn.execute(SUPABASE_STUB)
        conn.execute(MIGRATION.read_text())
    return pg_url


@pytest.fixture(scope="session")
def db(migrated_url: str) -> Iterator[Database]:
    database = Database(migrated_url)
    database.open()
    yield database
    database.close()


@pytest.fixture(autouse=True)
def _clean(request: pytest.FixtureRequest) -> None:
    if "db" not in request.fixturenames and "client" not in request.fixturenames:
        return
    url = request.getfixturevalue("migrated_url")
    with psycopg.connect(url, autocommit=True) as conn:
        conn.execute("truncate auth.users cascade")
        conn.execute("truncate audit_events restart identity")


class FakeClock:
    def __init__(self) -> None:
        self.now = START

    def __call__(self) -> datetime:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += timedelta(seconds=seconds)


@pytest.fixture
def clock() -> FakeClock:
    return FakeClock()


@pytest.fixture
def settings(migrated_url: str) -> Settings:
    return Settings(
        database_url=migrated_url,
        jwt_secret=JWT_SECRET,
        token_hmac_secret=HMAC_SECRET,
        teacher_emails=["teacher@example.edu"],
    )


@pytest.fixture
def client(settings: Settings, db: Database, clock: FakeClock) -> TestClient:
    # No `with`: the pool is shared across the session, so skip the app lifespan.
    return TestClient(create_app(settings, db, clock))


@dataclass
class DeviceKey:
    private: ec.EllipticCurvePrivateKey = field(
        default_factory=lambda: ec.generate_private_key(ec.SECP256R1())
    )

    @property
    def public_b64(self) -> str:
        der = self.private.public_key().public_bytes(
            serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
        )
        return base64.b64encode(der).decode()

    def sign(self, message: bytes) -> str:
        return base64.b64encode(self.private.sign(message, ec.ECDSA(hashes.SHA256()))).decode()


@dataclass
class User:
    id: UUID
    email: str
    headers: dict[str, str]


def make_jwt(
    user_id: UUID, email: str, *, secret: str = JWT_SECRET, aud: str = "authenticated"
) -> str:
    claims = {"sub": str(user_id), "email": email, "aud": aud, "exp": int(time.time()) + 3600}
    return jwt.encode(claims, secret, algorithm="HS256")


@pytest.fixture
def new_user(migrated_url: str, client: TestClient) -> Callable[..., User]:
    """Create an auth.users row (what Supabase sign up does) and its API profile."""

    def factory(
        email: str, name: str = "Test User", roll: str | None = None, *, create_profile: bool = True
    ) -> User:
        user_id = uuid4()
        with psycopg.connect(migrated_url, autocommit=True) as conn:
            conn.execute("insert into auth.users (id, email) values (%s, %s)", (user_id, email))
        user = User(user_id, email, {"Authorization": f"Bearer {make_jwt(user_id, email)}"})
        if create_profile:
            body: dict[str, Any] = {"full_name": name}
            if roll:
                body["roll_number"] = roll
            resp = client.post("/v1/profile", json=body, headers=user.headers)
            assert resp.status_code == 200, resp.text
        return user

    return factory


@dataclass
class World:
    """A teacher, a classroom, an enrolled student with a bound device, and a live session."""

    client: TestClient
    clock: FakeClock
    teacher: User
    student: User
    key: DeviceKey
    classroom: dict[str, Any]
    session: dict[str, Any]

    def token(self) -> str:
        resp = self.client.get(
            f"/v1/sessions/{self.session['id']}/token", headers=self.teacher.headers
        )
        assert resp.status_code == 200, resp.text
        return str(resp.json()["token_hex"])

    def challenge(self, token_hex: str | None = None, user: User | None = None) -> Any:
        return self.client.post(
            "/v1/attendance/challenge",
            json={"token_hex": token_hex or self.token()},
            headers=(user or self.student).headers,
        )

    def claim_body(
        self,
        challenge: dict[str, Any],
        token_hex: str,
        *,
        rssi: int = -60,
        samples: int = 5,
        observed_at: datetime | None = None,
        key: DeviceKey | None = None,
    ) -> dict[str, Any]:
        observed = observed_at or self.clock.now
        message = crypto.canonical_claim(
            session_id=UUID(challenge["session_id"]),
            nonce=UUID(challenge["nonce"]),
            token_hex=token_hex,
            median_rssi=rssi,
            sample_count=samples,
            observed_at=observed,
        )
        return {
            "nonce": challenge["nonce"],
            "token_hex": token_hex,
            "median_rssi": rssi,
            "sample_count": samples,
            "observed_at": observed.isoformat(),
            "signature": (key or self.key).sign(message),
        }

    def claim(self, body: dict[str, Any], user: User | None = None) -> Any:
        return self.client.post(
            "/v1/attendance/claim", json=body, headers=(user or self.student).headers
        )

    def check_in(self, **kwargs: Any) -> Any:
        token_hex = self.token()
        resp = self.challenge(token_hex)
        assert resp.status_code == 200, resp.text
        return self.claim(self.claim_body(resp.json(), token_hex, **kwargs))


@pytest.fixture
def world(client: TestClient, clock: FakeClock, new_user: Callable[..., User]) -> World:
    teacher = new_user("teacher@example.edu", "Dr. Teacher")
    student = new_user("ada@example.edu", "Ada Lovelace", "1024160001")
    classroom = client.post(
        "/v1/classrooms", json={"name": "UCS503P"}, headers=teacher.headers
    ).json()
    joined = client.post(
        "/v1/classrooms/join", json={"join_code": classroom["join_code"]}, headers=student.headers
    )
    assert joined.status_code == 200, joined.text
    key = DeviceKey()
    bound = client.put(
        "/v1/devices/me",
        json={"public_key": key.public_b64, "label": "Pixel"},
        headers=student.headers,
    )
    assert bound.status_code == 200, bound.text
    session = client.post(
        "/v1/sessions", json={"classroom_id": classroom["id"]}, headers=teacher.headers
    ).json()
    return World(client, clock, teacher, student, key, classroom, session)
