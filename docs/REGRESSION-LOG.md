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

## R6 — `Transaction` entity never compiled: missing `fireflyId`

**Symptom.** The new `test/domain/entities/transaction_test.dart` failed to load:
`lib/domain/entities/transaction.freezed.dart:241: Error: The non-abstract class
'_Transaction' is missing implementations ... SyncBookkeeping.fireflyId`.

**Root cause.** `Transaction` is the only entity whose factory constructor did not
declare `String? fireflyId`, while `with _$Transaction, SyncBookkeeping` requires
it (the mixin declares an abstract getter). Nothing had ever imported
`lib/domain/entities/transaction.dart`, so the breakage stayed invisible until the
first round-trip test did. Two contributing errors in the entity's own docs:
it claimed "the schema has no column for the group id", but
`syncBookkeepingColumns` (applied to `transactions` too — DESIGN §5.1 uses
transactions as its *example* table) includes `firefly_id TEXT`, and DESIGN §7
pull matching (`WHERE firefly_id = resource_id`) requires it. `toJsonApi`
therefore also emitted `id: null`, which would have broken re-pull row matching.

**Fix (followed the every-other-entity pattern exactly).**
- Constructor: added `String? fireflyId` (after the required params, so
  `always_put_required_named_parameters_first` holds).
- `fromJsonApi`: `fireflyId: jsonApiId(member)` — member `id` is the group id.
- `fromRow` / `toRow`: read / write the `firefly_id` column.
- `toJsonApi`: `id: fireflyId` instead of `id: null`.
- Doc comments corrected (group id *is* stored; DESIGN §5.1/§7 cited).
- Regenerated freezed (`dart run build_runner build`; if a plain build no-ops on
  stale cache, `dart run build_runner clean` first).

**Tested.** `flutter test` 202/202 (all 14 entity round-trip suites),
`flutter analyze` → *No issues found*.

---

## R7 — `Bill.next_expected_match` wrote epoch millis into a TEXT column

**Symptom.** The new `test/domain/entities/entity_persistence_test.dart` failed its
`Bill row survives a real SQLite round trip` case. The INSERT succeeded (SQLite
accepted the integer), but re-parsing the row threw rather than returning a `Bill`.

**Root cause.** Every date column in `lib/data/db/schema.dart` is TEXT and holds
ISO-8601 text — `next_expected_match TEXT` (schema.dart:189) is no exception, and
`opening_balance_date`, `start_date`, `target_date`, `recur_until` are all TEXT too.
`Bill.toRow` was writing `nextExpectedMatch?.millisecondsSinceEpoch`, an `int`.
SQLite's TEXT affinity coerces that integer to its decimal text form
(`"1793481600000"`), so the column never held a real integer; `Bill.fromRow` then
read it with an `as int?` cast, which throws a `TypeError` against that text.

The bug is the same class as R6: nothing exercised `Bill` against a real table
until the persistence suite did, and an entity-to-entity round trip cannot see it
because it never crosses the storage layer.

**Fix (matched the every-other-entity pattern).**
- `Bill.toRow`: `'next_expected_match': dateTimeToIso(nextExpectedMatch)`.
- `Bill.fromRow`: `isoToDateTime(row['next_expected_match'] as String?)`.
- The sibling fields on the same entity already used
  `isoJsonToDateTime` / `dateTimeToJson` for the JSON:API side, so only the
  SQLite side was wrong. `dateTimeToIso` / `isoToDateTime` are the helpers every
  other entity uses for row columns (`PiggyBank.target_date`, etc.).

**How to avoid repeating it.** A date/time column is TEXT and takes
`dateTimeToIso` on write and `isoToDateTime` on read. Never `millisecondsSinceEpoch`
in `toRow`, and never `as int?` in `fromRow`, for a column declared TEXT. When a
new column is added to `schema.dart`, pick the affinity that matches the helper
you intend to call.

**Tested.** `flutter test test/domain/entities/entity_persistence_test.dart` →
15/15 (14 entity round trips + the required-fields-only row), which includes the
failing-then-passing `Bill` case. Full `flutter test` → 217/217.
`flutter analyze` → *No issues found*.

