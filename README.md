# ClassLink

**UCS503P — Software Engineering Project, Thapar Institute of Engineering
and Technology**

ClassLink is a BLE-based classroom attendance system. A teacher's phone
serves a short-lived session token over Bluetooth Low Energy; enrolled
students' phones find it while physically nearby, measure signal strength,
and send a claim signed with a per phone key to a server that makes the
final decision.

The repository contains a tested **backend** (`backend/`), the **Flutter app**
for Android and iOS (`code/`), and the project documents. The SRS
(`docs/srs/`) marks every requirement as Done, POC, or Planned.

## Team

| Roll No. | Name |
|---|---|
| 1024160111 | Vemula Manvi Smaran |
| 1024160109 | Vrishank Nehru |
| 1024160102 | Mahi Singh |
| 1024160123 | Khagendra Saini |

## Repository layout

```
classlink/
├── backend/                       FastAPI + Supabase Postgres backend
├── code/                          Flutter application source
├── docs/                          MkDocs documentation site (incl. docs/srs)
├── journals/                      Weekly progress journals, one per member
├── project-proposal/              Project proposal (LaTeX + PDF)
├── project-srs/                   SRS (LaTeX + PDF, generated from docs/srs)
├── project-report-prototype-stage/  Prototype-stage report (TODO)
├── project-report-final/          Final report (TODO)
└── assets/                        Docs site assets (logo, theme, icons)
```

## Running the app

```bash
cd code
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://your-api.example.com \
  --dart-define=SUPABASE_URL=https://abcd.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ...
```

Leave out the two Supabase values to get a developer sign in that accepts a
token from `backend/scripts/dev_token.py`, for the local `docker compose`
stack. Without `API_BASE_URL` the app uses `http://10.0.2.2:8000`, which is
the host machine as seen from the Android emulator.

How a check in works on the phones:

1. The teacher starts a session. The teacher phone fetches the current token
   from the server every few seconds and serves it from a readable Bluetooth
   characteristic. The token is 17 bytes, too big for a normal advertisement
   next to a 128 bit service UUID, and iOS will not advertise manufacturer
   data, so a quick read works the same on Android and iOS.
2. The student phone finds the strongest teacher phone, reads the token, and
   sends it to the server, which returns a one time nonce and the signal rules.
3. The student phone measures signal strength for the session's window, signs
   the claim with its device key (ECDSA P-256, stored in the Keychain or
   Keystore backed storage) and sends it. The server checks everything again.

Real check ins need two physical phones with Bluetooth LE. Peripheral mode is
unreliable on emulators.

## Backend

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
cp .env.example .env            # then fill in real values
uvicorn app.main:app_from_env --factory --reload
```

Apply `backend/migrations/0001_init.sql` to the Supabase project first. API
reference is served at `/docs`.

## Testing

```bash
# Flutter app
cd code && flutter analyze && flutter test

# Backend (uses a throwaway local Postgres if installed, else set
# CLASSLINK_TEST_DATABASE_URL to a scratch database)
cd backend && ruff check . && mypy app && pytest
```

## Docs site

The documentation site (MkDocs) is built from `docs/` and deployed via
GitHub Actions on push to `main`. To build it locally:

```bash
make docs      # or: make docserve
```

See [`mkdocs.yml`](mkdocs.yml) for configuration.
