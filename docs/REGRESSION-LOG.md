# Regression log — Firefly III Flutter app

> Rules: when something breaks, record what broke, root cause, exact fix, and how it
> was tested. Read this before diagnosing a similar symptom.

---

## R1 — Trailing comma in generated schema DDL

**Symptom.** `flutter test` failed 20/22. Every DAO test threw a SQL syntax error on
open; `app_database_test.dart` also surfaced a `LateInitializationError` for `db`
(that error was a *symptom*: the open failed, so the `late final db` fixture never
initialised, then `tearDownAll` read it).

**Root cause.** `lib/data/db/schema.dart` — the shared fragment
`syncBookkeepingColumns` ended with `seq INTEGER NOT NULL,` (trailing comma).
Every business table interpolates it as a suffix:

```sql
CREATE TABLE currencies (
    ...,
    rate TEXT,
    <syncBookkeepingColumns>   -- expands to "... seq INTEGER NOT NULL,\n"
)                             -- → syntax error: comma directly before ")"
```

**Fix.** Dropped the trailing comma so the fragment ends on `seq INTEGER NOT NULL`.
Each table already supplies the separating comma before `$syncBookkeepingColumns`,
so no other edit was needed.

**Tested.** `flutter test` went 2/22 → 21/22.

---

## R2 — WAL assertion can never hold on an in-memory database

**Symptom.** `schema WAL mode is enabled on open` expected `'wal'`, got `'memory'`.

**Root cause.** Not a product bug. The test opened an **in-memory** DB
(`openTestDatabase()`), and SQLite does not support WAL for in-memory databases —
`PRAGMA journal_mode = WAL` is a silent no-op that returns `memory`. The product
code (`_onOpen` in `database_opener.dart`) is correct; the test was asserting
something SQLite cannot provide in that configuration.

**Fix.** Pointed the test at a real file-backed DB under `Directory.systemTemp`,
which is also a closer match to the production path. Added `dart:io`.

**Tested.** 22/22.

---

## R3 — Encryption path was untested; `sqlcipher_flutter_libs` is a no-op

**Symptom.** No test covered the `password` argument of `openAppDatabase`, i.e. the
"opens with key / fails without key" exit criterion was unverified.

**Root cause (two parts).**
1. `sqlcipher_flutter_libs: ^0.7.0+eol` in `pubspec.yaml` is explicitly obsolete —
   its own README says it "no longer does anything" after the move to
   `package:sqlite3` 3.x. It was providing false confidence.
2. `sqlite3` 3.5.2 binds via `@ffi.Native` + the Dart **hooks** system, so the old
   `open.overrideFor(...)` override point no longer exists. SQLCipher must now be
   selected through `pubspec.yaml` user defines.

**Fix.**
- Added to `pubspec.yaml`:

  ```yaml
  hooks:
    user_defines:
      sqlite3:
        source: sqlcipher
  ```

  This makes `package:sqlite3` load a bundled SQLCipher build on every platform.
  (`source: system` + `name: sqlcipher` also works, but only on a machine that has
  `libsqlcipher.so` installed — it would break Android/iOS. `source: sqlcipher`
  downloads the portable prebuilt and is the correct production value.)
- New `test/data/db/encryption_test.dart` asserts all four cases: create+write with
  key, reopen with the same key, reopen with a **wrong** key throws, reopen with
  **no** key throws.

**Why the test is a real gate.** Plain SQLite treats `PRAGMA KEY` as a no-op, so
without a genuine SQLCipher build cases 3 and 4 would open successfully and the
test would fail. It only passes when encryption is actually active — confirmed via
`PRAGMA cipher_version` → `4.18.0 community`.

**Tested.** `flutter analyze` clean; `flutter test` 23/23.

---

## R4 — Golden fixture committed a live credential

**Symptom.** `test/fixtures/api/preferences.json` contained the raw Firefly CLI
access token — a 32-char hex secret. The literal value is deliberately not
reproduced here (it never left this machine: the file was caught before any
commit or push, so it should be treated as low risk — but rotate it anyway).

**Root cause.** The capture script's normalisation redacted by **key name**:

```python
REDACT_KEYS = {"access_token", "password", "secret", ...}
if k.lower() in REDACT_KEYS: ...
```

But Firefly exposes preferences as JSON:API *rows* — the credential is the row's
`attributes.data`, and the discriminator is its sibling `attributes.name`:

