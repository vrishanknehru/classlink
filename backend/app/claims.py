"""Pure policy checks for the challenge and claim pipeline.

These functions take already loaded data and return a rejection reason or None,
so every rule can be unit tested without a database.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from app import tokens
from app.domain import Challenge, Reason, Session


def decode_token_hex(token_hex: str) -> tokens.ParsedToken | None:
    try:
        raw = bytes.fromhex(token_hex)
    except ValueError:
        return None
    return tokens.parse_token(raw)


def check_token(
    *,
    secret: bytes,
    session: Session,
    parsed: tokens.ParsedToken,
    now: datetime,
    period_seconds: int,
    grace_epochs: int,
) -> Reason | None:
    if not session.active:
        return Reason.SESSION_NOT_ACTIVE
    if not tokens.tag_is_valid(secret, session.id, parsed):
        return Reason.INVALID_TOKEN
    now_epoch = tokens.epoch_for(now.timestamp(), period_seconds)
    if not tokens.epoch_is_fresh(parsed.epoch, now_epoch, grace_epochs):
        return Reason.TOKEN_EXPIRED
    return None


def check_challenge(challenge: Challenge, *, token_hex: str, now: datetime) -> Reason | None:
    """Checks that apply to an unused challenge."""
    if now >= challenge.expires_at:
        return Reason.CHALLENGE_EXPIRED
    if challenge.token_hex.lower() != token_hex.lower():
        return Reason.TOKEN_MISMATCH
    return None


def check_freshness(*, observed_at: datetime, now: datetime, max_age_seconds: int) -> Reason | None:
    if abs(now - observed_at) > timedelta(seconds=max_age_seconds):
        return Reason.CLAIM_STALE
    return None


def check_policy(session: Session, *, sample_count: int, median_rssi: int) -> Reason | None:
    """The per session proximity policy. RSSI is evidence, not proof of distance."""
    if sample_count < session.min_samples:
        return Reason.TOO_FEW_SAMPLES
    if median_rssi < session.rssi_threshold_dbm:
        return Reason.RSSI_BELOW_THRESHOLD
    return None
