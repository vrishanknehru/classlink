import base64
from datetime import UTC, datetime
from uuid import uuid4

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app import crypto
from tests.conftest import DeviceKey


def test_valid_signature_verifies() -> None:
    key = DeviceKey()
    sig = key.sign(b"hello")
    assert crypto.verify_signature(key.public_b64, b"hello", sig)


def test_altered_message_or_other_key_fails() -> None:
    key, other = DeviceKey(), DeviceKey()
    sig = key.sign(b"hello")
    assert not crypto.verify_signature(key.public_b64, b"hellp", sig)
    assert not crypto.verify_signature(other.public_b64, b"hello", sig)


def test_garbage_inputs_fail_closed() -> None:
    key = DeviceKey()
    assert not crypto.verify_signature(key.public_b64, b"x", "not base64!!")
    assert not crypto.verify_signature("not a key", b"x", key.sign(b"x"))
    assert not crypto.is_valid_public_key("")


def test_only_p256_keys_are_accepted() -> None:
    p384 = ec.generate_private_key(ec.SECP384R1()).public_key()
    der = p384.public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    assert not crypto.is_valid_public_key(base64.b64encode(der).decode())
    assert crypto.is_valid_public_key(DeviceKey().public_b64)


def test_canonical_claim_is_stable_and_binds_every_field() -> None:
    kwargs = dict(
        session_id=uuid4(), nonce=uuid4(), token_hex="AB", median_rssi=-60, sample_count=5,
        observed_at=datetime(2026, 10, 15, 12, 0, tzinfo=UTC),
    )  # fmt: skip
    base = crypto.canonical_claim(**kwargs)  # type: ignore[arg-type]
    assert base == crypto.canonical_claim(**kwargs)  # type: ignore[arg-type]
    assert crypto.canonical_claim(**{**kwargs, "median_rssi": -61}) != base  # type: ignore[arg-type]
    assert crypto.canonical_claim(**{**kwargs, "sample_count": 6}) != base  # type: ignore[arg-type]
    assert b"classlink-claim-v1" in base


def test_observation_time_is_signed_as_whole_unix_seconds() -> None:
    from datetime import timedelta

    base = datetime(2026, 10, 15, 12, 0, 0, tzinfo=UTC)
    kwargs = dict(
        session_id=uuid4(), nonce=uuid4(), token_hex="ab", median_rssi=-60, sample_count=5
    )
    a = crypto.canonical_claim(observed_at=base, **kwargs)  # type: ignore[arg-type]
    b = crypto.canonical_claim(observed_at=base + timedelta(milliseconds=900), **kwargs)  # type: ignore[arg-type]
    c = crypto.canonical_claim(observed_at=base + timedelta(seconds=1), **kwargs)  # type: ignore[arg-type]
    assert a == b  # sub second noise never breaks a signature
    assert a != c
    assert a.decode().split("\n")[-1] == str(int(base.timestamp())) == "1792065600"


def test_golden_vector_shared_with_the_flutter_client() -> None:
    """The same vector is asserted in code/test/claim_protocol_test.dart."""
    from uuid import UUID

    msg = crypto.canonical_claim(
        session_id=UUID("11111111-2222-3333-4444-555555555555"),
        nonce=UUID("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"),
        token_hex="0101020304000000f1a1b2c3d4e5f60708",
        median_rssi=-62,
        sample_count=5,
        observed_at=datetime(2026, 10, 15, 12, 0, 0, tzinfo=UTC),
    )
    assert msg == GOLDEN_CLAIM


GOLDEN_CLAIM = (
    b"classlink-claim-v1\n11111111-2222-3333-4444-555555555555\n"
    b"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n0101020304000000f1a1b2c3d4e5f60708\n"
    b"-62\n5\n1792065600"
)
