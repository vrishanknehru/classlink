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
| `flutter analyze` | **Fails. Exit code 1, 9 issues.** See issue 1. |

Flutter version used: 3.50.1, stable channel, Dart 3.14.0.

## Open issues

### 1. `flutter analyze` fails on the current stable Flutter (blocks CI)

- **Owner:** Flutter (Vrishank or Khagendra).
- **What:** Flutter 3.47 and later mark `package:flutter/material.dart` as
  deprecated. The notice says to use `package:material_ui/material_ui.dart`.
  `flutter analyze` treats these info notices as failures.
- **Where:** the first line of these 9 files:
  - `code/lib/main.dart`
  - `code/lib/screens/home_gate.dart`
  - `code/lib/screens/profile_setup_screen.dart`
  - `code/lib/screens/sign_in_screen.dart`
  - `code/lib/screens/student_checkin_screen.dart`
  - `code/lib/screens/student_home_screen.dart`
  - `code/lib/screens/teacher_home_screen.dart`
  - `code/lib/screens/teacher_session_screen.dart`
  - `code/lib/screens/widgets.dart`
- **Why it matters:** CI (`.github/workflows/ci.yml`) and the release workflow
  install the `stable` channel and run `flutter analyze`. So CI most likely
  fails now, even on code from before this push.
- **Suggested fix:** add `material_ui` to `code/pubspec.yaml` and switch the 9
  imports. Then run `flutter analyze` and `flutter test`. Do not pin CI to an
  old Flutter just to hide the notice.
- **Note:** on the new Flutter, `flutter pub get` also rewrites
  `code/analysis_options.yaml` (it adds an `analyzer: exclude:` list) and
  `code/pubspec.lock`. Commit those changes only on purpose, in the same
  commit as the upgrade.

### 2. An empty `CLASSLINK_JWT_SECRET` stopped the API from starting (fixed)

- **Status:** fixed. `backend/app/config.py` now sets `env_ignore_empty=True`,
  so a key set to an empty value counts as unset. The test
  `test_empty_optional_values_count_as_unset` in `backend/tests/test_config.py`
  covers it. "Leave it empty" in `docs/deployment.md` is now safe.

### 3. One new Flutter test checks nothing

- **Owner:** Flutter.
- **What:** `TeacherSessionController` writes the running session id to secure
  storage (`code/lib/teacher/session_controller.dart:75`, `:83`, `:191`), but
  nothing in `code/lib` reads it back. Resume now asks the server instead. The
  test "a stale saved id is replaced by the session the server reports" in
  `code/test/session_controller_test.dart` passes whatever the code does.
- **Suggested fix:** remove the unused `_activeKey` writes and that one test.
  The other resume tests already cover the real path. Or give the saved id a
  real use and test that.

### 4. macOS still uses the old bundle id

- **Owner:** iOS and macOS (Khagendra), low priority.
- **What:** `code/macos/Runner/Configs/AppInfo.xcconfig:11` still says
  `com.classlink.poc.bleAttendancePoc`. Android is now `com.classlink.app`.
  This only matters if macOS becomes a target.

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

1. **Fix issues 1 to 3** above, then get CI green.
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
