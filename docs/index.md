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

The repository currently contains a runnable **proof of concept**: an
offline Flutter app that proves the core BLE mechanism (teacher advertises,
student scans and checks in by proximity, results export to CSV). It does
not yet implement the backend, authentication, device-key signing, rotating
tokens, or row-level security that the full system is designed to include.

## Where to look

- [`code/`](https://github.com/vrishanknehru/classlink/tree/main/code) —
  the Flutter application source.
- [UML diagrams](uml/README.md) — use case, class, sequence, activity,
  component, deployment, and state diagrams for the current POC.
- [`journals/`](journals/) — weekly progress journals, one per team member.
- [`project-proposal/`](https://github.com/vrishanknehru/classlink/tree/main/project-proposal) —
  the project proposal document.

## Team

| Roll No. | Name |
|---|---|
| 1024160111 | Vemula Manvi Smaran |
| 1024160109 | Vrishank Nehru |
| 1024160102 | Mahi Singh |
| 1024160123 | Khagendra Saini |