---

## R8 — graphify extract refuses a fully cached corpus with "no LLM API key"

*(graphify toolchain, not app code — recorded because it blocks the documented
"cache-hit-only, no model calls" workflow.)*

**Symptom.** `graphify extract .` on a corpus whose 13 doc/image files are all
semantic-cache-ready exited 1:
`error: no LLM API key found (13 doc/paper/image file(s) need semantic extraction)`.

**Root cause.** `graphify/cli.py` enforces the backend/API-key gate
(`needs_llm = bool(semantic_files)`) **before** the semantic-cache read (which
happens later, after the AST pass). `semantic_files` is every changed doc/image
file — it is not pre-filtered against the cache. So a fully cached corpus still
requires a resolvable backend, even though zero model calls would be made.

**Fix.** Set a dummy key for the gate only:
`GEMINI_API_KEY=dummy graphify extract .`. The gate only checks key *presence*;
with 13/13 cache hits the extract path dispatches nothing (verified:
`semantic cache: 13 hit / 0 miss`, no HTTP attempted — a dummy key would 400 if
anything were sent). Community naming stays LLM-free via the labels-reuse branch
(`.graphify_labels.json` + `.sig`, validated per community against membership
signatures) or the hub-label fallback — both local.

**Tested.** Full pipeline: extract (dummy key) → 13 hit / 0 miss → graph.json
865 nodes / 1383 edges / 68 communities → `cluster-only` (56 communities renamed
by hub, 0 placeholders) → `graphify-theme-apply` OK. Zero model calls throughout.

---

## R9 — "unverified semantic shrink" on docs/DESIGN.md (3 → 2) was a replaced legacy id

**Symptom.** Extract wrote the graph but warned:
`semantic extraction is incomplete: unverified semantic shrink detected for
'docs/DESIGN.md' (3 -> 2 nodes)` (#3203 fail-closed guard).

**Root cause.** Yesterday's graph carried a third DESIGN-attributed node — the
old-format short id `docs_design`, from before the full-path stem convention.
The cached entry holds the canonical two (`src_docs_design`, `src_auth_session`).
`build_merge` drops prior semantic nodes of any file re-extracted this run, so
the legacy node was replaced by the entry's two; the guard counts prior (3) vs
fresh (2) and warns. The stale node had no inbound edges and no cache references.

**Fix.** None needed — replacement was correct. Verified on the written graph:
0 dangling edges; no node, edge, or cache entry references `docs_design`; every
DESIGN link targets the live `src_docs_design` id.

**How to avoid repeating it.** Cross-file edge targets must be node ids taken
from the real cache entry of the target file (full-path stems), never
short-form guesses. After fixing a legacy id, re-run extract so the guard's
counts realign. Note: `extract` and `cluster-only` both back up to the same
dated folder (`graphify-out/YYYY-MM-DD/`); a later command overwrites the
earlier pre-run snapshot — copy it aside first if you need it.

---

## R10 — Entity `==` fails when the test builds local `DateTime`, the codec decodes UTC

**Symptom.** Seven of the fourteen new `entity_dao_test.dart` assertions
failed with values that looked identical, e.g.
`updatedAt: 1970-01-01 05:00:01.000` (expected) vs
`1970-01-01 00:00:01.000Z` (actual) — same epoch instant, still `!=`.

**Root cause.** `sync_bookkeeping.dart:60` `millisToDateTime` decodes rows
with `DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)`, so every
entity read back from SQLite carries `isUtc == true`. Dart's `DateTime.==`
compares the epoch **and** the `isUtc` flag, so a test helper that builds
`DateTime.fromMillisecondsSinceEpoch(millis)` (local time, host is UTC+5)
produces an object that is never `==` to the decoded row. Storage was never
affected — `dateTimeToMillis` stores the same epoch either way; only
object-level equality breaks.

**Fix.** Test helper and the two `softDelete` assertions now build
`DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)`, mirroring the
decoder; the helper's doc comment states the rule. No production code
changed. Covered by the previously failing assertions themselves
(round-trip, upsert ×2, patch, softDelete ×2, getByFireflyId).

**How to avoid repeating it.** Any test comparing a decoded entity with a
constructed one must build DateTimes with `isUtc: true`. Alternative used
by the repository suite: convert through the codec,
`millisToDateTime(dateTimeToMillis(dt))`, so the expected value is produced
by the same function the code under test uses.

---

## R11 — `generateDatabaseKey` doc said "43 chars"; the encoder pads to 44

**Symptom.** Writing the key-format assertion for
`database_key_store_test.dart`, the doc comment on
`lib/data/db/database_key_store.dart:88` claimed the key is "43 chars".

**Root cause.** Dart's `base64Url.encode` always pads to a multiple of
four (Dart SDK `convert/base64.dart`), so 32 bytes encode to 44 chars —
43 payload chars plus one trailing `=`. Verified empirically with a
`dart` probe: `len=44`, decodes to 32 bytes, matches `^[A-Za-z0-9_-]{43}=$`.

**Fix.** Comment corrected to "44 chars: 43 payload chars plus one `=`
padding character". No code depended on 43 (`grep \b43\b` matched only the
comment). The test now pins `hasLength(44)` + regex + `base64Url.decode`
length, so a future encoder/alphabet change fails loudly.

