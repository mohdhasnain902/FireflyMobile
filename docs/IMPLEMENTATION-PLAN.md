# Firefly III Mobile — Implementation Plan

**Version:** 1.0
**Status:** Draft for review
**Date:** 2026-10-11
**Depends on:** `docs/DESIGN.md` v1.0

---

## Overview

Seven phases (P0–P6), each with a hard exit criterion. No phase starts until the previous phase's exit criterion is met. Every phase includes automated tests and a manual verification pass.

| Phase | Name | Duration (est.) | Exit Criterion |
|---|---|---|---|
| P0 | Foundation | 2–3 days | Firefly III live on CachyOS via Docker (pinned, SQLite, Tailscale); Flutter scaffold builds; golden API fixtures committed. |
| P1 | Local data layer | 3–4 days | SQLite schema + all DAOs; unit tests green (round-trip, tombstones, op-log append atomicity). |
| P2 | Offline UI | 5–7 days | Every entity's list + create/edit/delete screens work in airplane mode with pending badges. Manual airplane-mode pass completed. |
| P3 | Sync engine | 5–7 days | Op-log push + pull-diff + LWW merge; conflict-matrix tests green; end-to-end offline→reconnect convergence proven on real Firefly. |
| P4 | Backup | 1–2 days | Snapshot-on-sync writes to PC; restore drill (5 steps) executed successfully. |
| P5 | Hardening | 3–4 days | All threat-model scenarios (DESIGN §10.3) pass; 1000-op backlog < 60 s; battery idle drain measured. |
| P6 | Docs + graphify | 1 day | Design doc + plan updated to match implementation; graphify knowledge graph generated. |

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
- [ ] Firefly III reachable at `http://firefly.<cachyos-hostname>.ts.net` from the phone's Tailscale.
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
3. Theme: Material 3, dark + light.

**P2.2 — Entity screens (per entity)**
1. List view: paginated local query, search/filter, pull-to-refresh (will trigger sync in P3; for now, local-only).
2. Create form: all required fields per Firefly's API contract (from golden fixtures).
3. Edit form: pre-filled from local row.
4. Delete: confirmation dialog → soft-delete.
5. Per-row sync badge: `synced` (check icon), `pending` (clock icon), `conflict` (warning icon).

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
- Widget tests for each form: validation, save, cancel.
- Integration test: create a transaction in airplane mode → verify it appears in the list with `pending` badge.
- Manual pass: enable airplane mode → exercise every screen → verify no network calls, no spinners, no crashes.

### Exit Criterion
- [ ] All entity screens functional offline.
- [ ] All widget + integration tests green.
- [ ] Manual airplane-mode pass completed and logged.

---

## P3 — Sync Engine

### Tasks

**P3.1 — API client**
1. HTTP client with `Authorization: Bearer <PAT>` header, base URL from settings.
2. JSON:API parser (extract `data.id`, `data.attributes`, `meta.pagination`).
3. Error handling: 401 (auth), 404 (not found), 409 (conflict), 422 (validation), 5xx (server), network errors.
4. Retry with exponential backoff (1 s, 2 s, 4 s, 8 s, max 5).

**P3.2 — Op-log push**
1. Implement the replay algorithm from DESIGN §6.3.
2. Batch size 50.
3. Per-op acknowledge: on 2xx, set `firefly_id` on the entity, set `sync_status='synced'`, delete op-log entry.
4. On failure: increment `attempts`, store `last_error`, break batch.

**P3.3 — Pull-diff**
1. Implement the full-pagination + local-diff algorithm from DESIGN §7.2.
2. Per-entity: paginate `GET /api/v1/{entity}?page=N&limit=100`, diff each resource against local by `firefly_id`.
3. Insert new server rows, update changed rows (LWW), soft-delete server-deleted rows.
4. Wrap each entity's pull in a single SQLite transaction.

**P3.4 — Sync orchestrator**
1. `sync()` method: push → pull → backup (P4).
2. Auto-trigger: app foreground + network available, debounced 5 s.
3. Manual trigger: pull-to-refresh / "Sync now".
4. Structured sync log (JSON lines): timestamp, phase, entity, op count, success/failure, duration.

**P3.5 — Conflict handling**
1. Implement LWW merge per DESIGN §7.3.
2. After merge, set `sync_status='conflict'` on the affected row if the server won; UI shows a "resolved by server" badge (informational, not interactive).

**P3.6 — Restore from server**
1. "Restore from server" in Settings: full pull, no push. Clears local DB first (with confirmation).

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

### Exit Criterion
- [ ] All unit + integration tests green.
- [ ] End-to-end convergence proven on real Firefly III (pinned instance).
- [ ] Sync log readable in-app (last 500 entries).
- [ ] Restore-from-server drill passes.

---

## P4 — Backup

### Tasks

**P4.1 — Backup trigger**
1. After successful push+pull, Sync Engine triggers a backup on the PC.
2. Transport: SSH over Tailscale (simplest — CachyOS has OpenSSH; phone uses a Dart SSH package) OR a tiny authenticated HTTP endpoint on the PC. Decision at implementation time; SSH preferred (no extra service to maintain).

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
