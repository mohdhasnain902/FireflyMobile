# Firefly III Mobile

Offline-first Android expense tracker that syncs bidirectionally with a
self-hosted [Firefly III](https://firefly-iii.org/) instance.

Everything works offline; sync is a background concern, never a UI blocker.

---

## Stack

| Layer | Choice |
|-------|--------|
| UI | Flutter 3.47.7 (Material 3), Riverpod |
| Local DB | SQLite via `sqflite`, encrypted with SQLCipher |
| Sync | Ordered op-log, push-then-pull, field-level LWW merge |
| Transport | Firefly III REST API over Tailscale |
| Backup | SQLite snapshot + CSV export to PC sidecar (P4) |

---

## Architecture

```
Phone                              PC (CachyOS)               Tailscale
┌─────────────┐                    ┌─────────────┐           ┌──────────┐
│ Flutter UI  │                    │ Firefly III │           │ WireGuard│
│ (Riverpod)  │                    │ (Docker,    │           │ Mesh     │
└──────┬──────┘                    │  pinned tag)│           │          │
       │ reads/writes only        └──────┬──────┘           └────┬─────┘
       │ through repo layer             │                          │
       ▼                                  │                          │
┌─────────────┐                    ┌─────────────┐           ┌──────────┐
│ Local SQLite│                    │ Backup Dir  │           │ MagicDNS │
│ (SQLCipher) │◄──── sync ─────────│ (snapshots  │───────────│ *.ts.net │
│             │   push→pull        │  + CSV)     │           │          │
└─────────────┘                    └─────────────┘           └──────────┘
       ▲
       │ op-log append
       │ in same txn as row write
┌─────────────┐
│ Op Log      │
│ (ordered)   │
└─────────────┘
```

---

## Quick Start

### Prerequisites

- Flutter 3.47.7+ (`/mnt/data/opencode/tools/flutter`)
- Android SDK (`$HOME/Android/Sdk`)
- A self-hosted Firefly III instance (see `docs/DESIGN.md` P0.2)
- Tailscale on PC + phone (same tailnet)
- A Firefly III Personal Access Token (PAT)

### Build

```sh
export PATH="/mnt/data/opencode/tools/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"

cd app
flutter pub get
dart format lib test
flutter analyze        # must stay clean
flutter test           # must stay green
flutter build apk --debug
```

CI runs the same four gates on every push/PR (`.github/workflows/ci.yml`).

---

## First Run

1. Install the debug APK on your Android phone.
2. Join the same Tailscale tailnet as your PC.
3. Open the app → **Settings** → enter:
   - **Firefly base URL**: `http://firefly.<pc-hostname>.ts.net` (or `http://<pc-tailscale-ip>:8080`)
   - **PAT**: from Firefly UI → Options → Profile → OAuth → Create new token
   - **Backup sidecar URL** (optional): `http://<pc-tailscale-ip>:8095` + sidecar token
4. Tap "Sync now" — the app pushes pending ops, pulls server changes, and (if configured) triggers a PC backup.

---

## Sync

- **Automatic:** on app foreground + network available (debounced 5s).
- **Manual:** pull-to-refresh on any list, or "Sync now" in Settings.
- **Order:** push first (local edits land on server), then pull (server diff merged).
- **Offline:** full CRUD works in airplane mode; rows show `pending` badges until synced.

---

## Backup (P4)

After every successful sync, the app triggers the PC backup sidecar:

1. SQLite snapshot of Firefly's `database.sqlite` → `~/firefly-backups/firefly-YYYYMMDDTHHMMSSZ.sqlite`
2. CSV export of all entities → `~/firefly-backups/csv-YYYYMMDDTHHMMSSZ/`
3. Rotation keeps the last 30 snapshots + CSV dirs.

The sidecar runs on the PC (`infra/firefly/backup_sidecar.py`), not the phone. Phone loss does not lose backups.

---

## Restore from Server

1. Install Firefly III on a new PC (or restore from the latest `firefly-*.sqlite` snapshot).
2. Install the Flutter app on the phone.
3. Enter Tailscale auth key + Firefly base URL + PAT.
4. Tap **Settings → Restore from server** — full pull (no push), wipes local first.
5. Verify: spot-check last 10 transactions, account balances, budget totals.

---

## Project Structure

```
app/
  lib/
    core/        constants, Result type, typed Failures, settings
    domain/      entities (freezed), repository interfaces
    data/        SQLite, DAOs, repository implementations, API client
    sync/        op log, sync engine, pull engine, backup client
    ui/          screens, widgets, theme
  test/          unit + widget tests
  integration_test/  end-to-end tests
docs/
  DESIGN.md           architecture + data model + sync protocol
  IMPLEMENTATION-PLAN.md  phased build plan (P0–P6)
  SECURITY-AUDIT.md   P5.4 security review
  REGRESSIONS.md      P6.3 regression log
infra/firefly/
  docker-compose.yml  pinned Firefly III (SQLite, no MariaDB)
  backup_sidecar.py   PC-side backup trigger (P4)
  .env                Firefly env (gitignored)
  .credentials        FIIII_PAT (gitignored)
scripts/
  seed_demo_data.py   realistic demo data seeder
  test_backup_sidecar.py  sidecar unit tests (rotation, run_backup)
```

---

## Testing

```sh
flutter test             # all unit + widget tests
flutter test --coverage  # coverage report (target > 80% on lib/sync/ + lib/data/)
flutter analyze          # static analysis (must be clean)
dart format lib test     # formatting check
```

Integration tests (gated, require a running Firefly instance):

```sh
FIREFLY_LIVE=1 flutter test test/integration/live_sync_e2e_test.dart
BACKUP_TEST=1 flutter test test/integration/backup_after_sync_test.dart
```

---

## License

See `NOTICE.md` for bundled third-party attributions (SQLCipher BSD-3, SQLite, OpenSSL).
