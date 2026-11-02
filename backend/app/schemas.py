"""Request and response bodies for the HTTP API."""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, Field

from app.domain import AttendanceSource, AttendanceStatus, Reason, Role


class ProfileIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=100)
    roll_number: str | None = Field(default=None, min_length=1, max_length=32)


class ProfileOut(BaseModel):
    id: UUID
    role: Role
    full_name: str
    roll_number: str | None
    email: str | None


class ClassroomIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class ClassroomOut(BaseModel):
    id: UUID
    name: str
    join_code: str


class JoinIn(BaseModel):
    join_code: str = Field(min_length=4, max_length=12)


class DeviceIn(BaseModel):
    """Public key is base64 SubjectPublicKeyInfo DER for an ECDSA P-256 key."""

    public_key: str = Field(min_length=1, max_length=512)
    label: str | None = Field(default=None, max_length=100)


class DeviceOut(BaseModel):
    id: UUID
    label: str | None


class SessionIn(BaseModel):
    classroom_id: UUID
    rssi_threshold_dbm: int = Field(default=-75, ge=-100, le=-30)
    sample_window_seconds: int = Field(default=4, ge=1, le=30)
    min_samples: int = Field(default=3, ge=1, le=50)


class SessionOut(BaseModel):
    id: UUID
    classroom_id: UUID
    alias: str
    rssi_threshold_dbm: int
    sample_window_seconds: int
    min_samples: int
    started_at: AwareDatetime
    ended_at: AwareDatetime | None


class TokenOut(BaseModel):
    token_hex: str
    epoch: int
    period_seconds: int
    expires_at: AwareDatetime


class ChallengeIn(BaseModel):
    token_hex: str = Field(min_length=2, max_length=64)


class ChallengeOut(BaseModel):
    nonce: UUID
    session_id: UUID
    rssi_threshold_dbm: int
    sample_window_seconds: int
    min_samples: int
    expires_at: AwareDatetime


class ClaimIn(BaseModel):
    nonce: UUID
    token_hex: str = Field(min_length=2, max_length=64)
    median_rssi: int = Field(ge=-127, le=0)
    sample_count: int = Field(ge=1, le=500)
    observed_at: AwareDatetime
    signature: str = Field(min_length=1, max_length=256)


class AttendanceOut(BaseModel):
    session_id: UUID
    student_id: UUID
    status: AttendanceStatus
    source: AttendanceSource
    median_rssi: int | None
    recorded_at: AwareDatetime


class ClaimOut(BaseModel):
    status: Literal["accepted"] = "accepted"
    duplicate_retry: bool = False
    attendance: AttendanceOut


class RejectionDetail(BaseModel):
    status: Literal["rejected"] = "rejected"
    reason: Reason


class RosterRowOut(BaseModel):
    student_id: UUID
    full_name: str
    roll_number: str | None
    status: AttendanceStatus | None
    source: AttendanceSource | None
    median_rssi: int | None
    recorded_at: AwareDatetime | None


class CorrectionIn(BaseModel):
    student_id: UUID
    status: AttendanceStatus
    reason: str = Field(min_length=5, max_length=500)
