"""Postgres access for the ClassLink backend (Supabase Postgres in production).

The backend connects with a privileged role, so every authorization decision
is made in the API layer. Row level security (see migrations) protects the
same tables against direct client access.
"""

from __future__ import annotations

import json
import secrets
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import datetime
from typing import Any
from uuid import UUID

import psycopg
from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb
from psycopg_pool import ConnectionPool

from app.domain import (
    Attendance,
    AttendanceSource,
    AttendanceStatus,
    Challenge,
    Classroom,
    Device,
    Profile,
    Role,
    RosterRow,
    Session,
)

Row = dict[str, Any]

_JOIN_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I


class ActiveSessionExists(Exception):
    """The classroom already has a live session."""


class NonceAlreadyUsed(Exception):
    """The challenge was consumed by a different claim."""


class DuplicateAttendance(Exception):
    """The student already has a record for this session."""


def _profile(r: Row) -> Profile:
    return Profile(r["id"], Role(r["role"]), r["full_name"], r["roll_number"], r["email"])


def _classroom(r: Row) -> Classroom:
    return Classroom(r["id"], r["teacher_id"], r["name"], r["join_code"])


def _session(r: Row) -> Session:
    return Session(
        r["id"],
        r["classroom_id"],
        r["alias"],
        r["rssi_threshold_dbm"],
        r["sample_window_seconds"],
        r["min_samples"],
        r["started_at"],
        r["ended_at"],
    )


def _challenge(r: Row) -> Challenge:
    return Challenge(
        r["id"], r["session_id"], r["student_id"], r["token_hex"],
        r["issued_at"], r["expires_at"], r["used_at"],
    )  # fmt: skip


def _attendance(r: Row) -> Attendance:
    return Attendance(
        r["id"],
        r["session_id"],
        r["student_id"],
        AttendanceStatus(r["status"]),
        AttendanceSource(r["source"]),
        r["median_rssi"],
        r["sample_count"],
        r["observed_at"],
        r["device_id"],
        r["challenge_id"],
        r["created_at"],
        r["corrected_by"],
        r["correction_reason"],
    )


def _audit(
    conn: psycopg.Connection[Row],
    action: str,
    actor_id: UUID | None,
    subject_type: str,
    subject_id: object,
    details: dict[str, Any] | None = None,
) -> None:
    conn.execute(
        "insert into audit_events (actor_id, action, subject_type, subject_id, details) "
        "values (%s, %s, %s, %s, %s)",
        (actor_id, action, subject_type, str(subject_id), Jsonb(details or {}, dumps=_dumps)),
    )


def _dumps(value: object) -> str:
    return json.dumps(value, default=str)


