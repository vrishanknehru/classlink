"""Row level security isolation, exercised as the `authenticated` database role."""

from __future__ import annotations

import psycopg
import pytest

from tests.conftest import World


def as_user(url: str, user_id: object) -> psycopg.Connection:  # type: ignore[type-arg]
    conn = psycopg.connect(url, autocommit=True)
    conn.execute("set role authenticated")
    conn.execute("select set_config('request.jwt.claim.sub', %s, false)", (str(user_id),))
    return conn


def count(conn: psycopg.Connection, table: str) -> int:  # type: ignore[type-arg]
    row = conn.execute(f"select count(*) from {table}").fetchone()  # noqa: S608
    assert row is not None
    return int(row[0])


@pytest.fixture
def populated(world: World) -> World:
    assert world.check_in().status_code == 200
    return world


def test_student_sees_only_their_own_rows(populated: World, new_user, migrated_url: str) -> None:  # type: ignore[no-untyped-def]
    other = new_user("other@example.edu", "Other Student", "1024160777")
    with as_user(migrated_url, populated.student.id) as me, as_user(migrated_url, other.id) as them:
        assert count(me, "attendance") == 1
        assert count(me, "profiles") == 1
        assert count(me, "devices") == 1
        assert count(me, "classrooms") == 1
        assert count(them, "attendance") == 0
        assert count(them, "devices") == 0
        assert count(them, "classrooms") == 0
        assert count(them, "sessions") == 0


def test_teacher_sees_their_classroom_data_and_the_students_in_it(
    populated: World, migrated_url: str
) -> None:
    with as_user(migrated_url, populated.teacher.id) as t:
        assert count(t, "classrooms") == 1
        assert count(t, "sessions") == 1
        assert count(t, "attendance") == 1
        assert count(t, "enrollments") == 1
        assert count(t, "profiles") == 2  # themselves and the enrolled student
        assert count(t, "devices") == 0  # device keys are private to the student


def test_another_teacher_sees_nothing(populated: World, new_user, migrated_url: str) -> None:  # type: ignore[no-untyped-def]
    other = new_user("teacher@example.edu", "Different Teacher")
    with as_user(migrated_url, other.id) as t:
        for table in ("classrooms", "sessions", "attendance", "enrollments"):
            assert count(t, table) == 0, table
        assert count(t, "profiles") == 1


def test_clients_cannot_write_anything(populated: World, migrated_url: str) -> None:
    with as_user(migrated_url, populated.student.id) as me:
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            me.execute("update attendance set status = 'present'")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            me.execute("delete from attendance")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            me.execute(
                "insert into enrollments (classroom_id, student_id) values (gen_random_uuid(), gen_random_uuid())"
            )


def test_challenges_and_audit_log_are_not_readable_by_clients(
    populated: World, migrated_url: str
) -> None:
    for who in (populated.student.id, populated.teacher.id):
        with as_user(migrated_url, who) as c:
            for table in ("challenges", "audit_events"):
                with pytest.raises(psycopg.errors.InsufficientPrivilege):
                    c.execute(f"select * from {table}")  # noqa: S608


def test_anonymous_clients_see_nothing(populated: World, migrated_url: str) -> None:
    with psycopg.connect(migrated_url, autocommit=True) as conn:
        conn.execute("set role anon")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            conn.execute("select * from attendance")
