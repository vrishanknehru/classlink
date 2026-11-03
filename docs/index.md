# ClassLink

**UCS503P — Software Engineering Project, TIET**

ClassLink is a BLE-based classroom attendance system. A teacher's phone
shares a short-lived session token over Bluetooth Low Energy; enrolled
students' phones find it while physically nearby, measure signal strength,
and send a claim signed with a per phone key to a server that makes the
final decision.

ClassLink does not claim to prove that the human owner of a phone is
present. It verifies that a bound, locally authenticated device observed a
valid classroom beacon under a configured proximity policy.

## Current status

| Part | Status |
|---|---|
| Backend | Done. FastAPI on Supabase Postgres: rotating tokens, signed claims, 14 rejection reasons, live roster, corrections with a reason, audit log, CSV export. 78 tests. |
| Flutter app (Android and iOS) | Done and connected to the server: sign in, classrooms, teacher session with live roster, one tap student check in with a signed claim. 47 tests. |
| SRS | Done. [Read it here](srs/index.md), or the [PDF](https://github.com/vrishanknehru/classlink/blob/main/project-srs/ClassLink-SRS.pdf). |
| Deployment | Files ready: Docker image, Render blueprint, release workflow. See the [runbook](deployment.md). Server not live yet. |
| Next | Put the server live, then test check in on real phones in a classroom. |

## Where to look

- [`code/`](https://github.com/vrishanknehru/classlink/tree/main/code) —
  the Flutter application source.
- [Software Requirements Specification](srs/index.md) — requirements,
  threat model, API summary, and test traceability.
- [UML diagrams](uml/README.md) — use case, class, sequence, activity,
  component, deployment, and state diagrams for the current POC.
- Weekly journals, one per team member:
  [Manvi](journals/1024160111-vemula-manvi-smaran/index.md),
  [Vrishank](journals/1024160109-vrishank-nehru/index.md),
  [Mahi](journals/1024160102-mahi-singh/index.md),
  [Khagendra](journals/1024160123-khagendra-saini/index.md).
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
