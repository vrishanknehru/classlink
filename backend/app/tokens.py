"""Rotating BLE session tokens.

A token is what the teacher's phone advertises. It is 17 bytes, within the
20 byte payload budget, and carries no student or teacher identifier:

    version (1) | session alias (4) | epoch (4, big endian) | HMAC tag (8)

The tag is HMAC-SHA256 over the version, alias, epoch and session id, keyed
with a server side secret. A photographed or relayed token stops working
once its epoch falls outside the grace window.
"""

from __future__ import annotations

import hashlib
import hmac
import struct
from dataclasses import dataclass
from uuid import UUID

TOKEN_VERSION = 1
TOKEN_LENGTH = 1 + 4 + 4 + 8
_TAG_LENGTH = 8


@dataclass(frozen=True, slots=True)
class ParsedToken:
    alias: str
    epoch: int
    tag: bytes


def epoch_for(timestamp: float, period_seconds: int) -> int:
    return int(timestamp // period_seconds)


def _tag(secret: bytes, session_id: UUID, alias: bytes, epoch: int) -> bytes:
    message = struct.pack(">B4sI", TOKEN_VERSION, alias, epoch) + session_id.bytes
    return hmac.new(secret, message, hashlib.sha256).digest()[:_TAG_LENGTH]


def make_token(secret: bytes, session_id: UUID, alias_hex: str, epoch: int) -> bytes:
    alias = bytes.fromhex(alias_hex)
    header = struct.pack(">B4sI", TOKEN_VERSION, alias, epoch)
    return header + _tag(secret, session_id, alias, epoch)


def parse_token(raw: bytes) -> ParsedToken | None:
    """Split a token into its parts, or return None if it is malformed."""
    if len(raw) != TOKEN_LENGTH:
        return None
    version, alias, epoch = struct.unpack(">B4sI", raw[:9])
    if version != TOKEN_VERSION:
        return None
    return ParsedToken(alias=alias.hex(), epoch=epoch, tag=raw[9:])


def tag_is_valid(secret: bytes, session_id: UUID, token: ParsedToken) -> bool:
    expected = _tag(secret, session_id, bytes.fromhex(token.alias), token.epoch)
    return hmac.compare_digest(expected, token.tag)


def epoch_is_fresh(token_epoch: int, now_epoch: int, grace_epochs: int) -> bool:
    """Accept the current epoch, up to `grace_epochs` old, and one ahead for clock skew."""
    return now_epoch - grace_epochs <= token_epoch <= now_epoch + 1
