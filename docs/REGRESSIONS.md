# Firefly III Mobile — Regression Log (P6.3)

Regressions found and fixed during P0–P5 development, grouped by area. Each entry
records: symptom, root cause, fix, and how it was verified. Read this before
diagnosing a similar symptom.

---

## Schema & Data Layer

### R1 — Trailing comma in generated schema DDL

**Symptom.** `flutter test` failed 20/22. Every DAO test threw a SQL syntax error
on open.

**Root cause.** `lib/data/db/schema.dart` — `syncBookkeepingColumns` ended with
`seq INTEGER NOT NULL,` (trailing comma), producing `... seq INTEGER NOT NULL,\n)`
in every `CREATE TABLE`.

**Fix.** Dropped the trailing comma so the fragment ends on `seq INTEGER NOT NULL`.

**Tested.** `flutter test` went 2/22 → 21/22 → 22/22 (after R2 fix).

---

### R2 — WAL assertion can never hold on an in-memory database

**Symptom.** Schema WAL-mode test expected `'wal'`, got `'memory'`.

**Root cause.** The test opened an in-memory DB; SQLite silently no-ops WAL on
`:memory:`. Product code (`_onOpen` in `database_opener.dart`) was correct.

**Fix.** Pointed the test at a real file-backed DB under `Directory.systemTemp`.

**Tested.** 22/22.

---

### R3 — Encryption path was untested; `sqlcipher_flutter_libs` is a no-op

**Symptom.** No test covered the `password` argument of `openAppDatabase`.

**Root cause.** `sqlcipher_flutter_libs: ^0.7.0+eol` is obsolete (README says it
"no longer does anything" after `sqlite3` 3.x moved to the Dart hooks system).

**Fix.** Added `hooks.user_defines.sqlite3.source: sqlcipher` to `pubspec.yaml`
so `package:sqlite3` loads a bundled SQLCipher build on every platform. New
`test/data/db/encryption_test.dart` asserts create/write/reopen/wrong-key/no-key.

**Tested.** `flutter analyze` clean; `flutter test` 23/23.

---

### R4 — Golden fixture committed a live credential

**Symptom.** `test/fixtures/api/preferences.json` contained Firefly's live per-user
cron token (32 hex chars) plus `mfa_recovery`, `slack_webhook_url`, and pushover
tokens.

**Root cause.** Fixture capture redacted by key name (`data`), not row name
(`attributes.name`). The credential lived in `attributes.data` keyed by
`attributes.name: "access_token"`.

**Fix.** `capture_fixtures.sh` now redacts by row name: when a dict has a `name`
field containing token/secret/password/key/webhook/recovery/apikey, its `data`
value is replaced with `<redacted>`. Key-name matching kept as backstop.

**Tested.** Re-captured all 17 fixtures; grep for `\b[a-f0-9]{32}\b` returns
nothing; credential rows read `<redacted>`; non-credential prefs intact;
`capture_fixtures.sh --check` exits 0. Token rotated in the live DB.

---

### R5 — `flutter` on PATH is the wrong SDK for this project

**Symptom.** `flutter test` aborted: SDK version `^3.13.5` required, installed
Dart was 3.7.2.

**Root cause.** Two Flutter installs exist; PATH picks `/home/arcore/flutter`
(3.29.2/Dart 3.7.2) instead of `/mnt/data/opencode/tools/flutter`
(3.47.7/Dart 3.13.5).

**Fix.** Use the explicit binary for every command:
`/mnt/data/opencode/tools/flutter/bin/flutter test|analyze|build`

**Tested.** `flutter test` 34/34; `flutter analyze` no issues;
`flutter build apk --debug` exit 0.

---

### R6 — `Transaction` entity never compiled: missing `fireflyId`

**Symptom.** `transaction_test.dart` failed to load: `_Transaction` missing
implementations of `SyncBookkeeping.fireflyId`.

