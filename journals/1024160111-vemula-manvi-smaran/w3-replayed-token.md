# Week 3 : A Photographed Code Should Not Work Later

# Rotating Session Tokens

## Error:

In the prototype the session code stayed the same for the
whole class. A student could send it to a friend outside
the room, and the friend could check in.

## Relevant Context

The server now issues the token the teacher phone shares:

``` text
version (1) | session alias (4) | epoch (4) | HMAC tag (8)
```

17 bytes in total. The epoch is the current 15 second
period.

## Key Observation

Making the code change is not enough on its own, because
anyone could invent a code. The server has to be able to
tell that it made the code, and when.

## Solution

The tag is an HMAC over the version, alias, epoch and
session id, keyed with a secret only the server holds:

``` python
def _tag(secret, session_id, alias, epoch):
    message = struct.pack(">B4sI", TOKEN_VERSION, alias, epoch) + session_id.bytes
    return hmac.new(secret, message, hashlib.sha256).digest()[:8]
```

and a token is only fresh within a small window:

``` python
def epoch_is_fresh(token_epoch, now_epoch, grace_epochs):
    return now_epoch - grace_epochs <= token_epoch <= now_epoch + 1
```

**Because**

Without the secret nobody can make a valid tag, and with
one epoch of grace a code stops working about 30 seconds
after it was on air. A forwarded code is stale before a
friend can use it.
