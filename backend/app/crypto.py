"""Device key verification for signed attendance claims.

Student phones hold an ECDSA P-256 key in the Android Keystore. The public key
is exported as base64 SubjectPublicKeyInfo DER and signatures are base64 DER
ECDSA over SHA-256, which is what `SHA256withECDSA` produces on Android.
"""

from __future__ import annotations

import base64
import binascii
from datetime import datetime
from uuid import UUID

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import load_der_public_key

CLAIM_DOMAIN = "classlink-claim-v1"


def canonical_claim(
    *,
    session_id: UUID,
    nonce: UUID,
    token_hex: str,
    median_rssi: int,
    sample_count: int,
    observed_at: datetime,
) -> bytes:
    """The exact byte string a device signs. Clients must build it identically."""
    parts = [
        CLAIM_DOMAIN,
        str(session_id),
        str(nonce),
        token_hex.lower(),
        str(median_rssi),
        str(sample_count),
        observed_at.isoformat(),
    ]
    return "\n".join(parts).encode("utf-8")


def _load_p256(public_key_b64: str) -> ec.EllipticCurvePublicKey | None:
    try:
        key = load_der_public_key(base64.b64decode(public_key_b64, validate=True))
    except (binascii.Error, ValueError):
        return None
    if isinstance(key, ec.EllipticCurvePublicKey) and isinstance(key.curve, ec.SECP256R1):
        return key
    return None


def is_valid_public_key(public_key_b64: str) -> bool:
    return _load_p256(public_key_b64) is not None


def verify_signature(public_key_b64: str, message: bytes, signature_b64: str) -> bool:
    key = _load_p256(public_key_b64)
    if key is None:
        return False
    try:
        signature = base64.b64decode(signature_b64, validate=True)
        key.verify(signature, message, ec.ECDSA(hashes.SHA256()))
    except (binascii.Error, ValueError, InvalidSignature):
        return False
    return True