**Root cause.** `Transaction` was the only entity whose factory constructor did
not declare `String? fireflyId`, while `with _$Transaction, SyncBookkeeping`
requires it. `toJsonApi` also emitted `id: null`.

**Fix.** Added `fireflyId` to constructor, `fromJsonApi`, `fromRow`/`toRow`, and
`toJsonApi` (matching every other entity pattern). Regenerated freezed.

**Tested.** `flutter test` 202/202 (all 14 entity round-trip suites);
`flutter analyze` → No issues found.

---

### R7 — `Bill.next_expected_match` wrote epoch millis into a TEXT column

**Symptom.** `entity_persistence_test.dart` failed `Bill row survives a real SQLite
round trip` — re-parsing threw `TypeError`.

**Root cause.** `Bill.toRow` wrote `nextExpectedMatch?.millisecondsSinceEpoch` (an
int) into a TEXT column. `Bill.fromRow` then read it with `as int?`, which throws
against text.

**Fix.** `Bill.toRow` uses `dateTimeToIso()`; `Bill.fromRow` uses `isoToDateTime()` — matching every other TEXT date column.

**Tested.** `entity_persistence_test.dart` 15/15; full `flutter test` 217/217.

---

### R10 — Entity `==` fails: local `DateTime` vs UTC-decoded row

**Symptom.** Seven `entity_dao_test.dart` assertions failed with
"identical-looking" datetimes (e.g. `1970-01-01 05:00:01.000` vs
`1970-01-01 00:00:01.000Z`) — same epoch, different `isUtc` flag.

**Root cause.** `millisToDateTime` decodes rows with `isUtc: true`. Dart's
`DateTime.==` compares epoch **and** `isUtc`. Test helpers built local-time
`DateTime`s that never matched.

**Fix.** Test helpers now build `DateTime.fromMillisecondsSinceEpoch(ms,
isUtc: true)` to mirror the decoder. No production code changed.

**Tested.** Covered by the previously failing assertions themselves.

---

### R11 — `generateDatabaseKey` doc said "43 chars"; encoder pads to 44

**Symptom.** Key-format assertion doc claimed 43 base64-url chars.

**Root cause.** Dart's `base64Url.encode` pads to a multiple of four — 32 bytes
encode to 44 chars.

**Fix.** Comment corrected to "44 chars: 43 payload + one `=` padding". Test now
pins `hasLength(44)` + regex + `base64Url.decode` length.

**Tested.** Dart probe confirmed `len=44`, decodes to 32 bytes.

---

### R14 — `Uri.port == 0` never drops a default port

**Symptom.** `normalizeBaseUrl('https://x.example.com')` returned
`https://x.example.com:443`.

**Root cause.** Dart synthesizes scheme-default ports — `Uri.port` is always a
number (443 for `https`), and `hasPort` is `false` both for omitted ports and
explicit defaults (`:443`).

**Fix.** Key off `hasPort` (true only for genuinely non-default ports) instead of
`uri.port == 0`.

**Tested.** `connection_settings_test.dart` 5 cases; `settings_screen_test.dart`
save-normalize case. Full run: `flutter test` 321/321.

---

### R15 — `SyncEngine.sync()` success path never set `last_sync_status='ok'`

**Symptom.** App-bar sync indicator never showed `ok` after a successful cycle.

**Root cause.** `sync()` wrote `last_sync_ts` on success but only wrote
`last_sync_status='error'` on failure paths. `restoreFromServer` correctly wrote
`'ok'`.

**Fix.** Added `_setLastStatus('ok')` at the end of the `sync()` success path.

**Tested.** `sync_engine_test.dart` 10/10; full `test/data/` 118/118.

---

### R16 — Recurrence Model B migration replayed onto a v1 table

**Symptom.** `entity_persistence_test.dart` failed in `setUpAll` with `no such
column: recur_until`.

**Root cause.** `_initialSchema` was edited in place to Model B shape while the
migration map still carried `RENAME COLUMN recur_until` / `DROP COLUMN
repeat_freq`. SQLite replays **every** migration on `onCreate`, so each ran
against the table v1 just created — rename targeted a non-existent column,
child-table CREATE hit "table already exists".

