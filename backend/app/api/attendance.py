"""Student attendance: challenge then signed claim. The server decides the result."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Annotated, NoReturn
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status

from app import claims, crypto
from app.config import Settings
from app.db import Database, DuplicateAttendance, NonceAlreadyUsed
from app.domain import Attendance, Profile, Reason
from app.schemas import (
    AttendanceOut,
    ChallengeIn,
    ChallengeOut,
    ClaimIn,
    ClaimOut,
    RejectionDetail,
)
from app.security import get_db, get_now, get_settings, require_student

router = APIRouter(prefix="/v1/attendance", tags=["attendance"])

Db = Annotated[Database, Depends(get_db)]
Student = Annotated[Profile, Depends(require_student)]
Cfg = Annotated[Settings, Depends(get_settings)]
Now = Annotated[datetime, Depends(get_now)]


def _reject(
    db: Database, student: Profile, reason: Reason, stage: str, session_id: UUID | None = None
) -> NoReturn:
    """Audit the rejection and answer 409 with a machine readable reason."""
    db.audit(
        "claim_rejected",
        student.id,
        "session" if session_id else "student",
        session_id or student.id,
        {"reason": reason.value, "stage": stage},
    )
    raise HTTPException(
        status.HTTP_409_CONFLICT, detail=RejectionDetail(reason=reason).model_dump(mode="json")
    )


def _attendance_out(a: Attendance) -> AttendanceOut:
    return AttendanceOut(
        session_id=a.session_id,
        student_id=a.student_id,
        status=a.status,
        source=a.source,
        median_rssi=a.median_rssi,
        recorded_at=a.created_at,
    )


@router.post("/challenge", response_model=ChallengeOut)
def create_challenge(
    body: ChallengeIn, student: Student, db: Db, cfg: Cfg, now: Now
) -> ChallengeOut:
    """Trade a scanned BLE token for a single use nonce and the session's proximity policy."""
    parsed = claims.decode_token_hex(body.token_hex)
    if parsed is None:
        _reject(db, student, Reason.INVALID_TOKEN, "challenge")
    session = db.active_session_by_alias(parsed.alias)
    if session is None:
        _reject(db, student, Reason.SESSION_NOT_ACTIVE, "challenge")
    reason = claims.check_token(
        secret=cfg.token_hmac_secret.encode(),
        session=session,
        parsed=parsed,
        now=now,
        period_seconds=cfg.token_period_seconds,
        grace_epochs=cfg.token_grace_epochs,
    )
    if reason is not None:
        _reject(db, student, reason, "challenge", session.id)
    if not db.is_enrolled(session.classroom_id, student.id):
        _reject(db, student, Reason.NOT_ENROLLED, "challenge", session.id)
    if db.active_device(student.id) is None:
        _reject(db, student, Reason.NO_DEVICE_BOUND, "challenge", session.id)
    expires_at = now + timedelta(seconds=cfg.challenge_ttl_seconds)
    challenge = db.create_challenge(session.id, student.id, body.token_hex.lower(), now, expires_at)
    return ChallengeOut(
        nonce=challenge.id,
        session_id=session.id,
        rssi_threshold_dbm=session.rssi_threshold_dbm,
        sample_window_seconds=session.sample_window_seconds,
        min_samples=session.min_samples,
        expires_at=expires_at,
    )


@router.post("/claim", response_model=ClaimOut)
def submit_claim(body: ClaimIn, student: Student, db: Db, cfg: Cfg, now: Now) -> ClaimOut:
    challenge = db.get_challenge(body.nonce)
    if challenge is None or challenge.student_id != student.id:
        _reject(db, student, Reason.CHALLENGE_UNKNOWN, "claim")
    session = db.get_session(challenge.session_id)
    if session is None or not session.active:
        _reject(db, student, Reason.SESSION_NOT_ACTIVE, "claim", challenge.session_id)

    if challenge.used_at is not None:
        # A retry of an accepted claim is answered from the stored record.
        existing = db.attendance_for_challenge(challenge.id)
        if existing is None:
            _reject(db, student, Reason.NONCE_REUSED, "claim", session.id)
        return ClaimOut(duplicate_retry=True, attendance=_attendance_out(existing))

    reason = claims.check_challenge(challenge, token_hex=body.token_hex, now=now)
    if reason is not None:
        _reject(db, student, reason, "claim", session.id)

    device = db.active_device(student.id)
    if device is None:
        _reject(db, student, Reason.NO_DEVICE_BOUND, "claim", session.id)
    message = crypto.canonical_claim(
        session_id=session.id,
        nonce=challenge.id,
        token_hex=body.token_hex,
        median_rssi=body.median_rssi,
        sample_count=body.sample_count,
        observed_at=body.observed_at,
    )
    if not crypto.verify_signature(device.public_key, message, body.signature):
        _reject(db, student, Reason.BAD_SIGNATURE, "claim", session.id)

    reason = claims.check_freshness(
        observed_at=body.observed_at, now=now, max_age_seconds=cfg.claim_max_age_seconds
    )
    if reason is None:
        reason = claims.check_policy(
            session, sample_count=body.sample_count, median_rssi=body.median_rssi
        )
    if reason is not None:
        _reject(db, student, reason, "claim", session.id)

    try:
        record, created = db.accept_claim(
            challenge,
            device_id=device.id,
            median_rssi=body.median_rssi,
            sample_count=body.sample_count,
            observed_at=body.observed_at,
            now=now,
        )
    except DuplicateAttendance:
        _reject(db, student, Reason.DUPLICATE, "claim", session.id)
    except NonceAlreadyUsed:
        _reject(db, student, Reason.NONCE_REUSED, "claim", session.id)
    return ClaimOut(duplicate_retry=not created, attendance=_attendance_out(record))
