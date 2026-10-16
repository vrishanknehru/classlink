from uuid import uuid4

from app import tokens

SECRET = b"s" * 32
SESSION = uuid4()
ALIAS = "a1b2c3d4"


def test_token_fits_ble_budget() -> None:
    raw = tokens.make_token(SECRET, SESSION, ALIAS, 1000)
    assert len(raw) == tokens.TOKEN_LENGTH == 17
    assert len(raw) <= 20


def test_round_trip_validates() -> None:
    raw = tokens.make_token(SECRET, SESSION, ALIAS, 1234)
    parsed = tokens.parse_token(raw)
    assert parsed is not None
    assert (parsed.alias, parsed.epoch) == (ALIAS, 1234)
    assert tokens.tag_is_valid(SECRET, SESSION, parsed)


def test_wrong_secret_or_session_fails() -> None:
    parsed = tokens.parse_token(tokens.make_token(SECRET, SESSION, ALIAS, 5))
    assert parsed is not None
    assert not tokens.tag_is_valid(b"x" * 32, SESSION, parsed)
    assert not tokens.tag_is_valid(SECRET, uuid4(), parsed)


def test_tampered_epoch_fails() -> None:
    raw = bytearray(tokens.make_token(SECRET, SESSION, ALIAS, 5))
    raw[8] ^= 0x01  # flip a bit in the epoch
    parsed = tokens.parse_token(bytes(raw))
    assert parsed is not None
    assert not tokens.tag_is_valid(SECRET, SESSION, parsed)


def test_tokens_rotate_each_epoch() -> None:
    assert tokens.make_token(SECRET, SESSION, ALIAS, 1) != tokens.make_token(
        SECRET, SESSION, ALIAS, 2
    )


def test_malformed_tokens_are_rejected() -> None:
    assert tokens.parse_token(b"") is None
    assert tokens.parse_token(b"\x01" * 16) is None
    good = tokens.make_token(SECRET, SESSION, ALIAS, 5)
    assert tokens.parse_token(b"\x02" + good[1:]) is None  # unknown version


def test_epoch_freshness_window() -> None:
    assert tokens.epoch_is_fresh(100, 100, 1)
    assert tokens.epoch_is_fresh(99, 100, 1)
    assert not tokens.epoch_is_fresh(98, 100, 1)
    assert tokens.epoch_is_fresh(101, 100, 1)  # one ahead tolerates clock skew
    assert not tokens.epoch_is_fresh(102, 100, 1)


def test_epoch_for() -> None:
    assert tokens.epoch_for(0, 15) == 0
    assert tokens.epoch_for(14.9, 15) == 0
    assert tokens.epoch_for(15, 15) == 1
