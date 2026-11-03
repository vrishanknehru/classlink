# Week 5 : Checking the Token the Student Phone Reads

# Testing the Token Format

## Error:

Once the token moved to a Bluetooth read, a student phone
could connect to the wrong device, or read before the
teacher phone had a token, and get bytes that are not a
token. Sending those to the server wastes a request and
shows the student a confusing error.

## Relevant Context

A real token always has the same shape:

``` text
version (1) | session alias (4) | epoch (4) | HMAC tag (8)
```

17 bytes, and the first byte is the version, `1`.

## Key Observation

The phone cannot tell whether a token is genuine, only the
server can. But it can reject anything with the wrong
shape before asking the server.

## Solution

A shape check on the phone, plus tests that pin it:

``` dart
bool looksLikeToken(List<int> bytes) =>
    bytes.length == tokenLength && bytes.first == tokenVersion;
```

``` dart
test('recognises the token shape only', () {
  expect(looksLikeToken(token), isTrue);
  expect(looksLikeToken(token.sublist(1)), isFalse);       // too short
  expect(looksLikeToken([2, ...token.sublist(1)]), isFalse); // wrong version
});

test('room code is the session alias in capitals', () {
  expect(roomCodeOf(token), '01020304');
});
```

The room code test matters too: both phones show those 8
characters, so a student can compare with the teacher's
screen.

**Because**

Cheap checks on the phone catch the common mistakes early
with a clear message, and the server still makes the real
decision.
