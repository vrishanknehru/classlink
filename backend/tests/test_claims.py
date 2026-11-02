from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app import claims, tokens
from app.domain import Challenge, Reason, Session

NOW = datetime(2026, 10, 15, 12, 0, 0, tzinfo=UTC)
SECRET = b"k" * 32


def make_session(*, threshold: int = -75, min_samples: int = 3, ended: bool = False) -> Session:
    return Session(uuid4(), uuid4(), "a1b2c3d4", threshold, 4, min_samples, NOW,
                   NOW if ended else None)  # fmt: skip


def test_policy_accepts_at_exact_threshold_and_sample_floor() -> None:
    s = make_session()
    assert claims.check_policy(s, sample_count=3, median_rssi=-75) is None


def test_policy_rejects_weak_signal_and_few_samples() -> None:
    s = make_session()
    assert claims.check_policy(s, sample_count=5, median_rssi=-76) is Reason.RSSI_BELOW_THRESHOLD
    assert claims.check_policy(s, sample_count=2, median_rssi=-50) is Reason.TOO_FEW_SAMPLES


def test_freshness_window() -> None:
    assert claims.check_freshness(observed_at=NOW, now=NOW + timedelta(seconds=60),
                                  max_age_seconds=60) is None  # fmt: skip
    assert claims.check_freshness(observed_at=NOW, now=NOW + timedelta(seconds=61),
                                  max_age_seconds=60) is Reason.CLAIM_STALE  # fmt: skip
    assert claims.check_freshness(observed_at=NOW + timedelta(seconds=90), now=NOW,
                                  max_age_seconds=60) is Reason.CLAIM_STALE  # fmt: skip


def test_challenge_expiry_and_token_binding() -> None:
    c = Challenge(uuid4(), uuid4(), uuid4(), "ab12", NOW, NOW + timedelta(seconds=120), None)
    assert claims.check_challenge(c, token_hex="AB12", now=NOW) is None
    assert claims.check_challenge(c, token_hex="ffff", now=NOW) is Reason.TOKEN_MISMATCH
    assert claims.check_challenge(c, token_hex="ab12",
                                  now=NOW + timedelta(seconds=120)) is Reason.CHALLENGE_EXPIRED  # fmt: skip


def test_token_check_orders_failures() -> None:
    s = make_session()
    epoch = tokens.epoch_for(NOW.timestamp(), 15)
    good = tokens.parse_token(tokens.make_token(SECRET, s.id, s.alias, epoch))
    old = tokens.parse_token(tokens.make_token(SECRET, s.id, s.alias, epoch - 5))
    forged = tokens.parse_token(tokens.make_token(b"z" * 32, s.id, s.alias, epoch))
    assert good and old and forged
    args = dict(secret=SECRET, now=NOW, period_seconds=15, grace_epochs=1)
    assert claims.check_token(session=s, parsed=good, **args) is None  # type: ignore[arg-type]
    assert claims.check_token(session=s, parsed=old, **args) is Reason.TOKEN_EXPIRED  # type: ignore[arg-type]
    assert claims.check_token(session=s, parsed=forged, **args) is Reason.INVALID_TOKEN  # type: ignore[arg-type]
    ended = make_session(ended=True)
    assert claims.check_token(session=ended, parsed=good, **args) is Reason.SESSION_NOT_ACTIVE  # type: ignore[arg-type]


def test_decode_token_hex_rejects_garbage() -> None:
    assert claims.decode_token_hex("zz") is None
    assert claims.decode_token_hex("0102") is None
