"""Plain domain types shared by the database layer and the API."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class Role(StrEnum):
    TEACHER = "teacher"
    STUDENT = "student"


class AttendanceStatus(StrEnum):
    PRESENT = "present"
    ABSENT = "absent"


class AttendanceSource(StrEnum):
    BLE_CLAIM = "ble_claim"
    MANUAL_CORRECTION = "manual_correction"


class Reason(StrEnum):
    """Why a claim or challenge request was rejected."""

    INVALID_TOKEN = "invalid_token"
    TOKEN_EXPIRED = "token_expired"
    SESSION_NOT_ACTIVE = "session_not_active"
    NOT_ENROLLED = "not_enrolled"
    NO_DEVICE_BOUND = "no_device_bound"
    CHALLENGE_UNKNOWN = "challenge_unknown"
    CHALLENGE_EXPIRED = "challenge_expired"
    NONCE_REUSED = "nonce_reused"
    TOKEN_MISMATCH = "token_mismatch"
    CLAIM_STALE = "claim_stale"
    TOO_FEW_SAMPLES = "too_few_samples"
    RSSI_BELOW_THRESHOLD = "rssi_below_threshold"
    BAD_SIGNATURE = "bad_signature"
    DUPLICATE = "duplicate"


@dataclass(frozen=True, slots=True)
class Profile:
    id: UUID
    role: Role
    full_name: str
    roll_number: str | None
    email: str | None


@dataclass(frozen=True, slots=True)
class Classroom:
    id: UUID
    teacher_id: UUID
    name: str
    join_code: str


@dataclass(frozen=True, slots=True)
class Device:
    id: UUID
    student_id: UUID
    public_key: str
    label: str | None


@dataclass(frozen=True, slots=True)
class Session:
    id: UUID
    classroom_id: UUID
    alias: str
    rssi_threshold_dbm: int
    sample_window_seconds: int
    min_samples: int
    started_at: datetime
    ended_at: datetime | None

    @property
    def active(self) -> bool:
        return self.ended_at is None


@dataclass(frozen=True, slots=True)
class Challenge:
    id: UUID
    session_id: UUID
    student_id: UUID
    token_hex: str
    issued_at: datetime
    expires_at: datetime
    used_at: datetime | None


@dataclass(frozen=True, slots=True)
class Attendance:
    id: UUID
    session_id: UUID
    student_id: UUID
    status: AttendanceStatus
    source: AttendanceSource
    median_rssi: int | None
    sample_count: int | None
    observed_at: datetime | None
    device_id: UUID | None
    challenge_id: UUID | None
    created_at: datetime
    corrected_by: UUID | None
    correction_reason: str | None


@dataclass(frozen=True, slots=True)
class RosterRow:
    student_id: UUID
    full_name: str
    roll_number: str | None
    status: AttendanceStatus | None
    source: AttendanceSource | None
    median_rssi: int | None
    recorded_at: datetime | None
