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
