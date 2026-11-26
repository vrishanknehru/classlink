# Deployment and Pilot Runbook

This runbook takes ClassLink from a clean checkout to a running pilot. The
steps that need an account, a payment method, or a secret belong to a person on
the team. Nothing here asks you to put a secret in the repository.

## What you deploy

| Piece | Where it runs | How it gets there |
|---|---|---|
| Postgres, Auth | Supabase project | You create the project and apply one SQL file |
| API | Any container host (Render blueprint included) | `render.yaml`, or the image from GitHub Container Registry |
| Android app | Students' and teachers' phones | The APK from the `android-release` workflow |
| iOS app | iPhones | Built from `code/` in Xcode with the same `--dart-define` values |

## 1. Create the Supabase project

1. Create a project at supabase.com. Note the region and the database password.
2. Open **SQL Editor**, paste `backend/migrations/0001_init.sql`, and run it.
   It creates the tables, the row level security policies, and the helper
   functions. It does not seed any data.
3. Collect three values:
   - **Connection string.** Click **Connect** at the top of the project page
     and copy the **Session pooler** string. It looks like
     `postgresql://postgres.<project-ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`.
     Do not use the other two choices:
     - The **direct connection** (`db.<project-ref>.supabase.co`) is IPv6 only
       on the free plan. Render cannot reach IPv6 addresses, so the API would
       fail to connect.
     - The **transaction pooler** (port 6543) hands each query to a different
       server connection. psycopg's prepared statements can then fail with
       "prepared statement does not exist".

     The session pooler uses IPv4 and port 5432, and keeps one server
     connection per client connection, so neither problem happens. The string
     logs in as the `postgres` role, which bypasses row level security, so it
     stays on the server only.
   - **Signing method.** Project Settings, JWT Keys. New projects sign user
     tokens with an asymmetric key (ES256 or RS256). The API fetches the public
     keys from `<project URL>/auth/v1/.well-known/jwks.json` and caches them, so
     it only needs the project URL. If the page shows a legacy shared secret
     (HS256), copy it too. The API then accepts both kinds of token.
   - **Anon key and project URL.** The mobile app needs these to sign users in.
     They are safe to ship in the app.
4. Under Authentication, turn on the sign in method you want for the pilot
   (email with password is the simplest). Consider restricting sign up to your
   college email domain.

## 2. Generate the token secret

```bash
python -c "import secrets; print(secrets.token_hex(32))"
```

Store it as `CLASSLINK_TOKEN_HMAC_SECRET`. Changing it invalidates every token
already advertised, which is harmless between sessions.

## 3. Deploy the API

### Option A: Render

1. In Render, choose **New, Blueprint** and pick this repository. It reads
   `render.yaml`.
2. Fill in the values when prompted:
   - `CLASSLINK_DATABASE_URL`: the connection string.
   - `CLASSLINK_SUPABASE_URL`: the project URL, such as
     `https://abcd.supabase.co`. The API reads the signing keys from it.
   - `CLASSLINK_JWT_SECRET`: only if your project still has a legacy HS256
     secret. Leave it empty otherwise.
   - `CLASSLINK_TOKEN_HMAC_SECRET`: the value from step 2.
   - `CLASSLINK_TEACHER_EMAILS`: a JSON list such as `["name@thapar.edu"]`.

   The API refuses to start unless at least one of `CLASSLINK_SUPABASE_URL` and
   `CLASSLINK_JWT_SECRET` is set.
   The blueprint uses Render's **free** plan. A free service sleeps after 15
   minutes without traffic. The next request wakes it, which takes about a
   minute. Open `/healthz` a minute or two before a class or a demo so the
   first check in does not wait. A paid plan does not sleep.
3. After the first deploy, open `https://<your-service>/readyz`. It must answer
   `{"status":"ready"}`. Then open `/docs` for the live API reference.

### Option B: any container host

