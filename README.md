# ClassLink

**UCS503P — Software Engineering Project, Thapar Institute of Engineering
and Technology**

ClassLink is a BLE-based classroom attendance system. A teacher's phone
advertises a short-lived Bluetooth Low Energy token for an active session;
enrolled students' phones scan for that token while physically nearby,
collect proximity evidence, authenticate locally, and submit a signed
attendance claim to a server-authoritative backend.

The repository contains a tested **backend** (`backend/`), a runnable
offline **proof of concept** app (`code/`), and the project documents. Mobile
integration with the backend is in progress. The SRS (`docs/srs/`) marks every
requirement as Done, POC, or Planned.

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
flutter run
```

Requires two physical Android devices with Bluetooth LE support — BLE
peripheral/GATT-server mode is unreliable on most emulators.

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