**How to avoid repeating it.** Assert key material in tests rather than
trusting prose; Dart's base64 codecs pad, while its decoder accepts
unpadded input.

---

## R12 — Editing a graphified doc pruned its rich cache entry; the thin
re-extraction shrank the graph and the write was (correctly) refused

**Symptom.** After ticking the P1 checkboxes in `docs/IMPLEMENTATION-PLAN.md`
and appending R10/R11 here, `graphify extract .` refused to write: 862 nodes
against the guarded floor of 867 (unverified semantic shrink, same guard as
R9).

**Root cause.** Two mechanisms stacked:

1. Cache entries are keyed by the SHA256 of the file's content, and every
   extract run calls `prune_semantic_cache`, which deletes entries whose hash
   is no longer live (by design — fixes the unbounded-orphan problem #1527).
   Editing either doc therefore deleted the rich entries (plan 9 nodes,
   log 11 nodes) the graph was built from.
2. Re-extraction under-extracted deterministically: the plan came back with
   4 nodes instead of 9, this log with 1 instead of 11 — identical across two
   retries with the real Gemini key, so not a transient glitch. Both docs go
   through one semantic chunk and the response came back trimmed.

The net loss (862 < 867) is what tripped the guard — correct behavior: it
protected the curated graph from a partial rebuild.

**Fix.** Rehydrated both cache entries by hand from `graphify-out/graph.json`:
took the 20 doc nodes, the 17 plan edges (14 within-doc plus 3 cross-doc →
`src_docs_design` and the two golden-test nodes), the 10 log edges, and the
`implementation_roadmap_phases` hyperedge; stripped builder keys
(`_origin`, `community`, `community_name`, `norm_label`); overwrote the
current content-hash entries under
`graphify-out/cache/semantic/p5e80268fecd6/`. The next run reported
3 hit / 0 miss (no LLM involved) and rebuilt 877 nodes / 1407 links /
0 dangling / 71 communities — write accepted. This entry was then added to
this file and restored with the same procedure (R10–R12 section nodes
rehydrated as `docs_regression_log_md_r10/r11/r12`).

**How to avoid repeating it.** After editing any graphified doc expect its
cache entry to be pruned and re-extracted; compare the re-extracted node set
against `graphify-out/graph.json` before trusting the rebuild. If it came
back thin, restore the entry from graph.json (rehydration above) rather than
accepting a partial shrink — never let a rebuild drop below the prior node
count without verification.

---

## Open follow-up

- `hooks.user_defines.sqlite3.source: sqlcipher` is global. Confirm the bundled
  SQLCipher build is what we want on Android/iOS before release (licensing: SQLCipher
  CE is BSD-3; the build links OpenSSL on some platforms). If we ever need a custom
  build, see `sqlite3` package `doc/hook.md`.
