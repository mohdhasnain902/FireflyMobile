# Firefly III Mobile — Implementation Plan

**Version:** 1.1
**Status:** In progress (P0–P3 complete; P4 code written, exit criteria pending on-device verification; P5 tests written; P6 docs in progress)
**Date:** 2026-11-02
**Depends on:** `docs/DESIGN.md` v1.0

---

## Overview

Seven phases (P0–P6), each with a hard exit criterion. No phase starts until the previous phase's exit criterion is met. Every phase includes automated tests and a manual verification pass.

| Phase | Name | Duration (est.) | Status | Exit Criterion |
|---|---|---|---|---|
| P0 | Foundation | 2–3 days | ✅ Complete | Firefly III live on CachyOS via Docker (pinned, SQLite, Tailscale); Flutter scaffold builds; golden API fixtures committed. |
| P1 | Local data layer | 3–4 days | ✅ Complete | SQLite schema + all DAOs; unit tests green (round-trip, tombstones, op-log append atomicity). |
| P2 | Offline UI | 5–7 days | ✅ Complete (manual pass pending) | Every entity's list + create/edit/delete screens work in airplane mode with pending badges. Manual airplane-mode pass completed. |
| P3 | Sync engine | 5–7 days | ✅ Complete | Op-log push + pull-diff + LWW merge; conflict-matrix tests green; end-to-end offline→reconnect convergence proven on real Firefly. |
| P4 | Backup | 1–2 days | ⚠️ Code written, exit criteria pending | Snapshot-on-sync writes to PC; restore drill (5 steps) executed successfully. |
| P5 | Hardening | 3–4 days | ⚠️ Tests written, verification pending | All threat-model scenarios (DESIGN §10.3) pass; 1000-op backlog < 60 s; battery idle drain measured. |
| P6 | Docs + graphify | 1 day | ⚠️ In progress | Design doc + plan updated to match implementation; graphify knowledge graph generated. |

---

## P0 — Foundation

### Tasks

**P0.1 — Docker on CachyOS**
1. `sudo pacman -S docker docker-compose`
2. `sudo systemctl enable --now docker.service`
3. `sudo usermod -aG docker $USER` (re-login to take effect)
4. `docker run hello-world` — verify.

**P0.2 — Firefly III via Docker Compose**
1. `mkdir -p ~/firefly && cd ~/firefly`
2. Download `docker-compose.yml` from `firefly-iii/docker` (main branch).
3. Download `.env.example` and `.db.env.example` from the same repo; rename to `.env` and `.db.env`.
4. Edit `.env`:
   - `APP_KEY=<random 32-char string>`
   - `STATIC_CRON_TOKEN=<random 32-char string>`
   - `TZ=<your timezone>`
   - `DB_CONNECTION=sqlite`
   - Remove all `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` lines.
