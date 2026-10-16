from __future__ import annotations

import csv
import io
from collections.abc import Callable

import psycopg

from tests.conftest import DeviceKey, User, World, make_jwt


# --- accounts ---------------------------------------------------------------
def test_teacher_role_only_comes_from_the_allowlist(
    client,
    new_user: Callable[..., User],  # type: ignore[no-untyped-def]
) -> None:
    teacher = new_user("teacher@example.edu", "Dr. T")
    pretender = new_user("pretender@example.edu", "Pretender", "1024160009")
    assert client.get("/v1/me", headers=teacher.headers).json()["role"] == "teacher"
    assert client.get("/v1/me", headers=pretender.headers).json()["role"] == "student"


def test_student_profile_requires_a_roll_number(client, new_user) -> None:  # type: ignore[no-untyped-def]
    u = new_user("noroll@example.edu", create_profile=False)
    resp = client.post("/v1/profile", json={"full_name": "No Roll"}, headers=u.headers)
    assert resp.status_code == 422


def test_profile_creation_is_idempotent(client, new_user) -> None:  # type: ignore[no-untyped-def]
    u = new_user("again@example.edu", "First Name", "1")
    again = client.post(
        "/v1/profile", json={"full_name": "Other", "roll_number": "2"}, headers=u.headers
    )
    assert again.status_code == 200
    assert again.json()["full_name"] == "First Name"


def test_requests_without_valid_credentials_are_rejected(client, world: World) -> None:  # type: ignore[no-untyped-def]
    assert client.get("/v1/me").status_code == 401
    assert client.get("/v1/me", headers={"Authorization": "Bearer junk"}).status_code == 401
    wrong_secret = make_jwt(world.student.id, "x@y.z", secret="a-different-secret-0123456789abcdef")
    assert (
        client.get("/v1/me", headers={"Authorization": f"Bearer {wrong_secret}"}).status_code == 401
    )
    wrong_aud = make_jwt(world.student.id, "x@y.z", aud="somebody-else")
    assert client.get("/v1/me", headers={"Authorization": f"Bearer {wrong_aud}"}).status_code == 401


def test_a_user_without_a_profile_is_asked_to_create_one(client, new_user) -> None:  # type: ignore[no-untyped-def]
    u = new_user("fresh@example.edu", create_profile=False)
    resp = client.get("/v1/me", headers=u.headers)
    assert resp.status_code == 403
    assert resp.json()["detail"] == "profile_required"


def test_invalid_device_key_is_rejected(world: World) -> None:
    resp = world.client.put(
        "/v1/devices/me", json={"public_key": "AAAA"}, headers=world.student.headers
    )
    assert resp.status_code == 422


def test_unknown_join_code_is_404(world: World) -> None:
    resp = world.client.post(
        "/v1/classrooms/join", json={"join_code": "ZZZZZZ"}, headers=world.student.headers
    )
    assert resp.status_code == 404


def test_students_cannot_use_teacher_endpoints(world: World) -> None:
    c, h = world.client, world.student.headers
    assert c.post("/v1/classrooms", json={"name": "x"}, headers=h).status_code == 403
    assert (
        c.post("/v1/sessions", json={"classroom_id": world.classroom["id"]}, headers=h).status_code
        == 403
    )
    assert c.get(f"/v1/sessions/{world.session['id']}/roster", headers=h).status_code == 403


def test_teachers_cannot_use_student_endpoints(world: World) -> None:
    t = world.teacher.headers
    assert (
        world.client.put(
            "/v1/devices/me", json={"public_key": DeviceKey().public_b64}, headers=t
        ).status_code
        == 403
    )
    assert (
        world.client.post(
            "/v1/attendance/challenge", json={"token_hex": "00"}, headers=t
        ).status_code
        == 403
    )


# --- sessions ---------------------------------------------------------------
def test_only_one_active_session_per_classroom(world: World) -> None:
    resp = world.client.post(
        "/v1/sessions", json={"classroom_id": world.classroom["id"]}, headers=world.teacher.headers
    )
    assert resp.status_code == 409
    assert resp.json()["detail"] == "active_session_exists"
    world.client.post(f"/v1/sessions/{world.session['id']}/end", headers=world.teacher.headers)
    again = world.client.post(
        "/v1/sessions", json={"classroom_id": world.classroom["id"]}, headers=world.teacher.headers
    )
    assert again.status_code == 201


def test_ending_twice_conflicts(world: World) -> None:
    url = f"/v1/sessions/{world.session['id']}/end"
    assert world.client.post(url, headers=world.teacher.headers).status_code == 200
    assert world.client.post(url, headers=world.teacher.headers).status_code == 409


def test_another_teacher_cannot_see_or_control_the_session(world: World, new_user) -> None:  # type: ignore[no-untyped-def]
    other = new_user("teacher@example.edu", "Same Allowlisted Email, different account")
    sid = world.session["id"]
    for path in (f"/v1/sessions/{sid}/roster", f"/v1/sessions/{sid}/token",
                 f"/v1/sessions/{sid}/export.csv"):  # fmt: skip
        assert world.client.get(path, headers=other.headers).status_code == 404
    assert world.client.post(f"/v1/sessions/{sid}/end", headers=other.headers).status_code == 404


def test_token_endpoint_rotates_with_time(world: World) -> None:
    first = world.token()
    world.clock.advance(15)
    assert world.token() != first
    assert len(bytes.fromhex(first)) == 17


