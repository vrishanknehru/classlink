"""End to end claim pipeline: challenge, signed claim, and every rejection path."""

from __future__ import annotations

from collections.abc import Callable
from datetime import timedelta

import psycopg

from app.domain import Reason
from tests.conftest import DeviceKey, User, World


def reason(resp) -> str:  # type: ignore[no-untyped-def]
    assert resp.status_code == 409, resp.text
    assert resp.json()["detail"]["status"] == "rejected"
    return str(resp.json()["detail"]["reason"])


def test_happy_path_records_attendance(world: World) -> None:
    resp = world.check_in(rssi=-62)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["status"] == "accepted"
    assert body["duplicate_retry"] is False
    assert body["attendance"]["status"] == "present"
    assert body["attendance"]["source"] == "ble_claim"
    assert body["attendance"]["median_rssi"] == -62

    roster = world.client.get(
        f"/v1/sessions/{world.session['id']}/roster", headers=world.teacher.headers
    ).json()
    assert [(r["full_name"], r["status"]) for r in roster] == [("Ada Lovelace", "present")]


def test_exact_threshold_is_accepted(world: World) -> None:
    assert world.check_in(rssi=-75).status_code == 200


def test_too_far_is_rejected_and_can_retry_with_same_nonce(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    far = world.claim_body(ch, token, rssi=-90)
    assert reason(world.claim(far)) == Reason.RSSI_BELOW_THRESHOLD
    near = world.claim_body(ch, token, rssi=-60)
    assert world.claim(near).status_code == 200  # nonce survives a policy rejection


def test_too_few_samples_rejected(world: World) -> None:
    assert reason(world.check_in(samples=2)) == Reason.TOO_FEW_SAMPLES


def test_forged_signature_rejected(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    body = world.claim_body(ch, token, key=DeviceKey())  # signed by a different key
    assert reason(world.claim(body)) == Reason.BAD_SIGNATURE


def test_tampered_rssi_breaks_the_signature(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    body = world.claim_body(ch, token, rssi=-90)
    body["median_rssi"] = -50  # a student editing the value after signing
    assert reason(world.claim(body)) == Reason.BAD_SIGNATURE


def test_replayed_claim_is_idempotent(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    body = world.claim_body(ch, token)
    first = world.claim(body)
    second = world.claim(body)
    assert first.status_code == second.status_code == 200
    assert second.json()["duplicate_retry"] is True
    assert first.json()["attendance"] == second.json()["attendance"]


def test_second_checkin_with_new_nonce_is_a_duplicate(world: World) -> None:
    assert world.check_in().status_code == 200
    assert reason(world.check_in()) == Reason.DUPLICATE


def test_expired_token_cannot_get_a_challenge(world: World) -> None:
    token = world.token()
    world.clock.advance(45)  # three 15 second periods later
    assert reason(world.challenge(token)) == Reason.TOKEN_EXPIRED


def test_token_within_grace_is_accepted(world: World) -> None:
    token = world.token()
    world.clock.advance(15)
    assert world.challenge(token).status_code == 200


def test_expired_challenge_rejected(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    body = world.claim_body(ch, token)
    world.clock.advance(121)
    assert reason(world.claim(body)) == Reason.CHALLENGE_EXPIRED


def test_stale_observation_rejected(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    old = world.clock.now - timedelta(seconds=300)
    assert reason(world.claim(world.claim_body(ch, token, observed_at=old))) == Reason.CLAIM_STALE


def test_claim_must_use_the_challenge_token(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    world.clock.advance(15)
    other_token = world.token()
    assert other_token != token
    assert reason(world.claim(world.claim_body(ch, other_token))) == Reason.TOKEN_MISMATCH


def test_forged_token_rejected(world: World) -> None:
    token = world.token()
    forged = token[:-2] + ("00" if token[-2:] != "00" else "01")
    assert reason(world.challenge(forged)) == Reason.INVALID_TOKEN


def test_garbage_token_rejected(world: World) -> None:
    assert reason(world.challenge("nothex")) == Reason.INVALID_TOKEN
    assert reason(world.challenge("0102")) == Reason.INVALID_TOKEN


def test_unenrolled_student_rejected(world: World, new_user: Callable[..., User]) -> None:
    outsider = new_user("eve@example.edu", "Eve", "1024169999")
    world.client.put(
        "/v1/devices/me", json={"public_key": DeviceKey().public_b64}, headers=outsider.headers
    )
    assert reason(world.challenge(user=outsider)) == Reason.NOT_ENROLLED


def test_student_without_device_rejected(world: World, new_user: Callable[..., User]) -> None:
    bob = new_user("bob@example.edu", "Bob", "1024160002")
    world.client.post(
        "/v1/classrooms/join",
        json={"join_code": world.classroom["join_code"]},
        headers=bob.headers,
    )
    assert reason(world.challenge(user=bob)) == Reason.NO_DEVICE_BOUND


def test_nobody_can_claim_with_someone_elses_nonce(
    world: World, new_user: Callable[..., User]
) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    thief = new_user("mal@example.edu", "Mal", "1024160003")
    assert reason(world.claim(world.claim_body(ch, token), user=thief)) == Reason.CHALLENGE_UNKNOWN


def test_ended_session_rejects_everything(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    body = world.claim_body(ch, token)
    ended = world.client.post(
        f"/v1/sessions/{world.session['id']}/end", headers=world.teacher.headers
    )
    assert ended.status_code == 200
    assert reason(world.claim(body)) == Reason.SESSION_NOT_ACTIVE
    assert reason(world.challenge(token)) == Reason.SESSION_NOT_ACTIVE


def test_rebinding_a_device_revokes_the_old_key(world: World) -> None:
    token = world.token()
    ch = world.challenge(token).json()
    old_key_body = world.claim_body(ch, token)
    new_key = DeviceKey()
    world.client.put(
        "/v1/devices/me", json={"public_key": new_key.public_b64}, headers=world.student.headers
    )
    assert reason(world.claim(old_key_body)) == Reason.BAD_SIGNATURE
    assert world.claim(world.claim_body(ch, token, key=new_key)).status_code == 200


def test_rejections_and_acceptances_are_audited(world: World, migrated_url: str) -> None:
    world.check_in(samples=1)  # rejected
    world.check_in()  # accepted
    with psycopg.connect(migrated_url) as conn:
        actions = [
            r[0]
            for r in conn.execute(
                "select action || ':' || coalesce(details->>'reason', '') "
                "from audit_events where action in ('claim_rejected', 'claim_accepted') order by id"
            ).fetchall()
        ]
    assert actions == ["claim_rejected:too_few_samples", "claim_accepted:"]


def test_concurrent_claims_never_double_count(world: World) -> None:
    """Two different nonces racing for the same student produce exactly one record."""
    token = world.token()
    a = world.challenge(token).json()
    b = world.challenge(token).json()
    first = world.claim(world.claim_body(a, token))
    second = world.claim(world.claim_body(b, token))
    assert {first.status_code, second.status_code} == {200, 409}
    assert reason(second) == Reason.DUPLICATE
