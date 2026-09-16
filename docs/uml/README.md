# ClassLink UML Diagrams

This folder contains the UML diagrams for the ClassLink project report. They
describe the **current BLE proof of concept (POC)** that exists in this
repository today, plus a small number of clearly separated **future /
planned** elements that are called out visually (dashed borders, red fill,
"Not Implemented" labels) and in notes on each diagram.

**Every diagram in this folder represents the current POC, except elements
that are explicitly labelled "Future", "Planned" or "Not Implemented."** No
diagram claims the backend, database, authentication, device binding,
biometrics, audit logging, or server-side attendance records exist — those
are target architecture, not delivered code.

## What "current POC" actually means

- Teacher phone: BLE peripheral/advertiser, one active session at a time.
- Student phone: BLE central/scanner, one-hop only (no mesh, no relay).
- Session identity: a locally generated 6-digit code, carried in Android
  manufacturer-specific advertisement data, or in the iOS advertised local
  name as `CLXXXXXX` (iOS peripherals cannot advertise manufacturer data).
- Proximity check: 4 seconds of RSSI sampling, median RSSI compared against
  an experimental **-75 dBm** threshold.
- Check-in: a brief GATT connection from student to teacher, one write of a
  JSON payload containing name and roll number, then disconnect.
- Attendance is held in memory on the teacher's device for the active
  session and exported to CSV locally. There is no server, no database, and
  no cross-device sync.

## Diagram descriptions

| # | Diagram | What it shows |
|---|---------|----------------|
| 1 | Use Case | Teacher and student actions available in the POC app, and how they relate (start session includes generating a code and advertising; scanning includes discovery, code reading, and RSSI collection). |
| 2 | Class | The client-side Flutter classes involved in advertising, scanning, session-code transport, proximity evaluation, and check-in. Not a database schema. |
| 3 | Sequence | The full student check-in exchange over BLE, including the Android manufacturer-data path, the iOS local-name fallback, an invalid-code branch, a weak-RSSI rejection branch, and the successful check-in branch. |
| 4 | Activity | The student's step-by-step flow from opening student mode through permission checks, scanning, RSSI evaluation, entering details, and GATT write, with every failure branch shown. |
| 5 | Component | The Flutter app's layered architecture (presentation, application, BLE communication, native platform, dev/quality tooling), with the **planned backend shown as a separate, disconnected, dashed package.** |
| 6 | Deployment | The two physical phones, the private GitHub repository, and the build artifacts (Android APK, iOS device install) used for testing today, with the **planned cloud deployment shown as a separate, disconnected, dashed package.** |
| 7 | State | The teacher's session lifecycle state machine, from idle through Bluetooth checks, code generation, advertising, receiving check-ins, and closing the session. |

## File map

```
docs/uml/
  source/
    _style.puml                        shared skinparam include (fonts, palette)
    01-use-case-current-poc.puml
    02-class-current-poc.puml
    03-sequence-student-checkin.puml
    04-activity-student-scan.puml
    05-component-current-poc.puml
    06-deployment-current-poc.puml
    07-state-session-lifecycle.puml
  png/    <matching >.png   (300 DPI)
  svg/    <matching >.svg   (scalable, for LaTeX/Overleaf)
  latex/
    uml-figures.tex                    ready-to-paste \begin{figure} blocks
  README.md                            this file
```

## Class-diagram name mapping (report names → actual source)

The class diagram (`02-class-current-poc.puml`) uses conceptual class names
chosen for readability in the report. The actual Dart source groups some of
that behaviour into fewer files. Mapping:

| Diagram class | Actual source |
|---|---|
| `Session` | `TeacherBroadcaster` fields/methods (`sessionCode`, `startSession()`, `endSession()`) in `lib/ble/teacher_broadcaster.dart` |
| `BleAdvertiser` | `TeacherBroadcaster` + `waitForPoweredOn()` in `lib/ble/ble_constants.dart` |
| `BleScanner` | `StudentScanner` in `lib/ble/student_scanner.dart` |
| `SessionCodeTransport` | `SessionCode` class in `lib/ble/ble_constants.dart` |
| `ProximityEvaluator` | `medianRssi()` / `isWithinThreshold()` in `lib/util/rssi_math.dart` |
| `StudentProfile` | name/roll number fields captured in `lib/screens/student_checkin_screen.dart` |
| `CheckInPayload` | `CheckInPayload` class in `lib/ble/ble_constants.dart` |
| `GattCheckInService` | GATT connect/write logic inside `StudentScanner._connectAndCheckIn()` and the write-request handler in `TeacherBroadcaster` |
| `BluetoothPermissionService` | `BlePermissions` in `lib/util/permissions.dart` |

## Rendering commands

Diagrams were rendered with [PlantUML](https://plantuml.com/) (`plantuml.jar`)
using Graphviz (`dot`) for the layered component/deployment layouts. From
`docs/uml/source/`:

```bash
# PNG at 300 DPI
java -Dplantuml.dpi=300 -jar plantuml.jar -tpng -o ../png *.puml

# SVG (scalable)
java -jar plantuml.jar -tsvg -o ../svg *.puml
```

Requirements: a JRE (Java 11+) and Graphviz (`dot` on `PATH`) — install with
`brew install graphviz` on macOS, or `apt-get install graphviz` on Linux.
Diagrams that use `package`/`node` grouping (component and deployment) will
render with a degraded layout, or fail, without Graphviz installed.

To render a single diagram:

```bash
java -Dplantuml.dpi=300 -jar plantuml.jar -tpng -o ../png 05-component-current-poc.puml
```

## Inserting into the report (LaTeX / Overleaf)

1. Ensure `main.tex` has `\usepackage{graphicx}` and `\usepackage{float}` in
   its preamble (the figures use the `[H]` placement specifier).
2. Copy `docs/uml/png/` (or the whole `docs/uml/` folder) into your Overleaf
   project alongside `main.tex`, preserving the relative path
   `docs/uml/png/...`.
3. In the section where the diagrams belong (typically "Methodology and
   Design"), add:
   ```latex
   \input{docs/uml/latex/uml-figures.tex}
   ```
4. Each figure in that file already has a caption and a `\label{fig:...}`
   for cross-referencing with `\ref{fig:uml-sequence}` etc.

## Accuracy checklist

- [x] No BLE mesh or student-to-student relay is shown anywhere — every
      diagram is one-hop, teacher-to-student only.
- [x] No backend or database is shown as completed — FastAPI, Supabase and
      PostgreSQL appear only inside dashed "Not Implemented"/"Future"
      packages with no solid connection to the current system.
- [x] No biometrics or device binding is shown as completed — both appear
      only in the future/not-implemented package on the component diagram.
- [x] RSSI sampling window is shown as 4 seconds (sequence and activity
      diagrams).
- [x] RSSI threshold is shown as -75 dBm (sequence and activity diagrams).
- [x] The Android manufacturer-data path is shown explicitly (sequence and
      activity diagrams, alt/decision branches).
- [x] The iOS `CLXXXXXX` local-name fallback is shown explicitly (sequence
      and activity diagrams).
- [x] The current system shows direct, one-hop teacher-to-student BLE
      discovery — no intermediary, no server round-trip during discovery.
- [x] Check-in uses name and roll number only (class diagram
      `CheckInPayload`/`StudentProfile`, sequence diagram payload write).
- [x] The pending cross-platform two-phone test is **not** marked as
      completed anywhere; see `docs/uml/VALIDATION.md` for what evidence
      does and does not exist in this repository.
