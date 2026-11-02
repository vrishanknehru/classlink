# ClassLink

**UCS503P — Software Engineering Project, TIET**

ClassLink is a BLE-based classroom attendance system. A teacher's phone
advertises a short-lived Bluetooth Low Energy token for an active session;
enrolled students' phones scan for that token while physically nearby,
collect proximity evidence, authenticate locally, and submit a signed
attendance claim to a server-authoritative backend.

ClassLink does not claim to prove that the human owner of a phone is
present. It verifies that a bound, locally authenticated device observed a
valid classroom beacon under a configured proximity policy.

## Current status

The repository contains two working pieces and one in progress.

- **Backend (done, tested).** A FastAPI service on Supabase Postgres with
  row level security, rotating BLE tokens, device signed attendance claims,
  a live roster, corrections with a mandatory reason, an audit trail, and CSV
  export. See [`backend/`](https://github.com/vrishanknehru/classlink/tree/main/backend).
- **Offline proof of concept app (done).** A Flutter app that proves the core
  BLE mechanism: the teacher advertises, the student scans and checks in by
  proximity, and results export to CSV on the device.
- **Mobile integration with the backend (in progress).** Sign in, device key
  signing, rotating token advertising, and the live roster in the app. The
  [SRS](srs/index.md) marks each requirement as Done, POC, or Planned.

## Where to look

- [`code/`](https://github.com/vrishanknehru/classlink/tree/main/code) —
  the Flutter application source.
- [Software Requirements Specification](srs/index.md) — requirements,
  threat model, API summary, and test traceability.
- [UML diagrams](uml/README.md) — use case, class, sequence, activity,
  component, deployment, and state diagrams for the current POC.
- [`journals/`](journals/) — weekly progress journals, one per team member.
- [`project-proposal/`](https://github.com/vrishanknehru/classlink/tree/main/project-proposal) —
  the project proposal (LaTeX source and PDF).
- [`project-srs/`](https://github.com/vrishanknehru/classlink/tree/main/project-srs) —
  the SRS as LaTeX and PDF, generated from the Markdown in `docs/srs/`.

## Team

| Roll No. | Name |
|---|---|
| 1024160111 | Vemula Manvi Smaran |
| 1024160109 | Vrishank Nehru |
| 1024160102 | Mahi Singh |
| 1024160123 | Khagendra Saini |