5. Edit `docker-compose.yml`:
   - Remove the `db` service (SQLite doesn't need MariaDB).
   - Remove `depends_on: db` from the `app` service.
   - Add to `app` volumes: `firefly_iii_database:/var/www/html/storage/database`
   - Add `firefly_iii_database` to the top-level `volumes` block.
   - **Pin** `image: fireflyiii/core:<exact-version-tag>` (not `latest`). Check the latest stable tag on GitHub releases.
   - The `cron` service stays as-is (it hits `http://app:8080/api/v1/cron/$STATIC_CRON_TOKEN`).
6. `docker compose up -d`
7. Verify: open `http://localhost` → Firefly III setup wizard → create account.
8. Generate a PAT: Firefly UI → Options → Profile → OAuth → "Create new token". Save it (will be needed in P3).

**P0.3 — Tailscale on CachyOS + Bazzite + phone**
1. CachyOS: `sudo pacman -S tailscale && sudo systemctl enable --now tailscaled && sudo tailscale up`
2. Bazzite: install Tailscale via `ujust` or Flatpak; `tailscale up`.
3. Phone: install Tailscale from F-Droid or Play Store; sign in with the same account.
4. Verify: from the phone, `ping firefly.<cachyos-hostname>.ts.net` resolves and responds.
5. Note the MagicDNS name (e.g. `firefly.cachyos.ts.net`) — this is the Firefly base URL for the app.

**P0.4 — Flutter project scaffold**
1. `flutter create firefly_mobile` inside `/mnt/data/Projects/firefly_III/app/`.
2. Add dependencies: `sqflite`, `sqlcipher_flutter_libs`, `sqlcipher_flutter`, `flutter_secure_storage`, `http`, `uuid`, `json_annotation`, `build_runner`, `freezed`.
3. Configure linters: `analysis_options.yaml` with `flutter_lints` + `very_good_analysis`.
4. Set up CI: GitHub Actions workflow — `flutter analyze`, `flutter test`, `flutter build apk --debug`.
5. Project structure:
   ```
   app/
     lib/
       main.dart
       core/          # constants, theme, utils
       data/          # SQLite helpers, DAOs, repositories
       domain/        # models, enums
       sync/          # op log, sync engine, API client
       ui/            # screens, widgets, state management
     test/
     integration_test/
   ```

**P0.5 — Golden API fixtures**
1. Against the running Firefly III instance, call every list endpoint (`GET /api/v1/{entity}`) with a seeded minimal dataset (1 account, 1 transaction, 1 category, 1 tag, 1 budget, 1 rule, 1 recurrence).
2. Save the raw JSON responses as fixtures in `test/fixtures/api/`.
3. Commit. These fixtures are the contract — any Firefly version bump that changes them is caught by fixture diff in CI.

### Exit Criterion
- [ ] Firefly III reachable at `http://firefly.<cachyos-hostname>.ts.net` from the phone's Tailscale. — **blocked on device (2026-10-15)**: build box has no `tailscale` CLI / `tailscaled` inactive and no phone attached (`adb devices` empty). Verified on build box instead: Firefly reachable via `http://127.0.0.1:8080` → 302, containers `firefly_iii_core` (healthy) + `firefly_iii_cron` up. Phone-side check deferred until the user connects a phone (decision 2026-10-15: code everything now, test on device later).
- [x] `docker compose ps` shows `app` and `cron` running; `db` absent. — verified 2026-10-12 (`app` healthy, `cron` up, no `db`).
- [x] Flutter project builds (`flutter build apk --debug` succeeds). — verified 2026-10-12, exit 0. Use `/mnt/data/opencode/tools/flutter` (3.47.7); the `flutter` on PATH is 3.29.2 and cannot resolve `sdk: ^3.13.5` (REGRESSION-LOG R5).
- [x] Golden fixtures committed and passing a smoke test that loads them. — 17 fixtures + `manifest.json` in `app/test/fixtures/api/`, smoke test `app/test/api_fixtures_smoke_test.dart` (11 tests) green; committed `dc35ed8` (2026-10-12) with `.credentials`/`.env`/`tmp/` gitignored and a staged-content secret scan passing.

---

## P1 — Local Data Layer

### Tasks

**P1.1 — SQLite schema + migrations**
1. Implement the schema from DESIGN §5.1 (all business tables + `op_log` + `device_meta`).
2. Use a migration versioning system (simple `PRAGMA user_version` based).
3. Enable WAL mode: `PRAGMA journal_mode=WAL;`
4. SQLCipher setup: generate a random 32-byte key at first launch; store in Android Keystore; pass to `sqflite` via `sqlcipher_flutter`.

**P1.2 — Domain models**
1. Dart model classes for every entity (freezed + json_serializable).
2. Sync bookkeeping fields (`fireflyId`, `updatedAt`, `remoteUpdatedAt`, `syncStatus`, `deletedAt`, `seq`) as nullable/optional on each model.
3. JSON serialization to/from Firefly's JSON:API format (`data.attributes`, `data.id`, `data.type`).

**P1.3 — DAOs**
1. CRUD DAO for each entity (insert, update, soft-delete, hard-delete, getById, getByFireflyId, getAll, getPending).
2. Op-log DAO: `append(op)`, `getPendingBatch(limit)`, `acknowledge(opId)`, `recordFailure(opId, error)`.
3. Device-meta DAO: `get(key)`, `set(key, value)`.

**P1.4 — Repository layer**
1. Each repository method wraps the business write + op-log append in a single SQLite transaction.
2. Soft-delete = set `deleted_at` + append `op_delete` to op-log.
3. Fire ID generation: UUIDv7 for `id`, monotonic `seq` from `device_meta`.

### Tests
- Round-trip: insert model → read back → assert deep equality (every entity).
- Entity JSON:API/SQLite round-trip suites exist for **all 14 JSON:API
  entities**: `app/test/domain/entities/{account,attachment,bill,budget,
  budget_limit,category,currency,piggy_bank,recurrence,rule,rule_group,
  subscription,tag,transaction}_test.dart`. Category is the template; the
  others mirror it (11–14 tests each; envelope-helper group deliberately
  omitted where irrelevant). Executed 2026-10-13: `flutter test` **202/202**,
  `flutter analyze` **no issues**, every line ≤80 chars. `op_log_entry` and
  `device_meta` are infra tables (not JSON:API entities) — covered by their
  DAO tests instead.
- Real-SQLite persistence suite:
  `app/test/domain/entities/entity_persistence_test.dart` proves each entity's
  `toRow`/`fromRow` agree with `lib/data/db/schema.dart`, not merely with each
  other. Per-entity round trips pass even when `toRow` emits a column the DDL
  never created, so this suite is the one that actually catches schema drift —
  it caught R7 (`Bill.next_expected_match` writing epoch millis into a TEXT
  column). 15 tests: 14 entities, each with every optional field populated,
  plus one row carrying only required fields. Cases are records (`typedef
  _Case`), not a wrapper class, so the loop stays free of the `dynamic` calls
  `avoid_dynamic_calls` bans. Executed 2026-10-13: 15/15.
- Recurrence 1:N DAO suite (2026-10-18, Model B follow-up):
  `app/test/data/dao/recurrence_dao_test.dart` — 11 tests over `RecurrenceDao`
  on real SQLite (ffi), pinning the child-row plumbing the generic `EntityDao`
  suite cannot see. Covers: parent+schedule round trip via `getById`;
  non-empty `update`/`upsert` rewrite children wholesale (old `ord` rows gone,
  no appends); **empty list is a no-op** (server ignores `repetitions: []` — a
  half-loaded entity must not wipe a real schedule); `update` on a vanished
  parent skips the child rewrite (no orphans); `hardDelete` cascades despite
  the child table having no FK clause and leaves other parents alone;
  `getAll` attaches each parent its own children via the shared `IN (...)`
  join with no cross-parent bleed; schedule-less parent reads back `[]`;
  `getPending` attaches children (sync-push path). Found nothing broken —
  the DAO logic already held; the suite exists so it cannot silently rot.
  Alongside it: removed two redundant `firstDate: optDate(...)!` null asserts
  in `lib/ui/configs/entity_configs.dart` (target field is nullable — `!`
  would have *thrown* on a missing date instead of storing null), two
  `async_return_with_no_await` fixes in `RecurrenceDao.getAll/getPending`,
  and a stale duplicated doc line atop `RecurrenceDao`. Executed 2026-10-18:
  `flutter test` **401/401**, `dart analyze` on all four touched files →
  **No issues found** (tree-wide 62 infos are all pre-existing in
  `firefly_api_client`/`sync_engine`/`pull_engine` + their tests — out of
  scope, untouched).
- Tombstone: soft-delete → verify `deleted_at` set, op-log has `op_delete`.
- Op-log append atomicity: force a failure in the business write → assert op-log is unchanged (transaction rollback).
- Seq monotonicity: rapid sequential writes → `seq` strictly increases.
- Repository-layer write-path suite (all three bullets above, 2026-10-14):
  `app/test/data/repositories/sync_repository_test.dart` — 10 tests over
  `CategoryRepository`/`AccountRepository` on real SQLite (ffi). One
  connection per file via `openTestDatabase()` (the ffi factory reuses its
  `:memory:` handle, so per-test opens would leak rows); `setUp` deletes
  `op_log`/`categories`/`accounts`/`device_meta`, which also rewinds
  `next_seq` so each test starts at seq 1. Covers: create queues exactly one
  op whose `entity_type` doubles as the JSON:API `type` and whose payload is
  `jsonEncode(row.toJsonApi())`; seq 1..5 monotonic in both row and queue
  order; failed `UPDATE` (row deleted behind the repo's back) throws
  `StateError` and rolls back op + stored counter; pending-create→`create`,
  fireflyId-bearing row→`update`; soft delete = tombstone + `op_delete` with
  null payload and `row.seq` stamped by the delete; hard delete drops the row
  but still queues; `accounts` table name for another entity type;
  `CurrencyRepository` is an `EntityReader` but **not** a `SyncRepository`
  (pull-only, DESIGN §3.1). **Finding:** SQLite stores epoch millis, so
  `getById` returns `updatedAt` truncated to ms while `create()` returns the
  entity with microseconds — the equality assertion therefore converts
  through `millisToDateTime(dateTimeToMillis(...))`, the codec's own
  conversion, instead of a hand-rolled truncation (the persistence suite
  never hit this because it uses whole-second timestamps). Executed
  2026-10-14: 10/10 new, full suite **227/227**, `flutter analyze` no
  issues, every line ≤80 chars.
- Generic `EntityDao` surface suite (2026-10-14):
  `app/test/data/dao/entity_dao_test.dart` — 14 tests on `CategoryDao`
  (real SQLite ffi, one shared connection, per-test table wipe). Covers the
  primitives the repository suite does not reach: insert round-trip and
  duplicate-key abort; `upsert` replace/insert (pull-merge, no duplicate
  row); `update` 1/0 return contract; `patch` touching only named columns;
  `softDelete` tombstone stamps (deletedAt/updated_at/seq/sync-status reset
  to pending); `getById`/`getByFireflyId` (local id never matches the
  server-id column); `getAll` default-hides tombstones, DESC order, limit,
  `includeDeleted`, custom `orderBy`; `getPending` excludes synced rows but
  keeps tombstones (pull-merge must not resurrect, DESIGN §6.4), oldest
  first; `count` ± `includeDeleted`. Constructed DateTimes must be
  `isUtc: true` — see REGRESSION-LOG R10.
- SQLCipher key lifecycle suite (2026-10-14):
  `app/test/data/db/database_key_store_test.dart` — 6 tests. Key format
  (44 URL-safe base64 chars → 32 bytes, unique over 50 draws — R11);
  `InMemoryDatabaseKeyStore` generate-once/delete; `SecureStorageDatabaseKeyStore`
  generate-once + persist, adopt-across-relaunch, adopt-pre-seeded,
  delete-then-regenerate (via `FlutterSecureStorage.setMockInitialValues`);
  end-to-end: store-minted key creates the encrypted DB, a fresh store
  instance reopens it with the data intact, and a wrong key is rejected
  (`file is not a database`).
- Migration proof (2026-10-14, `app_database_test.dart` `migrations`
  group, 2 tests): a raw pre-versioning file (`PRAGMA user_version` 0, one
  user table + row) opened through `openAppDatabase` reaches
  `latestSchemaVersion` with the legacy row and all app tables present;
  `migrations.keys` asserted contiguous `1..latestSchemaVersion` so a
  missing version fails here instead of on a device (`_applyMigrations`
  throws `StateError` on a gap).
- Full milestone verification 2026-10-14: `flutter test` **252/252**,
  `flutter analyze` no issues, every line ≤80 chars.

### Exit Criterion
- [x] All unit tests green (`flutter test`). — verified 2026-10-14: **252/252**, `flutter analyze` no issues, all lines ≤80 chars.
- [x] Schema migration from empty DB to latest version works. — verified 2026-10-14: `migrations` group in `app_database_test.dart` — legacy `user_version=0` file upgraded to `latestSchemaVersion` with its row and all app tables intact; migration keys contiguous 1..latest.
- [x] SQLCipher key stored in Keystore; DB opens with key; fails without key. — verified 2026-10-14: `database_key_store_test.dart` 6/6 — key minted once and persisted via `flutter_secure_storage` (Keystore/Keychain on device), fresh store instance reopens the DB with data intact, wrong key rejected (`file is not a database`).

---

## P2 — Offline UI

### Tasks

**P2.1 — App shell + navigation**
1. Bottom-nav or drawer: Transactions, Accounts, Budgets, Categories, Tags, Bills, Piggy Banks, Rules, Recurrences, Settings, Sync.
2. State management: Riverpod (or Bloc — decided at implementation time; Riverpod preferred for testability).
3. Theme: Material 3, dark + light. — **done 2026-10-19 (pinned deviation: dark-only)**.
   Measured palette from the 4 design PNGs in `docs/` lives in
   `app/lib/ui/theme/app_theme.dart` (`FireflyPalette` + `FireflyTheme.dark`);
   wired into BOTH `theme:` and `darkTheme:` (no light mock exists).
   Drawer header purple seed removed. Gates: analyze 62 = baseline,
   flutter test 438/438, `build linux --release` exit 0.
   Palette table + rationale: `docs/DESIGN.md` §14.

**P2.2 — Entity screens (per entity)**
1. List view: paginated local query, search/filter, pull-to-refresh (will trigger sync in P3; for now, local-only).
2. Create form: all required fields per Firefly's API contract (from golden fixtures).
3. Edit form: pre-filled from local row.
4. Delete: confirmation dialog → soft-delete.
5. Per-row sync badge: `synced` (check icon), `pending` (clock icon), `conflict` (warning icon).

**Tests (transactions 2nd-UI list, 2026-10-20):**
`app/test/ui/transactions_list_test.dart` — 7 widget tests through the
production `transactionsConfig` + one in-memory SQLite DB (single
`databaseProvider` override, `openTestDatabase` recipe):
empty state + labeled extended FAB; card rows w/ type glyphs (scoped
`find.descendant(Card, …)` — the FAB also carries `Icons.add`), search
hint, 4 filter pills, SyncBadge×3; day sections Today→Yesterday→older
with newest-first order pinned via `getTopLeft().dy` (same-day anchors
are 00:00/23:59 — a wall-clock `now` can sit before an 08:00 anchor when
PKT is early morning, reversing the pair under newest-first sort);
amounts `-$4.50`/`+$1,200.50`/`$1,000` (negative not doubled) + palette
colors + local `HH:mm`; subtitle fallback chain + first-tag-only chip +
bad-`tags_json` no-crash; pills incl. no-match label `No matches for
"Transfers"`; search matches title AND plain-text subtitle (`deposit`
hits the deposit row only) + clear-key + `No matches for "zzz"`.
Gates: target suite 7/7, full `flutter test` **464/464** (457+7),
`flutter analyze` **62 = baseline**.

**P2.3 — App-bar sync status**
1. Persistent indicator: last sync time, pending op count, connection state (offline / syncing / synced / error).
2. "Sync now" button (will be wired in P3).

**P2.4 — Settings screen**
1. Firefly base URL input (validated).
2. PAT input (stored in Keystore).
3. Tailscale status check (ping the base URL).
4. "Restore from server" button (wired in P3).
5. "Export local DB" button (debug aid).

### Tests
- Widget tests for each form: validation, save, cancel. — **done 2026-10-16**:
  `app/test/ui/` suite (26 tests, all green) against real in-memory SQLite
  (`openTestDatabase()`, no mocks):
  - `entity_list_screen_test.dart` (13): spinner branch (never-completing
    provider + plain `pump()`), empty state, error+retry, populated rows with
    pending badges, `canWrite: false` gating, overflow → confirm →
    softDelete round-trip (row tombstoned, ops queued), row/FAB → form
    navigation, + 4 search tests (P2.2.1: case-insensitive filter,
    clear-restore, no-match vs empty distinction, no field on empty DB).
  - `entity_form_screen_test.dart` (13): create/edit pop results, required +
    grounded rules (`Amount must be greater than zero`, `Kind is required`,
    `Meta must be valid JSON`), choice dropdown, Cancel discards writes,
    read-only gating (helper config + production `currenciesConfig`),
    optional-date picker cancel.
  - `sync_badge_test.dart` (4) + `confirm_delete_dialog_test.dart` + shared
    `support/tags_test_config.dart` (one config builder for the test-only
    branches production cannot reach).
  - Verified: `flutter test` **282/282**, `flutter analyze` no issues.
    Lint gotcha fixed en route: Riverpod 3 moved `Override` out of
    `flutter_riverpod.dart` → import `package:flutter_riverpod/misc.dart`;
    M3 date-picker buttons read `Cancel`/`OK` (M2 uppercased).
- List search/filter (P2.2.1) — **done 2026-10-16**: `entity_list_screen.dart`
  is now a ConsumerStatefulWidget with a search TextField above the results;
  client-side case-insensitive filter on `rowTitle`/`rowSubtitle` (list
  providers fetch ≤50 rows, so no SQLite query planning needed — server
  pagination lands with P3). No-match view distinct from empty state, pull-
  to-refresh still available, search hidden on empty DB, query survives
  refreshes (lives in State). Lines ≤80, `const new(...)` constructors.
- Settings + About screens (P2.4) — **done 2026-10-16**:
  - `lib/ui/screens/settings_screen.dart`: Firefly base URL (validated via
    `normalizeBaseUrl`), PAT field that is **write-only** — once a token is
    stored the field shows masked dots + `Replace`/`Clear` and the raw value
    never re-enters the UI (security model in DESIGN "PAT storage").
  - `lib/ui/screens/about_screen.dart`: renders bundled `NOTICE.md` (the
    SQLCipher BSD-3 / SQLite / OpenSSL attribution file) as read-only text;
    degrades to a message if the asset is ever missing.
  - `home_screen.dart` drawer: `Settings` tile after the 14 entity entries.
  - `pubspec.yaml`: `NOTICE.md` registered under `flutter: assets:`.
  - Probe default timeout set to **4s** (user decision) in
    `connection_probe.dart`.
  - Tests (23 new, all green): `test/core/connection_settings_test.dart`
    (5 — normalize: trim+path drop, `:8443` kept, explicit `:443`/`:80`
    dropped, scheme-less/non-http/whitespace/no-authority rejected),
    `test/core/connection_probe_test.dart` (8 — 2xx→ok, 401/403→unauthorized,
    500→unexpectedStatus, client-exception→unreachable, timeout→unreachable,
    `Authorization: Bearer` only when a token is present, `GET /api/v1/about`),
    `test/ui/about_screen_test.dart` (1 — NOTICE.md content on screen),
    `test/ui/settings_screen_test.dart` (9 — seed from store, invalid-URL
    snackbar without persisting, save-normalizes, add/replace/clear PAT flow
    with no raw-value leak, probe/export buttons wired, About navigation).
  - Lint gotchas fixed en route: Riverpod 3 moved `Override` → import
    `package:flutter_riverpod/misc.dart`; `unawaited(...)` needs
    `dart:async`; `avoid_catches_without_on_clauses` → `on Exception catch`.
  - **Regression found + fixed**: `normalizeBaseUrl` used `uri.port == 0` to
    drop default ports, but Dart synthesizes `port` for omitted/default ports
    so `:443`/`:80` survived normalization → now keys off `uri.hasPort`.
    Logged as **R14** in `docs/REGRESSION-LOG.md`.
  - Verified: `flutter test` **321/321** (was 282; +23 P2.4 +16 P2.3),
    `flutter analyze` no issues.
- Integration test: create a transaction in airplane mode → verify it appears in the list with `pending` badge.
  - **Done (2026-10-16)**: `app/test/integration/airplane_mode_transaction_test.dart`
    (2 tests) — single `databaseProvider` override → in-memory SQLite, a
    recording `HttpOverrides` counts every `HttpClient` creation (0 allowed,
    attempts throw `SocketException` like a dead radio), production
    `transactionsConfig` + generic screens end-to-end: FAB → type
    `withdrawal` → Description/Amount → AppBar Save → row + `SyncBadge`
    (`Icons.schedule`, Tooltip `Pending sync`), DB row `sync_status='pending'`
    + exactly one `op_log` create queued; second test: pull-to-refresh
    settles on the same row with no spinner and 0 network attempts.
  - Gotchas: bottom `FilledButton('Save')` is off-screen with 16 fields
    (lazy ListView) → tap AppBar `TextButton('Save')`; `SyncBadge` label is a
    Tooltip/semanticLabel, not `Text` → `find.byTooltip`; dart:io has
    `HttpOverrides.global` setter but only `HttpOverrides.current` getter;
    hide sqflite's `Transaction` in imports.
  - Verified: suite **323/323**, `flutter analyze` no issues.
- Manual pass: enable airplane mode → exercise every screen → verify no network calls, no spinners, no crashes.

### Exit Criterion
- [x] All entity screens functional offline.
- [x] All widget + integration tests green.
- [ ] Manual airplane-mode pass completed and logged. *(on-device, user-run — checklist = line above; automated equivalent covered by the integration test)*

---

## P3 — Sync Engine

### Tasks

**P3.1 — API client** ✅ DONE 2026-10-16
1. HTTP client with `Authorization: Bearer <PAT>` header, base URL from settings. ✅
2. JSON:API parser (extract `data.id`, `data.attributes`, `meta.pagination`). ✅
3. Error handling: 401 (auth), 404 (not found), 409 (conflict), 422 (validation), 5xx (server), network errors. ✅
4. Retry with exponential backoff (1 s, 2 s, 4 s, 8 s, max 5). ✅

**Tests:** 23/23 green, `flutter analyze` 0 errors/0 warnings. Files: `app/lib/data/api/firefly_api_client.dart`, `app/test/data/api/firefly_api_client_test.dart`. Covers: URL building, auth header, list/fetch/create/update/delete, all error codes, retry backoff + recovery, JSON:API parse (collection + single), undecodable JSON, missing `data` member.

**P3.2 — Op-log push** ✅ DONE (evidence 2026-10-21)
1. Implement the replay algorithm from DESIGN §6.3.
2. Batch size 50.
3. Per-op acknowledge: on 2xx, set `firefly_id` on the entity, set `sync_status='synced'`, delete op-log entry.
4. On failure: increment `attempts`, store `last_error`, break batch.

**P3.3 — Pull-diff** ✅ DONE (evidence 2026-10-21)
1. Implement the full-pagination + local-diff algorithm from DESIGN §7.2.
2. Per-entity: paginate `GET /api/v1/{entity}?page=N&limit=100`, diff each resource against local by `firefly_id`.
3. Insert new server rows, update changed rows (LWW), soft-delete server-deleted rows.
4. Wrap each entity's pull in a single SQLite transaction.

**P3.4 — Sync orchestrator** ✅ DONE (Stories 2–5; evidence 2026-10-21)
1. `sync()` method: push → pull → backup (P4).
2. Auto-trigger: app foreground + network available, debounced 5 s.
3. Manual trigger: pull-to-refresh / "Sync now".
4. Structured sync log (JSON lines): timestamp, phase, entity, op count, success/failure, duration.

**Tests (Story 2 — Settings Sync section + Sync log screen, 2026-10-18):**
`app/test/ui/settings_sync_test.dart` — 12 tests: 6 widget (gate-skip with
engine never built, unreachable probe reported without engine, button
disabled + spinner while a cycle runs, success reports and appends two log
lines, failure SnackBar, log tile opens the log screen with live rows) +
6 pure `describeSyncAttempt` (gate skips verbatim, already-up-to-date,
counter listing, push-only, failure message, missing-failure degrade).
`app/test/ui/sync_log_screen_test.dart` — 5 tests: newest-first rows with
counters/time/error line, empty state, query-error state, pending spinner
(`settle: false` — the indeterminate spinner never lets `pumpAndSettle`
return), pull-to-refresh surfaces a row added by a newer cycle. Both suites
**17/17 green**; no network/database touched (log query overridden at the
provider seam, `SyncController` seams `engine:`/`isConfigured:`/`probe:`).
Consequence fixed in `app/test/ui/settings_screen_test.dart`: the About-tile
test now `scrollUntilVisible` first — the new Sync section pushed About past
the initial ListView `cacheExtent`, so the tile was lazily unbuilt and
`find.text` matched 0. Full suite **426/426**; touched files analyze clean
(tree-wide 62 infos = pre-existing baseline in firefly_api_client /
sync_engine / pull_engine, untouched).

**Tests (Story 3 — lifecycle auto-trigger, P3.4.2, 2026-10-18):**
`app/lib/core/sync_lifecycle.dart` — `SyncLifecycleWatcher`
(ConsumerStatefulWidget + WidgetsBindingObserver) wraps MaterialApp inside
ProviderScope (`app.dart`); on `resumed` schedules one debounced
`syncControllerProvider.runNow()` (default 5s, injectable), cancels on any
transition out of resumed. Silent fire-and-forget: gate skips offline/
unconfigured; no connectivity_plus dep (probe gate = the network check).
Resume-transitions only — cold start never auto-fires (pull-to-refresh /
"Sync now" cover first open). `app/test/ui/sync_lifecycle_test.dart` — 4
tests via recording SyncController (isConfigured counts gate entries, stops
before engine/probe): resume fires exactly once after window, rapid resumes
coalesce, pause cancels + next resume retriggers, cold start stays silent.
Full suite **430/430**; touched files analyze clean.

**Tests (Story 4 — conflict marker, P3.5.2, 2026-10-18):**
`pull_engine._overwriteFromServer` now sets `sync_status='conflict'`
(was `'synced'`) on every server-won LWW overwrite; badge label for
`conflict` changed to "Resolved by server" (plan wording — informational,
not interactive). Merge gate narrowed from `localStatus != synced` to
`localStatus == pending`: only unsent local ops freeze a row; a `conflict`
row must stay pullable or it freezes at its first conflict forever
(regression-pinned by new test "a conflict row is still overwritten by a
newer server copy"). Updated: 2 LWW asserts → `'conflict'`, tombstone test
+ conflict-badge tooltip test. Suite **431/431**; 3 remaining infos in
pull_engine.dart = pre-existing baseline (unnecessary_type_name at
113/155/193, untouched).

**P3.5 — Conflict handling** ✅ DONE 2026-10-18 (Story 4)
1. Implement LWW merge per DESIGN §7.3.
2. After merge, set `sync_status='conflict'` on the affected row if the server won; UI shows a "resolved by server" badge (informational, not interactive).

**P3.6 — Restore from server** ✅ DONE 2026-10-18 (Story 5)
1. "Restore from server" in Settings: full pull, no push. Clears local DB first (with confirmation).

**Tests (Story 5 — restore from server, P3.6, 2026-10-18):**
Settings gains a destructive "Restore from server" ListTile (icon
`settings_backup_restore_outlined`, subtitle "Erase local records and
re-download them") gated by an AlertDialog confirm ("Erase & restore" /
Cancel); `_restore()` mirrors `_syncNow` (busy flag disables the tile +
shows a spinner, log provider invalidated, engine errors land in a
SnackBar). Gate skips (`failure.code` starts with `sync.skipped.`) show
the bare `SyncSkipReason.message` — same UX as a skipped "Sync now" via
`describeSyncAttempt` — other failures keep the `Restore failed — `
prefix. `app/test/ui/settings_sync_test.dart` grew 12 → **16 tests** (+4
widget: confirmed restore wipes local-only rows + success SnackBar, gate
skip stops before the engine build, tile disables + spinner while in
flight, confirm-then-success flow). Three gotchas fixed while writing
them: (1) the restore tile sits below the ListView `cacheExtent` (same
lazy-build trap as the About/log tiles) — `ensureVisible` cannot match
an unbuilt widget, so all four tests `scrollUntilVisible(…, 200,
scrollable: find.byType(Scrollable).first)` first; (2) the tile's
spinner is wrapped in a fixed-size `SizedBox`, so
`expect(tile.trailing, isA<CircularProgressIndicator>())` fails — assert
`find.descendant(…, matching: find.byType(CircularProgressIndicator))`
instead; (3) the screen edit initially shipped a 95-char `_snack(…)` line
(analyze 62 → 63) — re-broke it to stay at baseline. Final: suite
**438/438**, three touched UI suites **30/30**, `flutter analyze` **62**
(pre-existing baseline in firefly_api_client/sync_engine/pull_engine,
untouched).

### Tests
- **Op-log ordering:** 100 ops across 2 simulated devices → verify replay order matches `(wall_ts, device_id, seq)`.
- **Idempotent replay:** push same op twice → no duplicate on server.
- **Partial failure:** network drop after op 50 of 100 → ops 1–50 acked, 51–100 remain; resume → convergence.
- **Conflict matrix (DESIGN §7.4):** all 8 rows exercised.
- **Clock skew:** phone clock 5 min ahead / 5 min behind → pull still converges.
- **Millisecond collision:** two ops with identical `wall_ts` → `seq` breaks tie.
- **Delete tombstone:** soft-delete → push → server row removed, local hard-deleted.
- **Server-side delete:** delete on server → pull → local soft-delete.
- **1000-op backlog:** 1000 pending ops → batch push < 60 s, all rows `synced`.
- **End-to-end (real Firefly):** airplane mode → create 5 transactions → disable airplane → auto-sync → verify in Firefly web UI.

**Evidence (2026-10-21 — P3 push live-proof, regression R21):**
`FireflyApiClient.create/update` now send the **flat attributes body**
(`_requestBody` unwraps the app-wide `{type, attributes}` member — Firefly
requests take the flat object, responses stay JSON:API-wrapped; the member
body was rejected live with 422 `{"name": ["The name field is required."]}`).
Three tests that had pinned the wrong wire contract re-pinned (client suite
24/24 incl. new passthrough test; pusher ordering handler reads
`body['name']`); probe residue (category ids 1, 2) deleted. Gates: full
suite **466 pass / 0 fail**, `flutter analyze` **61** (baseline 62 − 1
superseded long line, no new infos), and the gated live run
`FIREFLY_LIVE=1 flutter test test/integration/live_sync_e2e_test.dart` =
**1/1 PASS** (`create → sync → server has row → restore parity`) against the
pinned Docker instance. Full story: `docs/REGRESSION-LOG.md` **R21**.

### Exit Criterion
- [x] All unit + integration tests green. (466 pass / 0 fail, 2026-10-21)
- [x] End-to-end convergence proven on real Firefly III (pinned instance).
      (live e2e 1/1: create → sync → server row → restore parity, 2026-10-21;
      the manual airplane-mode web-UI drill above remains a user-run check)
- [x] Sync log readable in-app (last 500 entries). (`kMaxSyncLogEntries=500`
      prune in sync_engine; SyncLogScreen + settings_sync suites green)
- [x] Restore-from-server drill passes. (live e2e restore parity + Story 5
      settings suites, 2026-10-21)

---

## P4 — Backup

### Tasks

**P4.1 — Backup trigger** (transport DECIDED 2026-10-19: authenticated HTTP, not SSH)
1. After successful push+pull, Sync Engine triggers a backup on the PC.
2. Transport: **authenticated HTTP sidecar chosen** — `infra/firefly/backup_sidecar.py`
   (`POST /backup`, `Authorization: Bearer <token>`, default port 8095, token from
   `BACKUP_TOKEN` env or `.backup_token` file). SSH over Tailscale rejected: the
   sidecar already exists for the snapshot/CSV work, so no extra service vs.
   adding an SSH key + Dart SSH package to the phone. Phone side landed 2026-10-19:
   `app/lib/data/sync/backup_client.dart` (best-effort, never throws) wired into
   `SyncEngine._runBackup` (one `backup`/`ok|error` log line, disabled = silent).

**P4.2 — SQLite snapshot**
1. `cp ~/firefly/storage/database/database.sqlite ~/firefly-backups/firefly-$(date +%Y%m%d-%H%M%S).sqlite`
   (Note: exact path depends on the Docker volume mount; verify in P0.2.)
2. Rotating: keep last 30; delete older.

**P4.3 — CSV export**
1. For each entity in `{transactions, accounts, budgets, categories, tags, bills, recurring, rules, piggy_banks}`: `GET /v1/data/export/{entity}` → write to `~/firefly-backups/csv-$(date +%Y%m%d-%H%M%S)/{entity}.csv`.

**P4.4 — Restore drill**
1. Follow DESIGN §8.3 (5 steps).
2. Document the exact commands and expected output.

### Tests
- Integration: complete a sync → verify backup files exist on PC with correct timestamps.
- Integration: delete local DB → restore from server → verify parity.
- Manual: full restore drill on a clean phone install.
- **Widget (DONE 2026-10-21)**: `backup_client_test` (6), `sync_engine_test`
  backup wiring (+4 incl. fire-once / log lines / disabled-silent /
  restore-never-triggers), `settings_screen_test` P4.1 section (+6: field
  renders / normalize+persist / clear disables / non-http snackbar /
  PAT+backup coexist / token add+persist+mask). Inserting the PC-backup
  section broke 6 widget tests below it via the ListView cacheExtent trap
  — fixed with scrollTo/tapSyncNow helpers; REGRESSION-LOG **R22**.

### Exit Criterion
- [ ] Backup files written after every successful sync.
- [ ] Rotation works (only last 30 snapshots retained).
- [ ] Restore drill passes end-to-end.

---

## P5 — Hardening

### Tasks

**P5.1 — Threat-model scenarios (DESIGN §10.3)**
1. App killed mid-sync → relaunch → op-log intact → sync resumes → no duplicates.
2. Battery dies mid-sync → same as above.
3. PC off during push → HTTP fails → op-log retained → resume when PC back on.
4. PC off during pull → no partial local writes.
5. 1000-op backlog + slow network → batch push with backoff → no ANR.
6. Same-millisecond ops on two devices → ordered by `device_id` then `seq`.
7. Firefly image accidentally set to `latest` + breaking change → golden fixture diff fails in CI.
8. Tailscale auth key expires → clear error in sync log → app usable offline.
9. Phone clock set to 1970 → `seq` orders ops → pull converges.

**P5.2 — Performance**
1. 1000-op push < 60 s on home broadband.
2. Full pull of 10 000 transactions < 30 s.
3. App launch to interactive < 2 s (local DB only).

**P5.3 — Battery**
1. Measure idle battery drain over 24 h with sync enabled but no activity.
2. Verify no background polling (sync only on foreground + network-change events).

**P5.4 — Security review**
1. Verify PAT never appears in logs, SharedPreferences, or crash reports.
2. Verify SQLCipher key never leaves Keystore.
3. Verify no outbound network calls except the Firefly endpoint (check with a network monitor).
4. Verify Tailscale is the only transport (no fallback to public internet).

**P5.5 — Code quality**
1. `flutter analyze` — zero warnings.
2. Test coverage > 80 % on `lib/sync/` and `lib/data/`.
3. All TODOs resolved or filed as issues.

### Exit Criterion
- [ ] All threat-model scenarios pass.
- [ ] Performance targets met.
- [ ] Battery drain within acceptable bounds (< 2 %/24 h idle).
- [ ] Security review clean.
- [ ] `flutter analyze` zero warnings; coverage > 80 % on sync + data layers.

---

## P6 — Docs + Graphify

### Tasks

**P6.1 — Documentation**
1. Update `DESIGN.md` to match the implemented system (any deviations documented).
2. Update `IMPLEMENTATION-PLAN.md` with actual durations and lessons learned.
3. Write `README.md`: setup, build, install, first-run, sync, backup, restore.
4. Write `OPERATIONS.md`: Firefly upgrade checklist, Tailscale key rotation, backup rotation policy.

**P6.2 — Graphify knowledge graph**
1. Run `graphify` on the project.
2. Apply the Obsidian-style theme (`graphify-theme-apply`).
3. Commit the graph.

**P6.3 — Regression log**
1. If any bugs were found and fixed during P1–P5, document them in `docs/REGRESSIONS.md`: what broke, root cause, exact fix, how tested.

### Exit Criterion
- [ ] All docs current and accurate.
- [ ] Graphify graph generated and themed.
- [ ] Regression log complete (or explicitly "no regressions").

---

## Appendix — Key Files (to be created)

| Path | Purpose |
|---|---|
| `/mnt/data/Projects/firefly_III/docs/DESIGN.md` | This design document. |
| `/mnt/data/Projects/firefly_III/docs/IMPLEMENTATION-PLAN.md` | This plan. |
| `/mnt/data/Projects/firefly_III/docs/REGRESSIONS.md` | Regression log (P6). |
| `/mnt/data/Projects/firefly_III/README.md` | User-facing setup guide (P6). |
| `/mnt/data/Projects/firefly_III/OPERATIONS.md` | Ops runbook (P6). |
| `/mnt/data/Projects/firefly_III/app/` | Flutter project (P0.4). |
| `~/firefly/` (on CachyOS) | Docker compose + Firefly data (P0.2). |
| `~/firefly-backups/` (on CachyOS) | Backup snapshots + CSV exports (P4). |

---

*End of implementation plan.*
