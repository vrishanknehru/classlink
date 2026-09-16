# ClassLink — BLE Attendance Proof of Concept

This is a minimal, offline proof-of-concept for the BLE mechanism described
in `CLAUDE.md` (the full "ClassLink Engineering Contract"). It proves out
one thing: **a teacher phone can broadcast a classroom session over BLE,
student phones can detect it by proximity (RSSI) and check in, and the
result can be exported as a CSV file.**

It intentionally does **not** implement the full contract. There is no
backend, no Supabase, no authentication, no device-key signing, no rotating
tokens, no RLS, no roles/admin panel, and no multi-classroom management.
See "Beyond the POC" below for how to start layering that in later.

## How it works

- **Teacher device**: advertises a BLE peripheral with a GATT service and a
  writable characteristic. It never scans or connects out to anyone.
- **Student device**: scans for that service, samples RSSI for a few
  seconds, and once the signal is consistently strong enough, connects
  *once* to the teacher's device and writes its name/roll number to the
  characteristic, then disconnects.
- This is strictly one-hop (student → teacher). There is no mesh and no
  student-to-student relaying, matching rule #6 of the full contract.
- When the teacher ends the session, all collected check-ins are written to
  a local CSV file (openable in Excel/Sheets) and can be shared off-device.

## Requirements

- Flutter (stable channel) with the Android toolchain set up.
- Two physical Android devices with Bluetooth LE support (BLE peripheral/
  GATT-server mode is unreliable or unsupported on most emulators, so this
  must be tested on real hardware).

## Running it

```bash
flutter pub get
flutter run
```

Install the app on two Android phones. On one, choose **"I'm the Teacher"**
and start a session. On the other, choose **"I'm a Student"**, enter a name
and roll number, and start checking in. Move the student phone closer to
the teacher phone until it checks in. Back on the teacher phone, end the
session to export a CSV.

## Testing

```bash
flutter analyze
flutter test
```

## Project layout

```
lib/
├── main.dart                       role picker (Teacher / Student)
├── ble/
│   ├── ble_constants.dart          shared UUIDs + payload encode/decode
│   ├── teacher_broadcaster.dart    PeripheralManager: advertise + GATT server
│   └── student_scanner.dart        CentralManager: scan, RSSI sampling, connect + write
├── attendance/
│   ├── attendance_record.dart      simple data class
│   └── csv_export.dart             CSV encoding, file save, share
├── screens/                        role picker + teacher/student screens
└── util/
    ├── rssi_math.dart              median RSSI + threshold check (unit tested)
    └── permissions.dart            runtime BLE/location permission requests
```

## Beyond the POC: creating a Supabase project

This POC has no backend and doesn't need one. When you're ready to build
towards the full contract in `CLAUDE.md` (persisted sessions, auth, roles,
audit trail, etc.), you'll need a Supabase project:

1. Go to [supabase.com](https://supabase.com) and sign in (or create an
   account).
2. Click **New project**, pick an organization, name the project, set a
   database password, and choose a region close to your users.
3. Once it's provisioned, go to **Project Settings → API**.
4. Copy the **Project URL** and the **anon public** key — these are what a
   future client app would use to talk to Supabase.
5. Don't commit these to source control. When they're actually wired up,
   put them in a local `.env` file (or platform-appropriate secret storage)
   that's excluded via `.gitignore`.

No code in this POC reads these values yet — this is just prep for the next
phase of the project.