```json
{"attributes": {"name": "access_token", "data": "a0600e..."}}
```

The key was `data`, which is not in `REDACT_KEYS`, so nothing was masked. The same
gap hid `mfa_recovery`, `slack_webhook_url`, `pushover_app_token` and
`pushover_user_token`.

**Fix.** `infra/firefly/capture_fixtures.sh` now redacts **by row name**: when a
dict has a `name` field containing `token`/`secret`/`password`/`key`/`webhook`/
`recovery`/`apikey`, its `data` value is replaced with `<redacted>`. Key-name
matching is kept only as a backstop for endpoints that are not in row shape.

**Tested.** Re-captured all 17 fixtures; grep for the token and for
`\b[a-f0-9]{32}\b` across `test/fixtures/api/` returns nothing; the five credential
rows read `data: "<redacted>"` while non-credential prefs (`language: en_US`,
`viewRange: 1M`) are intact; `capture_fixtures.sh --check` exits 0. Locked in by
`test/api_fixtures_smoke_test.dart` → "secrets never enter committed fixtures"
(2 tests).

### Rotation — completed 2026-10-13

**What the leaked value actually was.** Not the API bearer token. It was Firefly's
**per-user cron token**, stored at `preferences.access_token` (JSON-encoded string,
32 hex chars). It is a *separate* credential from `STATIC_CRON_TOKEN` in `.env`,
which never leaked.

**It was genuinely live.** Verified before rotating:

| Call | Result |
|---|---|
| `GET /api/v1/cron/<leaked>` | **200** + real cron body |
| `GET /api/v1/cron/<random 32-hex>` | 401 `Unauthenticated` |
| `Authorization: Bearer <leaked>` | 401 (so it was never an API PAT) |

**Fix / rotation steps.** No artisan command exists for this preference
(`correction:access-tokens` targets Passport, not this row), so:
1. Backed up the DB → `infra/firefly/tmp/database.sqlite.bak-20261013-132911`.
2. `UPDATE preferences SET data = json_encode(<new 32-hex>) WHERE name = 'access_token'` via PDO inside the `app` container.
3. `php artisan cache:clear` + `docker compose restart app`.

**Verified after rotation:** old → **401**, new → **200**, `STATIC_CRON_TOKEN` →
**200** (unaffected), API `PAT` → **200** (unaffected), `app` healthy, capture
`--check` → 0, `flutter analyze` clean, `flutter test` 34/34. The new value is
stored as `FIIII_CRON_TOKEN` in `infra/firefly/.credentials` (gitignored); a
staged-content scan confirmed all four secrets appear in **0** files.

**Side effect (legitimate, not a bug).** The app restart let Firefly run its
user-group correction, backfilling `preferences.user_group_id` from `null` → `1`.
That showed up as fixture drift in `--check` — fixed by re-capturing
(`preferences.json`, 14 rows). Every other fixture was byte-identical.

---

## R5 — `flutter` on PATH is the wrong SDK for this project

**Symptom.** `flutter test` aborted with
`Because firefly_mobile requires SDK version ^3.13.5, version solving failed`.
The installed Dart was 3.7.2.

**Root cause.** Two Flutter installs exist and PATH picks the wrong one:

| SDK | Version | Verdict |
|---|---|---|
| `/home/arcore/flutter` | 3.29.2 / Dart 3.7.2 | too old for `pubspec.yaml` (`sdk: ^3.13.5`) |
| `/mnt/data/opencode/tools/flutter` | 3.47.7 / Dart 3.13.5 | correct |

`.dart_tool/version` already recorded `3.47.7`, and `pubspec.lock` pins
`flutter: ">=3.44.0"` — the project had only ever been built with the second one.

**Fix.** Use the explicit binary for every command in this project:

```bash
/mnt/data/opencode/tools/flutter/bin/flutter test
/mnt/data/opencode/tools/flutter/bin/flutter analyze
/mnt/data/opencode/tools/flutter/bin/flutter build apk --debug
```

**Tested.** `flutter test` 34/34, `flutter analyze` no issues,
`flutter build apk --debug` exit 0.

---

## Open follow-up

- `hooks.user_defines.sqlite3.source: sqlcipher` is global. Confirm the bundled
  SQLCipher build is what we want on Android/iOS before release (licensing: SQLCipher
  CE is BSD-3; the build links OpenSSL on some platforms). If we ever need a custom
  build, see `sqlite3` package `doc/hook.md`.
