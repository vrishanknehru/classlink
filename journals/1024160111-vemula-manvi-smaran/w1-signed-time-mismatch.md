# Week 1 : Signatures Broke on the Observation Time

# Canonical Claim Format

## Error:

A claim signed on the phone would fail the server check
with `bad_signature`, even with the right key and data.

## Relevant Context

Both sides build the same text and the phone signs it.
The server built the last line from the observation time
like this:

``` python
parts = [
    CLAIM_DOMAIN, str(session_id), str(nonce),
    token_hex.lower(), str(median_rssi), str(sample_count),
    observed_at.isoformat(),
]
```

## Key Observation

`isoformat()` is not the same string in every language.
Python writes `2026-10-15T12:00:00+00:00`, while Dart
writes `2026-10-15T12:00:00.000Z`, and fractions of a
second appear or vanish. One different character means a
different signature.

## Solution

Sign whole seconds since the Unix epoch instead:

``` python
# Whole seconds since the Unix epoch: identical in every
# language, unlike ISO 8601.
str(int(observed_at.timestamp())),
```

and pin it with a shared golden vector that both the
Python and the Dart tests check:

``` text
classlink-claim-v1
11111111-2222-3333-4444-555555555555
aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
0101020304000000f1a1b2c3d4e5f60708
-62
5
1792065600
```

**Because**

A signature covers exact bytes, not meaning. Two strings
that mean the same moment still fail if any byte differs,
so the format must have only one way to write it.
