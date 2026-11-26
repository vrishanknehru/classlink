# Handoff: open issues and next steps

Written on 26 November 2026 by Manvi. This page is for the teammate who picks
up the work next. It lists what is done, what is broken, and what is left.
Every number here comes from a real run on 26 November 2026.

## What was pushed in this batch

| Commit | What it does |
|---|---|
| `a8aab73` | The API checks Supabase tokens with the project JWKS (ES256 and RS256). HS256 stays as a fallback. |
| `9a4dac2` | `render.yaml` uses Render's free plan. The runbook explains the session pooler. |
| `5db60b5` | New route `GET /v1/classrooms/{id}/sessions/active`. The app uses it to resume a running session from any teacher phone. |
| `32146ee` | New Flutter tests for the teacher session controller and the API models. |
| `b990fcc` | The Android package is now `com.classlink.app`. |

## Check results before this push

| Check | Result |
|---|---|
| `ruff check .` | Clean |
| `ruff format --check .` | Clean |
| `python -m mypy app` | Clean |
| `python -m pytest -q` | 98 passed, 1 warning (the old Starlette and httpx notice) |
| `flutter test` | 64 passed |
| `flutter analyze` | Failed with 9 issues at first. Fixed later, see issue 1. |

Flutter version used: 3.50.1, stable channel, Dart 3.14.0.

## Second batch: fixes

| Commit | What it does |
|---|---|
| `3ecd2b9` | Empty `CLASSLINK_` settings count as unset (issue 2). |
| `4df948f` | The teacher phone no longer saves the session id (issue 3). |
| `42a8cf9` | Material widgets come from `package:material_ui` (issue 1). |
| `d26b6c3` | The macOS app uses `com.classlink.app` (issue 4). |

Checks after these fixes: ruff clean, ruff format clean, mypy clean,
`pytest` 99 passed with 1 warning, `flutter analyze` no issues,
`flutter test` 63 passed.

## Open issues

### 1. `flutter analyze` failed on the current stable Flutter (fixed)

- **Status:** fixed. Flutter 3.47 deprecated `package:flutter/material.dart`.
  The app now depends on the official `material_ui` package (publisher
  `flutter.dev`) and the 9 screen files import
  `package:material_ui/material_ui.dart`. `code/pubspec.yaml` now needs Dart
  3.13 and Flutter 3.47 or newer. `flutter analyze`: no issues.
- **Note:** the new Flutter added an `analyzer: exclude:` list to
  `code/analysis_options.yaml`. That change is committed with this fix.

### 2. An empty `CLASSLINK_JWT_SECRET` stopped the API from starting (fixed)

- **Status:** fixed. `backend/app/config.py` now sets `env_ignore_empty=True`,
  so a key set to an empty value counts as unset. The test
  `test_empty_optional_values_count_as_unset` in `backend/tests/test_config.py`
  covers it. "Leave it empty" in `docs/deployment.md` is now safe.

### 3. One new Flutter test checked nothing (fixed)

- **Status:** fixed. `TeacherSessionController` no longer saves the running
  session id, because nothing read it back. Resume asks the server instead.
  The empty test is gone, and the controller no longer takes a `store`.
  `flutter test`: 63 passed.

### 4. macOS used the old app id (fixed, not build tested)

- **Status:** fixed. The macOS bundle id is now `com.classlink.app` and the
  product name is `classlink`, like iOS and Android. The changed files are
  `code/macos/Runner/Configs/AppInfo.xcconfig`, the Xcode project and the
  scheme. `GeneratedPluginRegistrant.swift` now also registers
  `flutter_secure_storage`, which `flutter pub get` added.
- **Not verified:** the machine used had no full Xcode, so the macOS app was
  not built. If macOS matters, run `flutter build macos` once on a Mac with
  Xcode.

### 5. One commit holds a file move that belongs to the next one

- **What:** the move of `MainActivity.kt` to `com/classlink/app/` landed in
  `5db60b5`. Its package line changed in `b990fcc`. Both build. We do not
  rewrite history, so this stays as it is. No action needed.

## Rules for this repo

- Do not change the claim protocol without telling the whole team. The golden
  vectors in `code/test/device_key_test.dart` and `backend/tests/test_crypto.py`
  must keep passing.
- Run all checks before every push:
  - `cd backend && ruff check . && ruff format --check . && python -m mypy app && python -m pytest -q`
  - `cd code && flutter analyze && flutter test`
  - Then confirm the GitHub Actions run passes.
- Never invent data. Evaluation CSVs, test counts and report numbers must come
  from real runs.
- Never commit secrets. Real values go in Render's dashboard or GitHub secrets.
- Small, focused commits. Update docs in the same commit as the change.
- Docs use plain, short sentences in active voice.

## What is left in the plan

1. **Confirm CI is green** on GitHub Actions for the latest push.
2. **Deploy:** create the Supabase project and the Render service, following
   `docs/deployment.md`. Then check `/readyz`, `/docs` and `/v1/me` on the live
   URL.
3. **Android release:** add the signing secrets in GitHub, tag `v1.0.0`, and
   check that the release has `app-release.apk`.
4. **iOS:** write the Xcode signing steps into `docs/deployment.md`.
5. **Evaluation:** write `docs/evaluation/PROTOCOL.md`. Later, add real CSVs
   from classroom runs, a summary script, and a suggested RSSI threshold.
6. **Reports:** copy the prototype report into `project-report-prototype-stage/`
   and remove the TODO files. Ask Manvi for the professor's exact name before
   editing the proposal. Update the SRS and rebuild its PDF, keeping the OT1
   cover. Update the UML diagrams, the README and the status table in
   `docs/index.md`. Write the final report in LaTeX. Add one journal entry per
   member.
7. **Finish:** all checks green, GitHub Pages turned on by Vrishank (repo
   owner), all 4 PDFs present, and a demo script with a fallback plan.