The `backend-image` workflow publishes `ghcr.io/vrishanknehru/classlink-backend`
on every push to `main` and on tags. Run it with the same environment
variables plus `CLASSLINK_ENVIRONMENT=production`, behind HTTPS.

### Settings you may tune

All are `CLASSLINK_*` variables. `backend/.env.example` lists the required ones.

| Variable | Default | Meaning |
|---|---|---|
| `TOKEN_PERIOD_SECONDS` | 15 | How often the BLE token rotates (5 to 120) |
| `TOKEN_GRACE_EPOCHS` | 1 | How many old epochs still validate |
| `CHALLENGE_TTL_SECONDS` | 120 | How long a nonce lives |
| `CLAIM_MAX_AGE_SECONDS` | 60 | Allowed gap between the phone's observation time and the server clock |
| `JWKS_CACHE_SECONDS` | 600 | How long the API keeps Supabase's public keys before fetching them again |

## 4. Make the first teacher

The teacher role comes from `CLASSLINK_TEACHER_EMAILS`. Add the teacher's
email, redeploy, then have them sign in and create their profile. Anyone not on
the list becomes a student. There is no in app way to grant teacher.

## 5. Build and distribute the APK

0. In **Settings > Secrets and variables > Actions > Variables**, add
   `CLASSLINK_API_BASE_URL` (the API's https address), `SUPABASE_URL` and
   `SUPABASE_ANON_KEY`. The workflow bakes them into the APK. To build by hand:
   ```bash
   cd code
   flutter build apk --release \
     --dart-define=API_BASE_URL=https://classlink-api.onrender.com \
     --dart-define=SUPABASE_URL=https://abcd.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=eyJ...
   ```
   For iPhones use `flutter build ipa` with the same flags and your Apple team.
1. In the GitHub repository settings, add four secrets for release signing:
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
   and `ANDROID_KEY_PASSWORD`. Create the keystore yourself and keep a backup.
   Losing it means you cannot update installed apps.
   ```bash
   keytool -genkeypair -v -keystore classlink.jks -alias classlink \
     -keyalg RSA -keysize 2048 -validity 10000
   base64 -w0 classlink.jks   # paste as ANDROID_KEYSTORE_BASE64
   ```
2. Push a tag: `git tag v0.2.0 && git push origin v0.2.0`. The workflow runs the
   analyzer and tests, builds `app-release.apk`, and attaches it to the release.
3. Students install the APK by sideloading it. Without the four secrets the
   workflow still builds, signed with the debug key. That is fine for a pilot
   and not for the Play Store.

The Android application id and the iOS bundle id are `com.classlink.app`.
Change them before any store upload if the college wants its own domain,
because they cannot change afterwards.

## 6. Pilot checklist

- [ ] `/readyz` is green and `/docs` loads.
- [ ] A teacher account exists and can create a classroom.
- [ ] Two student phones of different models joined the classroom.
- [ ] Each student phone bound its device key.
- [ ] One test session ran end to end and the CSV export opened correctly.
- [ ] Participants know what the app stores (name, roll number, email, device
      key, attendance) and that it never collects location.

## 7. Operating it

- **Health.** Point an uptime monitor at `/readyz`.
- **Backups.** Turn on Supabase backups for the project. Attendance records are
  the product.
- **What happened to a claim.** Rejections and acceptances live in
  `audit_events`. Example:
  ```sql
  select created_at, details->>'reason' as reason, details->>'stage' as stage
  from audit_events where action = 'claim_rejected' order by id desc limit 50;
  ```
- **Rotating secrets.** Change the token secret or JWT secret in the host's
  dashboard and redeploy. Changing the JWT secret signs everyone out.
- **Rollback.** Redeploy the previous image tag. Migrations are additive in
  version 1.0, so no database rollback is needed.

## Local development

```bash
docker compose up --build        # Postgres + API on :8000
python backend/scripts/dev_token.py teacher@example.edu
```

The script prints a user id and a bearer token. Insert the user into
`auth.users` first (the script's docstring shows the command). The compose
stack uses throwaway credentials and is not a deployment target.
