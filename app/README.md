# Firefly Mobile

Offline-first Android expense tracker that syncs bidirectionally with a
self-hosted [Firefly III](https://firefly-iii.org/) instance.

- Architecture and decisions: [`../docs/DESIGN.md`](../docs/DESIGN.md)
- Phased build plan: [`../docs/IMPLEMENTATION-PLAN.md`](../docs/IMPLEMENTATION-PLAN.md)

## Stack

| Layer | Choice |
|---|---|
| UI | Flutter 3.47.7 (Material 3), Riverpod |
| Local DB | SQLite via `sqflite`, encrypted with SQLCipher |
| Sync | Ordered op-log, push-then-pull, field-level LWW merge |
| Transport | Firefly III REST API over Tailscale |

Everything works offline; sync is a background concern, never a UI blocker.

## Development

```sh
export PATH="/mnt/data/opencode/tools/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"

flutter pub get
dart format lib test
flutter analyze        # must stay clean
flutter test           # must stay green
flutter build apk --debug
```

CI runs the same four gates on every push and pull request
(`.github/workflows/ci.yml`).

## Layout

```
lib/
  core/     # constants, Result type, typed Failures
  domain/   # entities, repository interfaces
  data/     # SQLite, DAOs, repository implementations
  sync/     # op log, sync engine, Firefly API client
  ui/       # screens, widgets
test/       # unit + widget tests
integration_test/
```

Dependency rule: `ui` → `domain` ← `data`. The `sync` module depends on
`domain` and `data`, never on `ui`.