class Database:
    def __init__(self, database_url: str, *, max_size: int = 10) -> None:
        self._pool: ConnectionPool[psycopg.Connection[Row]] = ConnectionPool(
            database_url,
            min_size=1,
            max_size=max_size,
            kwargs={"row_factory": dict_row, "autocommit": True},
            open=False,
        )

    def open(self) -> None:
        self._pool.open(wait=True, timeout=15)

    def close(self) -> None:
        self._pool.close()

    @contextmanager
    def _conn(self) -> Iterator[psycopg.Connection[Row]]:
        with self._pool.connection() as conn:
            yield conn

    def ping(self) -> bool:
        with self._conn() as conn:
            return conn.execute("select 1 as ok").fetchone() == {"ok": 1}

    # --- profiles -------------------------------------------------------
    def get_profile(self, user_id: UUID) -> Profile | None:
        with self._conn() as conn:
            row = conn.execute("select * from profiles where id = %s", (user_id,)).fetchone()
        return _profile(row) if row else None

    def create_profile(self, profile: Profile) -> Profile:
        with self._conn() as conn:
            conn.execute(
                "insert into profiles (id, role, full_name, roll_number, email) "
                "values (%s, %s, %s, %s, %s) on conflict (id) do nothing",
                (profile.id, profile.role.value, profile.full_name, profile.roll_number,
                 profile.email),
            )  # fmt: skip
        stored = self.get_profile(profile.id)
        assert stored is not None
        return stored

    # --- classrooms and enrollment ----------------------------------------
    def create_classroom(self, teacher_id: UUID, name: str) -> Classroom:
        with self._conn() as conn:
            for _ in range(10):
                code = "".join(secrets.choice(_JOIN_CODE_ALPHABET) for _ in range(6))
                try:
                    with conn.transaction():
                        row = conn.execute(
                            "insert into classrooms (teacher_id, name, join_code) "
                            "values (%s, %s, %s) returning *",
                            (teacher_id, name, code),
                        ).fetchone()
                        assert row is not None
                        _audit(conn, "classroom_created", teacher_id, "classroom", row["id"])
                        return _classroom(row)
                except errors.UniqueViolation:
                    continue
        raise RuntimeError("could not allocate a unique join code")

    def get_classroom(self, classroom_id: UUID) -> Classroom | None:
        with self._conn() as conn:
            row = conn.execute("select * from classrooms where id = %s", (classroom_id,)).fetchone()
        return _classroom(row) if row else None

    def classroom_by_join_code(self, code: str) -> Classroom | None:
        with self._conn() as conn:
            row = conn.execute(
                "select * from classrooms where join_code = %s", (code.upper(),)
            ).fetchone()
        return _classroom(row) if row else None

    def list_classrooms_for_teacher(self, teacher_id: UUID) -> list[Classroom]:
        with self._conn() as conn:
            rows = conn.execute(
                "select * from classrooms where teacher_id = %s order by created_at", (teacher_id,)
            ).fetchall()
        return [_classroom(r) for r in rows]

    def list_classrooms_for_student(self, student_id: UUID) -> list[Classroom]:
        with self._conn() as conn:
            rows = conn.execute(
                "select c.* from classrooms c join enrollments e on e.classroom_id = c.id "
                "where e.student_id = %s order by e.joined_at",
                (student_id,),
            ).fetchall()
        return [_classroom(r) for r in rows]

    def enroll(self, classroom_id: UUID, student_id: UUID) -> bool:
        with self._conn() as conn:
            cur = conn.execute(
                "insert into enrollments (classroom_id, student_id) values (%s, %s) "
                "on conflict do nothing",
                (classroom_id, student_id),
            )
            return cur.rowcount == 1

    def is_enrolled(self, classroom_id: UUID, student_id: UUID) -> bool:
        with self._conn() as conn:
            row = conn.execute(
                "select 1 from enrollments where classroom_id = %s and student_id = %s",
                (classroom_id, student_id),
            ).fetchone()
        return row is not None

    # --- devices ----------------------------------------------------------
    def bind_device(self, student_id: UUID, public_key: str, label: str | None) -> Device:
        """Bind a new device key. Any earlier active key is revoked in the same transaction."""
        with self._conn() as conn, conn.transaction():
            revoked = conn.execute(
                "update devices set revoked_at = now() "
                "where student_id = %s and revoked_at is null",
                (student_id,),
            ).rowcount
            row = conn.execute(
                "insert into devices (student_id, public_key, label) values (%s, %s, %s) "
                "returning *",
                (student_id, public_key, label),
            ).fetchone()
            assert row is not None
            _audit(conn, "device_bound", student_id, "device", row["id"],
                   {"replaced_previous": revoked > 0})  # fmt: skip
        return Device(row["id"], row["student_id"], row["public_key"], row["label"])

    def active_device(self, student_id: UUID) -> Device | None:
        with self._conn() as conn:
            row = conn.execute(
                "select * from devices where student_id = %s and revoked_at is null", (student_id,)
            ).fetchone()
        return (
            Device(row["id"], row["student_id"], row["public_key"], row["label"]) if row else None
        )

    # --- sessions ---------------------------------------------------------
    def create_session(
        self,
        classroom_id: UUID,
        actor_id: UUID,
        *,
        rssi_threshold_dbm: int,
        sample_window_seconds: int,
        min_samples: int,
    ) -> Session:
        with self._conn() as conn:
            for _ in range(10):
                alias = secrets.token_hex(4)
                try:
                    with conn.transaction():
                        row = conn.execute(
                            "insert into sessions (classroom_id, alias, rssi_threshold_dbm, "
                            "sample_window_seconds, min_samples) values (%s, %s, %s, %s, %s) "
                            "returning *",
                            (classroom_id, alias, rssi_threshold_dbm, sample_window_seconds,
                             min_samples),
                        ).fetchone()  # fmt: skip
                        assert row is not None
                        _audit(conn, "session_started", actor_id, "session", row["id"],
                               {"rssi_threshold_dbm": rssi_threshold_dbm})  # fmt: skip
                        return _session(row)
                except errors.UniqueViolation as exc:
                    if exc.diag.constraint_name == "sessions_one_active_per_classroom":
                        raise ActiveSessionExists from exc
                    continue  # alias collision, pick another
        raise RuntimeError("could not allocate a unique session alias")

    def get_session(self, session_id: UUID) -> Session | None:
        with self._conn() as conn:
            row = conn.execute("select * from sessions where id = %s", (session_id,)).fetchone()
        return _session(row) if row else None

    def active_session_by_alias(self, alias: str) -> Session | None:
        with self._conn() as conn:
            row = conn.execute(
                "select * from sessions where alias = %s and ended_at is null", (alias,)
            ).fetchone()
        return _session(row) if row else None

    def end_session(self, session_id: UUID, actor_id: UUID) -> Session | None:
        with self._conn() as conn, conn.transaction():
            row = conn.execute(
                "update sessions set ended_at = now() where id = %s and ended_at is null "
                "returning *",
                (session_id,),
            ).fetchone()
            if row is None:
                return None
            _audit(conn, "session_ended", actor_id, "session", session_id)
        return _session(row)

    # --- challenges -------------------------------------------------------
    def create_challenge(
        self, session_id: UUID, student_id: UUID, token_hex: str, issued_at: datetime,
        expires_at: datetime,
    ) -> Challenge:  # fmt: skip
        with self._conn() as conn:
            row = conn.execute(
                "insert into challenges (session_id, student_id, token_hex, issued_at, expires_at) "
                "values (%s, %s, %s, %s, %s) returning *",
                (session_id, student_id, token_hex, issued_at, expires_at),
            ).fetchone()
        assert row is not None
        return _challenge(row)

    def get_challenge(self, challenge_id: UUID) -> Challenge | None:
        with self._conn() as conn:
            row = conn.execute("select * from challenges where id = %s", (challenge_id,)).fetchone()
        return _challenge(row) if row else None

    # --- attendance -------------------------------------------------------
    def attendance_for_challenge(self, challenge_id: UUID) -> Attendance | None:
        with self._conn() as conn:
            row = conn.execute(
                "select * from attendance where challenge_id = %s", (challenge_id,)
            ).fetchone()
        return _attendance(row) if row else None

    def accept_claim(
        self,
        challenge: Challenge,
        *,
        device_id: UUID,
        median_rssi: int,
        sample_count: int,
        observed_at: datetime,
        now: datetime,
    ) -> tuple[Attendance, bool]:
        """Consume the challenge and record attendance atomically.

        Returns (record, created). A retry of an already accepted claim returns the stored
        record with created=False. Raises NonceAlreadyUsed if another claim consumed the
        challenge, and DuplicateAttendance if the student is already present in this session;
        in both cases nothing is written.
        """
        with self._conn() as conn:
            try:
                with conn.transaction():
                    consumed = conn.execute(
                        "update challenges set used_at = %s where id = %s and used_at is null "
                        "returning id",
                        (now, challenge.id),
                    ).fetchone()
                    if consumed is None:
                        raise NonceAlreadyUsed
                    row = conn.execute(
                        "insert into attendance (session_id, student_id, status, source, "
                        "median_rssi, sample_count, observed_at, device_id, challenge_id) "
                        "values (%s, %s, 'present', 'ble_claim', %s, %s, %s, %s, %s) "
                        "on conflict (session_id, student_id) do nothing returning *",
                        (challenge.session_id, challenge.student_id, median_rssi, sample_count,
                         observed_at, device_id, challenge.id),
                    ).fetchone()  # fmt: skip
                    if row is None:
                        raise DuplicateAttendance
                    _audit(conn, "claim_accepted", challenge.student_id, "session",
                           challenge.session_id, {"median_rssi": median_rssi})  # fmt: skip
                    return _attendance(row), True
            except NonceAlreadyUsed:
                existing = self.attendance_for_challenge(challenge.id)
                if existing is not None:
                    return existing, False
                raise

    def list_attendance(self, session_id: UUID) -> list[Attendance]:
        with self._conn() as conn:
            rows = conn.execute(
                "select * from attendance where session_id = %s order by created_at", (session_id,)
            ).fetchall()
        return [_attendance(r) for r in rows]

    def roster(self, session: Session) -> list[RosterRow]:
        with self._conn() as conn:
            rows = conn.execute(
                "select p.id, p.full_name, p.roll_number, a.status, a.source, a.median_rssi, "
                "a.created_at from enrollments e join profiles p on p.id = e.student_id "
                "left join attendance a on a.student_id = p.id and a.session_id = %s "
                "where e.classroom_id = %s order by p.roll_number, p.full_name",
                (session.id, session.classroom_id),
            ).fetchall()
        return [
            RosterRow(
                r["id"],
                r["full_name"],
                r["roll_number"],
                AttendanceStatus(r["status"]) if r["status"] else None,
                AttendanceSource(r["source"]) if r["source"] else None,
                r["median_rssi"],
                r["created_at"],
            )  # fmt: skip
            for r in rows
        ]

    def correct_attendance(
        self,
        session_id: UUID,
        student_id: UUID,
        status: AttendanceStatus,
        reason: str,
        actor_id: UUID,
    ) -> Attendance:
        with self._conn() as conn, conn.transaction():
            previous = conn.execute(
                "select status from attendance where session_id = %s and student_id = %s",
                (session_id, student_id),
            ).fetchone()
            row = conn.execute(
                "insert into attendance (session_id, student_id, status, source, corrected_by, "
                "correction_reason) values (%s, %s, %s, 'manual_correction', %s, %s) "
                "on conflict (session_id, student_id) do update set status = excluded.status, "
                "source = 'manual_correction', corrected_by = excluded.corrected_by, "
                "correction_reason = excluded.correction_reason returning *",
                (session_id, student_id, status.value, actor_id, reason),
            ).fetchone()
            assert row is not None
            _audit(conn, "manual_correction", actor_id, "session", session_id, {
                "student_id": student_id,
                "from": previous["status"] if previous else None,
                "to": status.value,
                "reason": reason,
            })  # fmt: skip
        return _attendance(row)

    # --- audit ------------------------------------------------------------
    def audit(
        self,
        action: str,
        actor_id: UUID | None,
        subject_type: str,
        subject_id: object,
        details: dict[str, Any] | None = None,
    ) -> None:
        with self._conn() as conn:
            _audit(conn, action, actor_id, subject_type, subject_id, details)

    def list_audit(self, subject_type: str, subject_id: object) -> list[Row]:
        with self._conn() as conn:
            return conn.execute(
                "select action, actor_id, details, created_at from audit_events "
                "where subject_type = %s and subject_id = %s order by id",
                (subject_type, str(subject_id)),
            ).fetchall()
