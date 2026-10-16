"""Teacher operations: sessions, rotating tokens, roster, corrections and export."""

from __future__ import annotations

import csv
import io
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Response, status

from app import tokens
from app.config import Settings
from app.db import ActiveSessionExists, Database
from app.domain import AttendanceStatus, Profile, Session
from app.schemas import (
    AttendanceOut,
    CorrectionIn,
    RosterRowOut,
    SessionIn,
    SessionOut,
    TokenOut,
)
from app.security import get_db, get_now, get_settings, require_teacher

router = APIRouter(prefix="/v1/sessions", tags=["sessions"])

Db = Annotated[Database, Depends(get_db)]
Teacher = Annotated[Profile, Depends(require_teacher)]
Now = Annotated[datetime, Depends(get_now)]


def _session_out(s: Session) -> SessionOut:
    return SessionOut(
        id=s.id,
        classroom_id=s.classroom_id,
        alias=s.alias,
        rssi_threshold_dbm=s.rssi_threshold_dbm,
        sample_window_seconds=s.sample_window_seconds,
        min_samples=s.min_samples,
        started_at=s.started_at,
        ended_at=s.ended_at,
    )


def owned_session(session_id: UUID, teacher: Profile, db: Database) -> Session:
    """Load a session the teacher owns. Others get 404 so session ids do not leak."""
    session = db.get_session(session_id)
    classroom = db.get_classroom(session.classroom_id) if session else None
    if session is None or classroom is None or classroom.teacher_id != teacher.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="session_not_found")
    return session


@router.post("", response_model=SessionOut, status_code=status.HTTP_201_CREATED)
def start_session(body: SessionIn, teacher: Teacher, db: Db) -> SessionOut:
    classroom = db.get_classroom(body.classroom_id)
    if classroom is None or classroom.teacher_id != teacher.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="classroom_not_found")
    try:
        session = db.create_session(
            classroom.id,
            teacher.id,
            rssi_threshold_dbm=body.rssi_threshold_dbm,
            sample_window_seconds=body.sample_window_seconds,
            min_samples=body.min_samples,
        )
    except ActiveSessionExists:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="active_session_exists") from None
    return _session_out(session)


@router.post("/{session_id}/end", response_model=SessionOut)
def end_session(session_id: UUID, teacher: Teacher, db: Db) -> SessionOut:
    session = owned_session(session_id, teacher, db)
    ended = db.end_session(session.id, teacher.id)
    if ended is None:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="session_already_ended")
    return _session_out(ended)


@router.get("/{session_id}/token", response_model=TokenOut)
def current_token(
    session_id: UUID,
    teacher: Teacher,
    db: Db,
    settings: Annotated[Settings, Depends(get_settings)],
    now: Now,
) -> TokenOut:
    """The token for the teacher phone to advertise right now. Fetch again each period."""
    session = owned_session(session_id, teacher, db)
    if not session.active:
        raise HTTPException(status.HTTP_409_CONFLICT, detail="session_not_active")
    period = settings.token_period_seconds
    epoch = tokens.epoch_for(now.timestamp(), period)
    raw = tokens.make_token(settings.token_hmac_secret.encode(), session.id, session.alias, epoch)
    return TokenOut(
        token_hex=raw.hex(),
        epoch=epoch,
        period_seconds=period,
        expires_at=datetime.fromtimestamp((epoch + 1) * period, tz=UTC),
    )


@router.get("/{session_id}/roster", response_model=list[RosterRowOut])
def roster(session_id: UUID, teacher: Teacher, db: Db) -> list[RosterRowOut]:
    session = owned_session(session_id, teacher, db)
    return [
        RosterRowOut(
            student_id=r.student_id,
            full_name=r.full_name,
            roll_number=r.roll_number,
            status=r.status,
            source=r.source,
            median_rssi=r.median_rssi,
            recorded_at=r.recorded_at,
        )
        for r in db.roster(session)
    ]


@router.post("/{session_id}/corrections", response_model=AttendanceOut)
def correct(session_id: UUID, body: CorrectionIn, teacher: Teacher, db: Db) -> AttendanceOut:
    """Manual correction. A reason is mandatory and the change is audited."""
    session = owned_session(session_id, teacher, db)
    if not db.is_enrolled(session.classroom_id, body.student_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="student_not_enrolled")
    record = db.correct_attendance(
        session.id, body.student_id, body.status, body.reason.strip(), teacher.id
    )
    return AttendanceOut(
        session_id=record.session_id,
        student_id=record.student_id,
        status=record.status,
        source=record.source,
        median_rssi=record.median_rssi,
        recorded_at=record.created_at,
    )


def _safe_cell(value: str) -> str:
    """Stop spreadsheet formula injection from names typed by students."""
    return "'" + value if value[:1] in ("=", "+", "-", "@", "\t", "\r") else value


@router.get("/{session_id}/export.csv")
def export_csv(session_id: UUID, teacher: Teacher, db: Db) -> Response:
    session = owned_session(session_id, teacher, db)
    classroom = db.get_classroom(session.classroom_id)
    assert classroom is not None
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        [
            "Classroom",
            "Session Start",
            "Name",
            "Roll Number",
            "Status",
            "Source",
            "Median RSSI (dBm)",
            "Recorded At",
        ]  # fmt: skip
    )
    for r in db.roster(session):
        writer.writerow(
            [
                _safe_cell(classroom.name),
                session.started_at.isoformat(),
                _safe_cell(r.full_name),
                _safe_cell(r.roll_number or ""),
                (r.status or AttendanceStatus.ABSENT).value,
                r.source.value if r.source else "no_record",
                r.median_rssi if r.median_rssi is not None else "",
                r.recorded_at.isoformat() if r.recorded_at else "",
            ]
        )
    db.audit("export_downloaded", teacher.id, "session", session.id)
    return Response(
        buffer.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="attendance_{session.id}.csv"'},
    )
