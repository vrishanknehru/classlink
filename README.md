# ClassLink

**UCS503P — Software Engineering Project, Thapar Institute of Engineering
and Technology**

ClassLink is a BLE-based classroom attendance system. A teacher's phone
advertises a short-lived Bluetooth Low Energy token for an active session;
enrolled students' phones scan for that token while physically nearby,
collect proximity evidence, authenticate locally, and submit a signed
attendance claim to a server-authoritative backend.

The repository currently contains a runnable **proof of concept**
validating the core BLE mechanism; see [`code/`](code/) and the docs site
for details.

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
├── code/                          Flutter application source
├── docs/                          MkDocs documentation site
├── journals/                      Weekly progress journals, one per member
├── project-proposal/              Project proposal (LaTeX)
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

## Testing

```bash
cd code
flutter analyze
flutter test
```

## Docs site

The documentation site (MkDocs) is built from `docs/` and deployed via
GitHub Actions on push to `main`. To build it locally:

```bash
make docs      # or: make docserve
```

See [`mkdocs.yml`](mkdocs.yml) for configuration.
