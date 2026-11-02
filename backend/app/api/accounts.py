"""Profiles, classrooms and device binding."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app import crypto
from app.config import Settings
from app.db import Database
from app.domain import Classroom, Profile, Role
from app.schemas import (
    ClassroomIn,
    ClassroomOut,
    DeviceIn,
    DeviceOut,
    JoinIn,
    ProfileIn,
    ProfileOut,
)
from app.security import (
    AuthUser,
    current_profile,
    current_user,
    get_db,
    get_settings,
    require_student,
    require_teacher,
)

router = APIRouter(prefix="/v1", tags=["accounts"])

Db = Annotated[Database, Depends(get_db)]


def _profile_out(p: Profile) -> ProfileOut:
    return ProfileOut(
        id=p.id, role=p.role, full_name=p.full_name, roll_number=p.roll_number, email=p.email
    )


def _classroom_out(c: Classroom) -> ClassroomOut:
    return ClassroomOut(id=c.id, name=c.name, join_code=c.join_code)


@router.post("/profile", response_model=ProfileOut)
def create_profile(
    body: ProfileIn,
    user: Annotated[AuthUser, Depends(current_user)],
    db: Db,
    settings: Annotated[Settings, Depends(get_settings)],
) -> ProfileOut:
    """Create the caller's profile. The teacher role comes only from the server allowlist."""
    existing = db.get_profile(user.id)
    if existing is not None:
        return _profile_out(existing)
    allowlist = {e.lower() for e in settings.teacher_emails}
    role = Role.TEACHER if user.email and user.email in allowlist else Role.STUDENT
    if role is Role.STUDENT and not body.roll_number:
        raise HTTPException(422, detail="roll_number_required")
    profile = Profile(user.id, role, body.full_name.strip(), body.roll_number, user.email)
    return _profile_out(db.create_profile(profile))


@router.get("/me", response_model=ProfileOut)
def me(profile: Annotated[Profile, Depends(current_profile)]) -> ProfileOut:
    return _profile_out(profile)


@router.post("/classrooms", response_model=ClassroomOut, status_code=status.HTTP_201_CREATED)
def create_classroom(
    body: ClassroomIn, teacher: Annotated[Profile, Depends(require_teacher)], db: Db
) -> ClassroomOut:
    return _classroom_out(db.create_classroom(teacher.id, body.name.strip()))


@router.get("/classrooms", response_model=list[ClassroomOut])
def list_classrooms(
    profile: Annotated[Profile, Depends(current_profile)], db: Db
) -> list[ClassroomOut]:
    if profile.role is Role.TEACHER:
        rooms = db.list_classrooms_for_teacher(profile.id)
    else:
        rooms = db.list_classrooms_for_student(profile.id)
    return [_classroom_out(c) for c in rooms]


@router.post("/classrooms/join", response_model=ClassroomOut)
def join_classroom(
    body: JoinIn, student: Annotated[Profile, Depends(require_student)], db: Db
) -> ClassroomOut:
    classroom = db.classroom_by_join_code(body.join_code.strip())
    if classroom is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="unknown_join_code")
    db.enroll(classroom.id, student.id)  # joining twice is harmless
    return _classroom_out(classroom)


@router.put("/devices/me", response_model=DeviceOut)
def bind_device(
    body: DeviceIn, student: Annotated[Profile, Depends(require_student)], db: Db
) -> DeviceOut:
    """Bind this student's signing key. A new key revokes the previous one."""
    if not crypto.is_valid_public_key(body.public_key):
        raise HTTPException(422, detail="invalid_public_key")
    device = db.bind_device(student.id, body.public_key, body.label)
    return DeviceOut(id=device.id, label=device.label)