**Fix.** `recurrences` now carries the full Model B column set from v1; migration
map collapsed to `{1: _initialSchema}`. Model B v2 folded in because v1 never
shipped under its earlier shape.

**Tested.** `test/domain/entities/` 188/188; full `flutter test` 390/390.

---

### R17 — `const FieldSpec` with closures fails to compile

**Symptom.** 5 test suites failed to load: `Not a constant expression` /
`Method invocation is not a constant expression` at `entity_configs.dart`.

**Root cause.** Three `FieldSpec`s in `recurrencesConfig` (`repeatUntil`,
`nrOfRepetitions`, `repetitions`) were `const` while carrying `requiredWhen`/
`isValid` function closures — Dart closures are never constant-evaluable.

**Fix.** Dropped `const` on exactly those three specs.

**Tested.** `dart analyze lib/` → 0 errors (was 17+); full `flutter test` 390/390.

---

### R18 — P4 handoff left `flutter analyze` at 77 (baseline 62)

**Symptom.** After P4 Story-2, `flutter analyze` reported 77 issues instead of 62.

**Root cause.** 15 new infos in `backup_client.dart` (missing `library`,
`comment_references` ×3, `unnecessary_type_name_in_constructor` ×3,
`sort_constructors_first`, `prefer_initializing_formals` ×2,
`avoid_catches_without_on_clauses`, `omit_local_variable_types`), `providers.dart`
(merged doc blocks → `public_member_api_docs`), `sync_engine.dart`
(`prefer_initializing_formals`, bare `catch (_)`).

**Fix.** Fixed all 15 lints with no behavior change. `backup_client.dart` ctors
→ `const new(...)`/`const new disabled()`, params hoisted to init-list;
`catch (exc)` → `on Object catch (exc)`; doc symbol links → plain code spans.

**Tested.** `flutter analyze` 77 → 62 (exact baseline); `flutter test` 438/438.

---

### R19 — Linux desktop switch stalled `app_smoke_test`

**Symptom.** `app_smoke_test.dart` hung at `pumpAndSettle` (spinner ticking
forever) after moving to `databaseFactoryFfi`.

**Root cause.** `testWidgets` fake-async zone never drains real dart:io / FFI
isolate completions — `databaseProvider` stays in `AsyncLoading` forever.

**Fix.** Test-side only: open a real in-memory DB in `setUpAll` and override
`databaseProvider` with it. The Linux boot path itself is correct (opens in
252 ms outside `testWidgets`).

**Tested.** `app_smoke_test.dart` 2/2; full suite 438/438; `flutter analyze` 62.

---

### R21 — `FireflyApiClient.create/update` sent wrong wire contract

**Symptom.** Live `create` rejected with 422 `{"name": ["The name field is
required."]}`.

**Root cause.** The client sent `{type, attributes}` (JSON:API member body) but
Firefly create/update endpoints expect flat attributes. Responses stay JSON:API
wrapped.

**Fix.** `_requestBody` unwraps to flat attributes for create/update; responses
remain JSON:API-wrapped. Three tests re-pinned to the correct contract.

**Tested.** Client suite 24/24; full suite 466/466; live e2e 1/1 PASS against
pinned Docker instance.

---

### R22 — PC-backup section broke 6 widget tests via ListView cacheExtent

**Symptom.** Inserting the backup section into Settings pushed lower tiles past
the `ListView` `cacheExtent`; `find.text` matched 0 for lazily-unbuilt tiles.

**Fix.** All backup/widget tests now `scrollUntilVisible(…, 200, scrollable: …)`
before matching tiles below the fold.

**Tested.** `settings_screen_test.dart` +6; `backup_client_test` 6;
`sync_engine_test` backup wiring +4. Full suite 466/466.

---

## Open follow-up

None open. All regressions from P0–P5 are resolved and pinned by tests.
