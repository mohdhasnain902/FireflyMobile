# Pull Engine Tests (P3.3, DESIGN §7.2–7.5)

**Date:** 2026-10-16 · **Task:** unit tests for `PullEngine` (Firefly → phone pull diff).

## What
`app/test/data/sync/pull_engine_test.dart` — 15 tests over the in-memory DB (`openTestDatabase()` from `test/data/db/app_database_test.dart`) + `MockClient`, covering the DESIGN §7.3 diff matrix and §7.4 tombstone pass.

## Cases
- unknown entity → `ValidationFailure`, zero HTTP
- empty collection + empty table → all-zero stats
- insert (server row absent locally) → INSERT as synced
- LWW: server newer → overwrite, keep local PK, refresh `remote_updated_at`
- LWW clears unpushed local tombstone
- unchanged (server not strictly newer) → `skippedUnchanged`, row untouched
- null local `remote_updated_at` counts as older
- null server `updated_at` never newer → local stands
- pending row never overwritten, never tombstoned
- tombstone: synced row absent from full response → `deleted_at` set
- tombstone skips already-tombstoned / pending / unpushed
- later-page failure → partial pull is NOT final, no tombstone pass
- multi-page pagination merged, tombstone once
- `budget_limits` walks nested `budgets/{id}/limits` per pushed budget
- `PullEntityStats` + `operator+` and `PullStats` getters aggregate

## How tested
`/mnt/data/opencode/tools/flutter/bin/flutter test` → **375/375 pass**.
`flutter analyze` on the new file → **No issues found** (after fixing: `Result` uses `isOk`/`valueOrNull`/`failureOrNull` — not `isSuccess`/`isFailure`; imported `failure.dart` for `ValidationFailure`; removed redundant `DateTime.utc(y, 1)`/`DateTime.utc(y, m, 1)` default args; removed duplicate import).

## Result
Pull-engine logic verified against the DESIGN diff matrix; suite green, analyzer clean.
