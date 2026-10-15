#!/usr/bin/env python3
"""Mint a local development JWT and (optionally) the matching auth.users row.

For the docker compose stack only. Real users sign in through Supabase Auth.

    python backend/scripts/dev_token.py teacher@example.edu
    # prints: user id, then a bearer token. Insert the user first:
    psql postgresql://postgres:postgres@localhost:5432/classlink \
      -c "insert into auth.users (id, email) values ('<id>', 'teacher@example.edu')"
"""

from __future__ import annotations

import sys
import time
import uuid

import jwt

SECRET = "local-dev-jwt-secret-change-me-0123456789"


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: dev_token.py <email> [user-uuid]")
    email = sys.argv[1]
    user_id = sys.argv[2] if len(sys.argv) > 2 else str(uuid.uuid4())
    expires = int(time.time()) + 86400
    claims = {"sub": user_id, "email": email, "aud": "authenticated", "exp": expires}
    print(f"user id: {user_id}")
    print(jwt.encode(claims, SECRET, algorithm="HS256"))


if __name__ == "__main__":
    main()