def test_token_unavailable_after_the_session_ends(world: World) -> None:
    world.client.post(f"/v1/sessions/{world.session['id']}/end", headers=world.teacher.headers)
    resp = world.client.get(
        f"/v1/sessions/{world.session['id']}/token", headers=world.teacher.headers
    )
    assert resp.status_code == 409


# --- corrections and export ---------------------------------------------------
def test_manual_correction_needs_a_reason_and_is_audited(world: World, migrated_url: str) -> None:
    url = f"/v1/sessions/{world.session['id']}/corrections"
    body = {"student_id": str(world.student.id), "status": "present"}
    short = world.client.post(url, json={**body, "reason": "no"}, headers=world.teacher.headers)
    assert short.status_code == 422
    ok = world.client.post(
        url,
        json={**body, "reason": "Phone battery died, teacher saw her"},
        headers=world.teacher.headers,
    )
    assert ok.status_code == 200
    assert ok.json()["source"] == "manual_correction"
    with psycopg.connect(migrated_url) as conn:
        row = conn.execute(
            "select details->>'reason', details->>'from', details->>'to' from audit_events "
            "where action = 'manual_correction'"
        ).fetchone()
    assert row == ("Phone battery died, teacher saw her", None, "present")


def test_correction_can_overturn_a_ble_claim(world: World) -> None:
    world.check_in()
    url = f"/v1/sessions/{world.session['id']}/corrections"
    resp = world.client.post(
        url,
        json={
            "student_id": str(world.student.id),
            "status": "absent",
            "reason": "Left after check in",
        },
        headers=world.teacher.headers,
    )
    assert resp.json()["status"] == "absent"
    roster = world.client.get(
        f"/v1/sessions/{world.session['id']}/roster", headers=world.teacher.headers
    ).json()
    assert roster[0]["status"] == "absent" and roster[0]["source"] == "manual_correction"


def test_cannot_correct_a_student_outside_the_classroom(world: World, new_user) -> None:  # type: ignore[no-untyped-def]
    outsider = new_user("out@example.edu", "Out", "7")
    resp = world.client.post(
        f"/v1/sessions/{world.session['id']}/corrections",
        json={"student_id": str(outsider.id), "status": "present", "reason": "should not work"},
        headers=world.teacher.headers,
    )
    assert resp.status_code == 404


def test_csv_export_lists_every_enrolled_student(world: World, new_user) -> None:  # type: ignore[no-untyped-def]
    bob = new_user("bob@example.edu", "Bob Absent", "1024160002")
    world.client.post(
        "/v1/classrooms/join", json={"join_code": world.classroom["join_code"]}, headers=bob.headers
    )
    world.check_in(rssi=-58)
    resp = world.client.get(
        f"/v1/sessions/{world.session['id']}/export.csv", headers=world.teacher.headers
    )
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/csv")
    rows = list(csv.DictReader(io.StringIO(resp.text)))
    by_name = {r["Name"]: r for r in rows}
    assert by_name["Ada Lovelace"]["Status"] == "present"
    assert by_name["Ada Lovelace"]["Median RSSI (dBm)"] == "-58"
    assert by_name["Bob Absent"]["Status"] == "absent"
    assert by_name["Bob Absent"]["Source"] == "no_record"


def test_csv_export_neutralises_formula_injection(world: World, new_user) -> None:  # type: ignore[no-untyped-def]
    evil = new_user("evil@example.edu", '=HYPERLINK("http://evil")', "@SUM(1)")
    world.client.post(
        "/v1/classrooms/join",
        json={"join_code": world.classroom["join_code"]},
        headers=evil.headers,
    )
    resp = world.client.get(
        f"/v1/sessions/{world.session['id']}/export.csv", headers=world.teacher.headers
    )
    rows = list(csv.DictReader(io.StringIO(resp.text)))
    cells = [r["Name"] for r in rows] + [r["Roll Number"] for r in rows]
    assert not any(c.startswith(("=", "@", "+")) for c in cells)
    assert "'=HYPERLINK" in resp.text


# --- additions for classroom listing, join codes and export auditing ----------
def test_join_code_format_and_listing(world: World) -> None:
    import re

    assert re.fullmatch(r"[A-HJ-NP-Z2-9]{6}", world.classroom["join_code"])
    mine_t = world.client.get("/v1/classrooms", headers=world.teacher.headers).json()
    mine_s = world.client.get("/v1/classrooms", headers=world.student.headers).json()
    assert [c["id"] for c in mine_t] == [world.classroom["id"]]
    assert [c["id"] for c in mine_s] == [world.classroom["id"]]


def test_join_code_is_case_insensitive_and_joining_twice_is_harmless(world: World) -> None:
    code = world.classroom["join_code"].lower()
    for _ in range(2):
        resp = world.client.post(
            "/v1/classrooms/join", json={"join_code": code}, headers=world.student.headers
        )
        assert resp.status_code == 200
    mine = world.client.get("/v1/classrooms", headers=world.student.headers).json()
    assert len(mine) == 1


def test_export_is_audited(world: World, migrated_url: str) -> None:
    world.client.get(
        f"/v1/sessions/{world.session['id']}/export.csv", headers=world.teacher.headers
    )
    with psycopg.connect(migrated_url) as conn:
        row = conn.execute(
            "select count(*) from audit_events where action = 'export_downloaded'"
        ).fetchone()
    assert row == (1,)
