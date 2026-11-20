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

## R13 — `prefer_const_constructors` false-positive on `MaterialApp`/`Scaffold` in this SDK

**Symptom.** A widget test (`test/ui/sync_status_indicator_test.dart`) built
`MaterialApp(home: Scaffold(appBar: AppBar(title: SyncStatusIndicator())))`.
`flutter analyze` reported `prefer_const_constructors` at the `Scaffold(...)`
call, but wrapping the subtree in `const` produced a *hard compile error*
(`const_with_non_const`) — the lint demanded `const` that the compiler
rejects.

**Root cause.** In this Flutter SDK (3.47.7 / Dart 3.13.5, per the R5 SDK pin)
`MaterialApp` and `Scaffold` constructors are **not** const-constructible,
yet the `prefer_const_constructors` lint still fires on them. Proven with an
isolated probe — even a trivial `const MaterialApp(home: Scaffold(appBar:
AppBar(title: Text('x'))))` (no project widgets at all) errors with
`const_initialized_with_non_constant_value` + `const_with_non_const`, while
the non-const form of the same expression triggers
`prefer_const_constructors`. It is a genuine analyzer/SDK mismatch, not a bug
in the test. Do **not** chase a `const` that cannot exist.

**Fix (two independent edits were needed).**

1. *Where the ignore binds.* An `// ignore: <rule>` comment applies to the
   **next line only**. Placing it above `child: MaterialApp(` (the obvious
   call site) silenced nothing — the lint fires on the **`Scaffold(...)`**
   argument one level down (col 48 of that line). The ignore must sit
   immediately above the flagged line:
   ```dart
   child: MaterialApp(
     // ignore: prefer_const_constructors   ← binds to the Scaffold line
     home: Scaffold(appBar: AppBar(title: SyncStatusIndicator())),
   ),
   ```
   An ignore placed on a non-flagged line is itself reported as
   `unnecessary_ignore`, so a mis-placed ignore creates a *second* lint.

2. *Justify the suppression.* Because `analysis_options.yaml` enforces
   "failures are fixed, never suppressed project-wide", the per-line ignore is
   paired with a short comment naming the SDK false-positive, so the next
   reader knows it is intentional, not a lazy dodge.

**Also fixed while here (my own lint debt, not the SDK).** The two
`cascade_invocations` infos (`entity_form_screen.dart`, `entity_list_screen.dart`)
were caused by two consecutive `ref.invalidate(...)` calls on the same `ref`
after I wired the new `pendingOpsCountProvider` into P2.3. Merged each pair
into a single cascade (`ref ..invalidate(a) ..invalidate(b);`) with one
combined comment — satisfies the lint, keeps both invalidations.

**Tested.** `flutter analyze` → **0 issues** (was 5). `flutter test` →
**298/298** (was 282; +16 from the P2.3 sync-status unit + widget suites).

**How to avoid repeating it.** Before adding `const` to a MaterialApp/Scaffold
tree in this project, remember this SDK rejects it — the lint is wrong, not
the code. Use a **per-line** ignore (never project-wide, per the options
policy) placed on the **exact** flagged line, with a reason comment. A
mis-placed ignore surfaces as `unnecessary_ignore`, which is the tell that
you bound it to the wrong line. When a lint and the compiler disagree, trust
the compiler and suppress the lint narrowly.

---

## Open follow-up

_None open. The previous item is resolved below._

### RESOLVED — SQLCipher bundled-build licensing (2026-10-15)

- Verdict: **SQLCipher Community Edition is BSD-3-Clause** (Zetetic) — fine for
  this closed-source app, no Commercial Edition purchase needed. Requirement:
  reproduce copyright + license text in a **user-accessible** location.
- Evidence: `hooks.user_defines.sqlite3.source: sqlcipher` builds `libsqlcipher.so`
  for all 3 Android ABIs (present under `app/build/.../jniLibs/`); binary check:
  NEEDED = only system libs, **OpenSSL 3.6.3 statically linked** (string
  `OpenSSL 3.6.3 9 Jun 2026` present, no dynamic `libcrypto` entry) → Apache-2.0
  attribution also required for OpenSSL; SQLite itself is public domain.
- Action taken: `app/NOTICE.md` created with full SQLCipher BSD-3 text, SQLite
  public-domain note, and OpenSSL Apache-2.0 notice; it is the source for the
  in-app **Settings → About → Open-source licenses** screen (P2). Wire as a
  bundled asset when the screen lands.
- Custom-build path (if ever needed): `sqlite3` package `doc/hook.md`.

---

## R14 — `Uri.port == 0` never drops a default port: `:443`/`:80` survive normalization

**Symptom.** `normalizeBaseUrl('https://x.example.com')` returned
`https://x.example.com:443`. Only caught by a widget test asserting the stored
value after a save; the analyzer and every other test stayed green.

**Root cause.** `Uri.parse('https://a.com').hasPort` is `false` and
`.port` is `443` (the scheme default is synthesized, not "absent"). The old
guard `uri.port == 0` therefore never fired, so the port branch always
appended — including the explicit-default form `https://a.com:443`, which Dart
also reports as `hasPort == false`.

**Fix.** `lib/core/settings/connection_settings.dart` — key off `hasPort`,
which is `true` only for a genuinely non-default port:

```dart
return '${uri.scheme}://${uri.host}'
    '${uri.hasPort ? ':${uri.port}' : ''}';
```

**Tested.** `test/core/connection_settings_test.dart` (5 cases: trim+path
drop, non-default `:8443` kept, explicit `:443`/`:80` dropped, scheme-less /
non-http / whitespace / no-authority rejected) and the widget suite
(`settings_screen_test.dart` save-normalize case). Full run:
`flutter test` **321/321**, `flutter analyze` 0 issues.

**How to avoid repeating it.** Never test `Uri.port == 0` (or `!= 0`) to mean
"the URL had no port". Dart synthesizes the scheme default, so `port` is always
a number. `hasPort` is the only correct "was a port actually specified (and is
it non-default)" predicate.

---

## R15 — `SyncEngine.sync()` success path never set `last_sync_status='ok'`

**Symptom.** Test "successful cycle records last_sync_ts and last_sync_status=ok"
failed: `last_sync_ts` was written but `metaGet(lastSyncStatusKey)` returned
`null` (or a stale `'error'` from a prior failed cycle). The app-bar sync
indicator (`syncStatusProvider`, `providers.dart:98`) would therefore never show
a clean `'ok'` after a successful cycle.

**Root cause.** `sync()` called `_setLastSynced()` on the success path but only
called `_setLastStatus('error')` on the three failure paths. `restoreFromServer`
correctly called `_setLastStatus('ok')`, so restore looked fine while a normal
cycle left the status key unset/stale.

**Fix.** `lib/data/sync/sync_engine.dart` — add `_setLastStatus('ok')` at the end
of the success path in `sync()`:

```dart
await _setLastSynced(_now().millisecondsSinceEpoch);
await _setLastStatus('ok');   // ← was missing
return SyncOutcome(ok: true, pushedOps: pushed, pull: pullStats);
```

**Tested.** `flutter test test/data/sync/sync_engine_test.dart` 10/10; full
`flutter test test/data/` 118/118 pass.

**How to avoid repeating it.** When a "last status" field is read by the UI, the
success path must set it explicitly — do not assume writing the timestamp is
enough, and do not rely on the field being pre-seeded. Mirror the status write in
every code path that returns a success `SyncOutcome`.

---

## R16 — Recurrence Model B migration v3/v4 replayed onto a v1 table that already had the new columns

**Symptom.** `test/domain/entities/entity_persistence_test.dart` failed in
`setUpAll` with `no such column: recur_until`, so the whole persistence suite
aborted before a single case ran. `recurrence_test.dart` also failed on the old
wire contract (`type`/`first_date`/`apply_rules` not round-tripping, 1:N
`repetitions` absent).

**Root cause.** Two things collided:

1. The still-unreleased `_initialSchema` had already been edited in place to the
   Model B shape (`repeat_until TEXT`, no `repeat_freq`), while the migration map
   still carried the older rename/drop chain (`RENAME COLUMN recur_until` →
   `repeat_until`, `DROP COLUMN repeat_freq`, plus a `CREATE TABLE
   recurrence_repetitions` that v1 already created).
2. SQLite runs `onCreate` by replaying **every** migration list in order on a
   fresh database. So each of those statements executed against the table v1 had
   *just created* — the rename targeted a column that no longer existed under
   the old name, and the child-table CREATE hit "table already exists".

**Fix.** `app/lib/data/db/schema.dart`:

- v1's `recurrences` now carries the full Model B column set from the start —
  `type`, `first_date`, `repeat_until`, `apply_rules` (wire-backed) and
  `latest_date` (phone-local scheduler cursor) — plus the
  `recurrence_repetitions` child table + lookup index (no
  `$syncBookkeepingColumns` on it: repetitions are owned by the parent and
  rewritten wholesale on parent upsert).
- Migration map collapsed to `{1: _initialSchema}` — the Model B version-2 entry
  was folded in because v1 never shipped under its earlier shape, so there is no
  installed base to migrate. A comment above the map records why a
  rename/drop must never be reintroduced there.

**Tested.** `flutter test test/domain/entities/` **188/188**; full
`flutter test` **390/390**; `dart analyze lib/` 0 errors.

**How to avoid repeating it.** Editing an initial schema in place only stays
safe while the migration list is edited to match — `onCreate` replays *all*
versions, so any migration statement whose target the initial create already
satisfies will throw on every fresh install. Whenever you change a column in
`_initialSchema`, re-read the whole `migrations` map top-to-bottom and delete
every statement the new shape makes redundant; never assume a version list only
runs against *old* databases.

---

## R17 — `const FieldSpec` with `requiredWhen`/`isValid` closures fails to compile (5 suites unloadable)

**Symptom.** Entity suites passed, but 5 unrelated suites failed to *load*:
`api_fixtures_smoke_test`, `app_smoke_test`,
`integration/airplane_mode_transaction_test`, `ui/entity_list_screen_test`,
`ui/entity_form_screen_test`. Errors: `Not a constant expression` /
`Method invocation is not a constant expression` at
`lib/ui/configs/entity_configs.dart:914+`.

**Root cause.** Three `FieldSpec`s in `recurrencesConfig` (`repeatUntil`,
`nrOfRepetitions`, `repetitions`) were declared `const` while also carrying
`requiredWhen:`/`isValid:` function closures. Dart closures are never
constant-evaluable, so the whole config file stopped compiling — and every test
importing it failed at load time with no test-level error message pointing at
the real file.

**Fix.** Dropped `const` on exactly those three (the file already used bare
`FieldSpec(` for closure-carrying specs elsewhere, e.g. the account `type`
field). No other spec touched.

**Tested.** `dart analyze lib/` → **0 errors** (was 17+); full `flutter test`
**390/390**.

**How to avoid repeating it.** `const` and closures are mutually exclusive. When
adding a `requiredWhen`/`isValid` validator to a spec, drop `const` on *that
FieldSpec only*. And when several suites fail with the identical
"loading <file>" message, read the compile errors first — they name the single
shared source file, not the tests.

---

## R18 — P4 handoff left `flutter analyze` at 77 (baseline 62): 15 new infos in backup_client/providers/sync_engine

**Symptom.** After the P4 Story-2 restore session closed, `flutter analyze`
(app-wide gate) reported **77 issues** instead of the **62** left as baseline
after P2/P3. All 15 extra infos sat in three files written or touched that day:
`lib/data/sync/backup_client.dart` (12), `lib/core/providers.dart` (1),
`lib/data/sync/sync_engine.dart` (2).

**Root cause.** Three independent mistakes, all from working without the
analyzer in the loop:

1. `backup_client.dart` was written by hand and handed off without a single
   `flutter analyze` run. It tripped 7 lint classes: missing `library`
   directive; `comment_references` ×3 (the sidecar-contract doc, moved onto
   `BackupReport`, referenced `[SyncEngine]` — a member of another file a doc
   comment cannot resolve — plus a bare `[trigger]`); and on this SDK
   `unnecessary_type_name_in_constructor` ×3, whose fix is the unnamed
   constructor shorthand `const new(...)` / `const new disabled()` instead of
   `const BackupReport(...)`. Plus `sort_constructors_first`,
   `prefer_initializing_formals` ×2 (ctor params assigned to the private
   `_settings`/`_timeout` fields through an init-list instead of `this._x`),
   `avoid_catches_without_on_clauses`, `omit_local_variable_types`.
2. `providers.dart`: the `/// SyncEngine status...` doc block belonging to
   `syncEngineProvider` was concatenated onto `backupClientProvider`'s doc when
   the new provider was inserted — `syncEngineProvider` ended up with no doc at
   all → `public_member_api_docs`.
3. `sync_engine.dart`: the new `withEngines(...)` constructor assigned its
   `backup` parameter to `_backup` in the body (`prefer_initializing_formals`)
   and the backup-run guard used a bare `catch (_)`
   (`avoid_catches_without_on_clauses`).

**Fix.** The 15 lints, fixed with no behavior change:

- `backup_client.dart` (12): deleted `library firefly;`; moved the contract doc
  from `BackupReport` onto `BackupClient`, `[SyncEngine]` → `` `SyncEngine` ``
  (plain code span, no symbol link), `[trigger]` → `[BackupClient.trigger]`
  and re-wrapped the line to ≤80 cols; both ctors → `const new(...)` /
  `const new disabled()`, hoisted above the fields (`sort_constructors_first`);
  `BackupClient({...})` → `required this._settings, required this._baseUrl, …,
  this._timeout = const Duration(seconds: 8)` with the init-list dropped;
  `catch (exc)` → `on Object catch (exc)`; `Map<String, dynamic> body = …` →
  `var body = <String, dynamic>{};` — **the `<String, dynamic>` must stay**:
  a bare `= {}` is `Map<dynamic, dynamic>`, and the
  `jsonDecode(...) as Map<String, dynamic>` cast inside `_sidecarFailureMessage`
  would then throw on the recovery path.
- `providers.dart` (1): split the merged block back — one doc block per
  provider.
- `sync_engine.dart` (2): `BackupClient? backup` → `this._backup` (dropped
  `_backup = backup,`; private named-param `this._x` verified lint-free on this
  SDK by a scratch probe); `} catch (_) {` → `} on Object catch (_) {`.

**Tested.** `flutter analyze` **77 → 62** (exact baseline; zero infos remain in
all three touched files — the two `sync_engine_test.dart` infos that match the
same grep were already part of the 62). `flutter test` **438/438**. `dart
format lib/data/sync/backup_client.dart` for the new file only — the repo has
pre-existing format drift in untouched baseline files (e.g. `pull_engine.dart`),
so a repo-wide format deliberately stays non-gating.

**How to avoid repeating it.** Run `flutter analyze` before declaring any
coding session done — the P4 handoff never did, which is exactly why 15 infos
accumulated unnoticed. When inserting a provider above an existing one in
`providers.dart`, never grow the neighbour's doc block: one doc comment per
member, always. Catch rules here: bare `catch (_)` is linted → write
`on Object catch (_)` (still catches everything, `String`/`Exception`/`Error`
alike).

## R19 — Linux desktop switch stalled `app_smoke_test`: real async (dart:io + FFI isolate) never settles under `testWidgets` fake async

**Symptom.** After moving the desktop build to the real Linux open path
(`databaseFactoryFfi` + app-support dir in `defaultDatabasePath`), the CI gate
`test/app_smoke_test.dart` hung at `pumpAndSettle` and timed out
(`pumpAndSettle timed out` with the `SyncStatusIndicator` spinner still
ticking). The target dir `~/.local/share/firefly_mobile` was never created.
Everything else stayed green (438/438 minus the smoke suite).

**Root cause.** `testWidgets` runs the body in a fake-async zone; real dart:io
completions (mkdir/write in `defaultDatabasePath`) and the FFI open's
`Isolate.run` are scheduled on the real event loop, which the fake-async zone
never drains — so `databaseProvider` stays in `AsyncLoading` forever and
`syncStatusProvider`'s spinner never settles. Three diagnostics proved it
(temp scratch suite, since deleted): DIAG-1 plain `test()` dir-creation
completes fine; DIAG-2 dart:io file write inside `testWidgets` never lands the
file; DIAG-3 `sqflite_common_ffi` isolate open hangs under `testWidgets` but
opens in **252 ms** in a plain `test()`. This is NOT a product bug — the Linux
boot path is correct (it opens fine outside the fake-async zone). The old smoke
test only passed because the previous platform-channel factory failed *fast*
with `MissingPluginException` (platform messages are delivered synchronously
by the test binding), landing on the static error UI instead of the spinner.

**Fix.** Test-side only, using the seam pattern already documented in
`lib/core/providers.dart` (tests override seam providers, never poke platform
channels):

- `lib/app.dart`: added optional `const FireflyApp({super.key,
  this.overrides = const []})` forwarded to `ProviderScope(overrides: ...)`
  (the scope is owned inside `FireflyApp`, so an outer `ProviderScope` cannot
  inject overrides — nested scopes create a fresh container). `Override` is
  imported from `package:flutter_riverpod/misc.dart` (Riverpod 3 does not
  export it from the main library). Doc note: `[databaseProvider]` had to be
  a plain backtick span — a bracket reference to an unimported symbol trips
  `comment_references`.
- `test/app_smoke_test.dart`: `setUpAll(sqfliteFfiInit)` + one real-async
  `openTestDatabase()` (in-memory, `databaseFactoryFfiNoIsolate` — no dart:io,
  no isolate) shared by both tests via `databaseProvider.overrideWith`.
  The boot chain's other seams stay un-overridden: `databasePathProvider` and
  `keyStoreProvider` are only consumed inside `databaseProvider`, and
  `SyncLifecycleWatcher` fires on resume transitions only — never at cold
  start — so no HTTP/probe runs during the pump.

**Test.** `flutter test test/app_smoke_test.dart` 2/2; full suite **438/438**;
`flutter analyze` **62** (= baseline — the first cut of this fix added 2
(`comment_references` in `lib/app.dart`, `unused_import` flutter_riverpod in
the smoke test), both removed and re-verified); `tmp_linux_diag_test.dart`
deleted before the final runs. A parallel first attempt reported 441 = 438 +
the 3 still-present diag tests — re-ran after deletion to pin 438.

**How to avoid repeating it.** Any widget test that pumps `FireflyApp` must
override `databaseProvider` with a pre-opened in-memory DB (open it in
`setUpAll`, real async) — the real boot path can never settle under
`testWidgets` fake async. Never chase this as a product bug: the tell is
"works in plain `test()`, hangs in `testWidgets`" (or a file/dir the async
work should have created that never appears). Do not put test-environment
detection into prod code to work around it.

**Desktop scaffold gotchas (same session, `flutter create --platforms=linux`):**
the repo had no `linux/` runner at all — created with
`flutter create --platforms=linux --project-name firefly_mobile .` (dir name is
`app`, pubspec name is `firefly_mobile`, so `--project-name` is mandatory).
Two silent side effects to re-check after any `flutter create` on an existing
project: (1) it **replaced** the `platform: android` entry in `app/.metadata`
with `platform: linux` instead of appending — android's entry was restored by
hand (both must stay; that file feeds `flutter migrate`); (2) it injected a
boilerplate `test/widget_test.dart` referencing a non-existent `MyApp` → suite
loading failure + 3 analyze issues — deleted (it never existed in this repo).
`analysis_options.yaml` gained a legitimate `linux/**` exclude (mirrors
`android/**`). Final gates after scaffold: `flutter test` **438/438**,
`flutter analyze` **62**, `flutter build linux` →
`build/linux/x64/release/bundle/firefly_mobile`.

## R20 — Screenshot of the running Linux app: xdotool is dead on a Wayland window, workspace focus races other opencode sessions, ydotool coords are screen/2

**Symptom.** Task: capture a full-window screenshot of the running
`firefly_mobile` desktop app on its Transactions tab (8 seeded demo rows).
Three independent failures: (1) `xdotool windowactivate` / `mousemove` / `click`
silently did nothing — the app never received focus or a single click;
(2) focus set before a click was gone by the time the click/screenshot ran —
`grim` kept capturing the wrong workspace because another opencode session
sharing the compositor switched workspaces between separate commands; (3) once
`ydotool` clicks landed they were offset — clicks intended for the bottom-nav
tab hit far right/bottom.

**Root cause.** Three traps on this box (Hyprland 0.56.2, session shared with
other opencode agents):
1. `xdotool` speaks X11/XTEST; the GTK window `com.firefly.firefly_mobile` is
   Wayland-native with no XWayland mapping — xdotool events/focus target
   nothing. The tell: commands exit 0 yet nothing changes.
2. Focus/workspace state is global and racy: any two-command sequence
   (focus … then click) can be interleaved by a concurrent session's workspace
   switch. Verified by re-checking `hyprctl activewindow -j` class immediately
   after focusing — it was no longer `com.firefly.firefly_mobile`.
3. `ydotool mousemove` takes absolute coordinates in its virtual-device space,
   which on this host maps as exactly **screen/2** (send 312,570 for screen
   624,1140) — sending raw `grim` pixel coords lands the click twice as far
   right/down.

**Fix.** One atomic bash invocation per attempt — focus, guard, click, capture
with no other tool call in between:
`hyprctl dispatch 'hl.dsp.focus({ workspace = "5" })'` (Hyprland 0.56.2 Lua
dispatch syntax) → guard
`[[ $(hyprctl activewindow -j | jq -r .class) == com.firefly.firefly_mobile ]]`
→ `ydotool mousemove <screen_x/2> <screen_y/2>` → `ydotool click 0xC0` →
`grim <shot.png>`. Bottom-nav "Transactions" tab center = screen (624,1140) →
sent (312,570).

**Test.** The atomic loop produced the capture showing the app focused on
Transactions with exactly the 8 seeded demo rows (Whole Foods, Coffee, Salary,
To savings, Netflix, Rent, Freelance invoice, Electric bill); promoted to
`app/docs/shots/transactions-list-8-demo-rows-2026-10-20.png`.

**How to avoid repeating it.** Never xdotool against a Wayland-native window
on this box; always convert screen pixels to ydotool coords with /2; always run
focus + class-guard + click + grim as a SINGLE bash command (workspace state is
shared with other sessions); verify `hyprctl activewindow -j` class is the
target app before trusting any screenshot.

## R21 — P3 push 422'd on live Firefly: client sent the JSON:API member, request validators want the flat attributes object (unit tests pinned the wrong wire contract)

**Symptom.** P3 push path was green in unit tests (465 pass) but failed
against the real server: every create op replayed by `OpLogPusher` returned
HTTP 422 `{"name": ["The name field is required."]}` even though the op-log
payload and local row both carried a non-empty `name`. The gated live e2e
(`FIREFLY_LIVE=1`) could not converge; probe rows created directly via curl
were also rejected with the same 422.

**Root cause.** Asymmetric request/response contract that no test caught:
- Firefly **request** validators (`StoreRequest`) take the **flat
  attributes object** — `{"name": "X"}`. A JSON:API member body
  `{"type": "categories", "attributes": {"name": "X"}}` fails validation
  because `name` is not at the top level → 422.
- Firefly **response** bodies are JSON:API-wrapped (`{data: {...}}`).
- `FireflyApiClient.create/update` sent the member as the body, and **three
  tests pinned that wrong contract**: two client tests asserted
  `{"type":...,"attributes":...}` on the wire, and the pusher ordering test
  read `body['attributes']['name']` off the request — all mocked at the
  `http` layer, so they verified the bug instead of catching it. The wrong
  contract was first written into a test comment claiming it was "Firefly's
  request contract"; DESIGN/IMPLEMENTATION-PLAN never claimed it.

**Fix.** `app/lib/data/api/firefly_api_client.dart` — new
`_requestBody(member)` static helper: if the body carries an `attributes`
map, unwrap it (send the flat object); otherwise pass through unchanged.
`create`/`update` route their wire body through it; doc comments corrected
(request flat / response wrapped). Callers (pusher, repos, op_log payloads)
keep the app-wide `{type, attributes}` member contract unchanged.
Re-pinned tests: client `create()`/`update()` wire assertions now expect
flat bodies, new defensive passthrough test added (24/24 in that file);
pusher ordering-test handler reads `body['name']`. Live probe residue
(category ids 1, 2) deleted (204).

**Test.** Full `flutter test` = **466 pass / 0 fail** (465 baseline + 1 new);
`flutter analyze` = **61** issues (baseline 62, −1 because the superseded
long `expect(seenBody, '{"type":...}')` line was replaced by a short one; no
new rule instances in touched files). Live proof:
`FIREFLY_LIVE=1 flutter test test/integration/live_sync_e2e_test.dart` =
**1/1 PASS** (`create → sync → server has row → restore parity`).

**How to avoid repeating it.** Wire-contract assertions must be validated
against the live service at least once — a mocked `http` layer happily
confirms a wrong body shape. Firefly-style JSON:API services are
asymmetric: *request* = flat attributes object, *response* = wrapped member;
never assume symmetry. Symptom fingerprint: 422 naming a field the payload
clearly contains = the field is nested one level deeper than the validator
looks.

## R22 — Inserting the P4.1 PC-backup section broke six widget tests below it: the ListView lazy cacheExtent trap (third recurrence, now with three distinct fingerprints)

**Symptom.** After the PC-backup section was inserted into `SettingsScreen`
above Diagnostics and the Sync tile, six previously-green widget tests
failed in three different ways:

1. `settings_screen_test.dart` probe/export tests —
   `expect(find.widgetWithText(OutlinedButton, ...), findsOneWidget)`
   found **0 widgets**.
2. `settings_screen_test.dart` save/clear/rejects backup-URL tests and
   four `settings_sync_test.dart` Sync-now tests —
   `Bad state: No element` from `WidgetTester.ensureVisible` /
   `enterText` (`Iterable.single` on an empty finder).
3. `settings_sync_test.dart` log-tile test — tap produced a
   hit-test warning and `SyncLogScreen` never appeared (tap landed
   on nothing: the tile was *built* but still **off-screen**).

**Root cause.** `SettingsScreen` is one big `ListView`; children below
the viewport are built lazily only up to `cacheExtent` (~250 px). The new
section added ~3 rows between the PAT tile and everything below it, so
every finder targeting Diagnostics / Sync / About now either:

- matches **0 widgets** if nothing scrolls first (fingerprint 1), or
- is handed to `ensureVisible`/`enterText` while unbuilt (fingerprint 2),
  or
- exists in the tree (built into the cache window) but its rect is still
  below the viewport, so `tester.tap` hit-tests empty space (fingerprint 3,
  the silent one — only the "warning: tap" line gives it away).

A fourth, self-inflicted ordering trap was also present in the new P4.1
tests: `ensureVisible(saveButton)` scrolls the button into view, which
**evicts the URL field above it** from the built window — so
`enterText` on the field afterwards finds nothing. Fix = type first,
then scroll to the button.

**Fix.** All three fingerprints share one remedy —
`scrollUntilVisible` (materialise) → `ensureVisible` (put in viewport)
→ then assert/tap:

- `settings_screen_test.dart`: new `scrollTo()` helper; applied to the
  About-tile test (original 2026-10-18 occurrence), the probe and export
  tests, and the three new backup-URL tests (which also reorder
  `enterText` before the button scroll).
- `settings_sync_test.dart`: new `tapSyncNow()` helper wraps the trio for
  all five Sync-now taps; the log-tile test gained the missing
  `ensureVisible` between its existing `scrollUntilVisible` and `tap`.

**Prevention.** Inserting *any* new section into a `ListView`-based
screen requires re-running every widget test that finds a tile below the
insertion point; a bare `find.*` assertion or a tap without the full
scroll→ensureVisible→act trio is not enough. If a test already scrolls,
check it also `ensureVisible`s before tapping — built ≠ visible.

**Tested.** `flutter test` **486 passed, 1 skipped** (was 486 with 6
failures mid-fix; settings_sync 16/16, settings_screen 21/21);
`flutter analyze` **61 infos** (baseline 62 − 1; only the two known
pre-existing infos remain in the touched sync files).

## R23 — Sweep test pass: horizontal RenderFlex overflows (settings token rows, entity-form dropdowns) + duplicate FAB default hero tags in the shell route

**Date.** 2026-10-23 (overflow sweep session, continuation).

**What broke.**

1. `settings_screen.dart:719` (PAT *edit* mode) and `:788` (backup-token
   *edit* mode): a `Row([FilledButton('Save token'), 8, OutlinedButton('Cancel')])`
   exceeded the 288px content width — **42px overflow at 320 logical px,
   1.6px at 360**, clean at 393/412. The two buttons render ~330px wide
   under the test font; any font-scaling user hits this on device too.
2. `entity_form_screen.dart:376/467`: the `DropdownButtonFormField`
   hint text is laid out in an unconstrained width context (IndexedStack
   shell gives the list its full width, then the Row clips to ~232px for
   the reference dropdown) → RenderFlex overflow in budgets/transactions
   forms.
3. Shell-wide sweep captured **48 × "There are multiple heroes that
   share the same tag … `<default FloatingActionButton tag>`"**: the home
   shell keeps every tab's `EntityListScreen` alive in one `IndexedStack`
   = **one PageRoute subtree**, and each list builds a FAB with Flutter's
   default hero tag. Two default-tag FABs in one route subtree is a hard
   `FlutterError` on every navigation.

**Root cause.** (a) `Row` used where horizontal budget is smaller than the
intrinsic button widths (no `Wrap`/`Flexible`). (b) Dropdowns not
`isExpanded`, so the hint chooses its intrinsic (wide) size. (c) FAB hero
tags defaulted per-widget instead of per-screen — invisible while only one
tab screen was built, fatal once IndexedStack builds all of them.

**Fix.**

- `lib/ui/screens/settings_screen.dart`: both edit-mode button `Row`s →
  `Wrap(spacing: 8, runSpacing: 8)` (children minus the `SizedBox(width: 8)`
  spacer). Summary-mode rows (686/755) left untouched — never overflowed.
- `lib/ui/screens/entity_form_screen.dart`: `isExpanded: true` on the
  choice dropdown (:391) and the reference dropdown (:467).
- `lib/ui/screens/entity_list_screen.dart`: `heroTag:
  'entity-list-fab-${config.title}'` on both FAB variants (plain +
  extended).

**Tested.**

- Regression sweeps (kept): `test/ui/zz_overflow_screens_test.dart`
  sweep2 **12/12** (About/SyncLog/EntityForm×2 × 4 widths),
  `test/ui/zz_overflow_settings_test.dart` **4/4** (320/360/393/412),
  `test/ui/zz_overflow_diagnostic_test.dart` **0 captured errors**
  (2 seed modes × 6 widths × all tabs + More→Accounts/Categories),
  timeout raised to 20 min (two full sweeps exceed the 10-min default).
- Full suite: `flutter test` **514 passed, 1 skipped, 0 failed**;
  `flutter analyze` **61 infos = exact baseline** (throwaway
  `zz_probe_test.dart` deleted; its 15 line-length infos + 4 lint infos in
  the sweep files fixed → `grep zz_` = 0).

**Prevention.** In this app the shell is an IndexedStack inside ONE
PageRoute: never put >1 widget with the same (default) hero tag in
per-tab screens — always pass an explicit `heroTag` keyed to the screen.
Any fixed-width `Row` holding two Material buttons must be a `Wrap`, and
every `DropdownButtonFormField` inside a `Row` needs `isExpanded: true`.

## R24 — Dashboard quick-access tiles: 9.9px vertical RenderFlex overflow at 320px + a captured onError wedging the test binding

**Date.** 2026-10-25 (overflow sweep session, continuation).

**What broke.**

1. `dashboard_screen.dart` `_QuickAccessTile`: the quick-access grid's
   `Column` (Icon 24 + 6px gap + Text) overflowed its grid cell by
   **9.9px at 320 logical px** — at 320 the 4-column grid leaves <55px
   for the column content after 10px padding, and a 2-line label at
   fontSize 11 needs more than the remainder. Captured 7× by the kept
   diagnostic sweep (same head, both seed modes).
2. The diagnostic test itself: the capture-callback left
   `FlutterError.onError` overridden while `expect` threw (the 7 errors
   failed the `expect(errors, isEmpty)`), so the binding's
   `_pendingExceptionDetails` assertion wedged `tearDownAll` until the
   20-minute suite timeout — a false test failure masking the real
   overflow.

**Root cause.** (a) Unbounded-height children (Text with no maxLines
budget) inside a fixed-height grid cell: `Column` sizes to intrinsic
text height and paints past the cell when intrinsic > cell. (b) Test
code order: restoring an overridden `FlutterError.onError` must happen
*before* any throwing assertion, else the binding never sees a clean
error state.

**Fix.**

- `lib/ui/screens/dashboard_screen.dart:716` — `_QuickAccessTile`
  Column gets `mainAxisSize: MainAxisSize.min`; the label `Text` is
  wrapped in `Flexible` (:724) so it takes only the leftover height,
  keeping `maxLines: 2` + ellipsis instead of painting out of bounds.
  Spacer gap also tightened 8→6 (:719).
- `test/ui/zz_overflow_diagnostic_test.dart:87` — `FlutterError.onError =
  prev` restored *before* `expect`, so a failing expect can no longer
  wedge the binding/teardown.

**Tested.**

- `flutter test test/ui/zz_overflow_diagnostic_test.dart` →
  **CAPTURED 0 error(s)**, finishes in 10s (was 7 errors + 20-min
  hang).
- Full suite: `flutter test` **515 passed, 1 skipped, 0 failed**
  (514 baseline + diagnostic now green).
- `flutter analyze` **61 infos = exact baseline** (my first
  diagnostic-test edit added a `noop_primitive_operations` info —
  `${details.toString()}` in an interpolation → `$details`; reverted
  to 61).

**Prevention.** Any widget inside a fixed-height grid/sliver cell must
use `mainAxisSize: MainAxisSize.min` + `Flexible` on the text child so
intrinsic text height can never exceed the cell. Test error-capture
blocks must always restore `FlutterError.onError` before asserting.

---

## R25 — "Delete does nothing, backup does nothing": full-precision amounts blew up every transaction row, and an unconfigured backup logged nothing

**Date.** 2026-11-18 (button-audit session).

**What broke.** On the phone every transaction row rendered mangled
(description one character per line) and its ⋮ menu could not be tapped, so
Delete appeared to do nothing; sync pushes stayed empty because no delete ever
queued. Separately, tapping "Sync now" with no backup URL configured wrote
nothing to the sync log, so backup appeared dead too.

**Root cause.**

1. Firefly III returns amounts at full precision — the live pull stores
   `2023.440000000000`, `1230.000000000000`. `_txTrailing` rendered that raw
   string, making the trailing column wider than the whole `ListTile`, so
   Flutter threw *"Trailing widget consumes the entire tile width"* once per
   row. The rows still painted (broken), but the throw short-circuited the
   gesture handling for the ⋮ button.
2. `SyncEngine._runBackup` returned silently when `client == null` or the
   report was disabled, so an unconfigured backup produced no log line at all.

**Fix.**

- `lib/ui/configs/entity_configs.dart:1671` — `_txGroupAmount` rounds to two
  fraction digits (carry via `BigInt`, trailing zeros dropped); the amount
  `Text` sits in `ConstrainedBox(maxWidth: 96)` with `maxLines: 1`, ellipsis
  and `textAlign: end` (:1688).
- `lib/data/sync/sync_engine.dart` — `_recordBackupSkipped(reason)` writes a
  `backup`/`skipped` line with a `backup.unconfigured` failure for both
  unconfigured paths.

**Tested.**

- New pin `test/ui/transactions_list_test.dart` → *"full-precision Firefly
  amounts keep the row usable at phone width"*: 12-decimal amounts at 360 dp
  render `-$2,023.44` / `+$1,234,567.89`, no exception, ⋮ inside the viewport,
  menu opens with Delete. Reverting the fix reproduces the production
  assertion, so the pin bites.
- Live check against the real server (`pullOnly`, throwaway test): 801 rows
  inserted, 546 transactions local, and server counts identical before/after
  (114 accounts / 546 transactions / 29 categories / 52 tags / 4 budgets /
  5 bills / 2 rules / 5 subscriptions / 42 currencies) — a pull never writes
  to the website.
- `flutter test test/ui test/data` → **296 passed, 0 failed**.

**Prevention.** Never render a server-sent decimal string directly in a
`ListTile` trailing slot: round it and cap the width. Pins must use the
precision the server actually sends, not hand-written `4.50`.

---

## R26 — Every Settings sync/restore button test died before reaching a button

**Date.** 2026-11-18 (button-audit session).

**What broke.** All 10 `settings_sync_test.dart` button tests plus the probe
and export tests in `settings_screen_test.dart` failed with
`Bad state: No element`, so no test ever tapped "Sync now", a directional
sync, restore, test-connection or export.

**Root cause.** The helpers scrolled `find.byType(Scrollable).first`, which
resolves to the *first text field's* internal horizontal scrollable (the
screen has three Scrollables), so `scrollUntilVisible` dragged sideways, the
list never moved, the target stayed unbuilt and `dragUntilVisible` ended in
`element(finder)` on an empty finder. Separately, `pumpAndSettle` after
tapping hung on the screen's indeterminate progress indicators.

**Fix.** Both files scroll
`find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first`
(`settingsScrollable()`), and interaction settles use a bounded pump loop
(under the 4 s SnackBar timeout) instead of `pumpAndSettle`. Two stale
assertions were corrected: the cycle now logs three rows (push + pull +
backup-skip), and the app-bar "Sync now" stub SnackBar test was dropped — the
indicator is status-only and the button lives in Settings.

**Tested.** `flutter test test/ui/settings_sync_test.dart` **16/16**;
`settings_screen_test.dart` **15/15**; `home_shell_test.dart` **5/5** (now
five destinations incl. Settings); `sync_status_indicator_test.dart` **6/6**;
full `test/ui test/data` **296 passed**.

**Prevention.** In multi-`Scrollable` screens always scope the scrollable to
the list (`ListView` → `Scrollable`), and never `pumpAndSettle` a screen that
shows an indeterminate `CircularProgressIndicator` while busy.

---

## R27 — Every account balance on the Dashboard was wrong (added only the newest 50 rows)

**Date.** 2026-11-18 (balance-audit session).

**What broke.** On the real book (546 transactions, 114 accounts) the Dashboard
account cards read SadaPay `Rs 7,102.53`, NayaPay `Rs 2,000`, MCB `Rs 89,069`
and bybit `$0.43`. The server — and the same arithmetic over the whole table —
says `4,041.00`, `52.90`, `2,012.28` and `$98.1346`.

**Root cause.** `buildDashboardSummary` sums opening balance ± every ledger leg,
which is right, but the Dashboard watched the *paged* list providers
(`transactionListProvider`, `accountListProvider`), and those load
`getAll(limit: 50)` from `providers.dart`. With 546 transactions and 114
accounts the summary therefore saw a 50-row slice: 7,102.53 is exactly
`opening + legs` over the 50 newest rows, verified by replaying the query
against the pulled device database. Reports was already correct because
`reports_screen.dart` loads with `limit: 100000`.

**Fix.** Added `ledgerTransactionsProvider` / `ledgerAccountsProvider`
(kLedgerQueryLimit = 100000, same cap as Reports) and pointed
`dashboard_screen.dart` at them for both the watch and the pull-to-refresh
reads; the refresh now also invalidates them, so it re-reads the database
instead of returning the cached future. List screens keep the 50-row page.

**Tested.** New `test/ui/dashboard_ledger_providers_test.dart` seeds 60
transactions and 55 accounts into an in-memory database and asserts the ledger
providers return all of them while the paged providers still return 50, and
that `accountBalance` over the ledger is 600 while the page value is not.
Reverting the provider to `limit: 50` fails the test ("has length of <50>").
Full `flutter test` **527 passed, 1 skipped**; `flutter analyze` back to the
278 pre-existing infos. On device the four cards now read `Rs 4,041`,
`Rs 52.9`, `Rs 2,012.28`, `$98.135`, and "Sync now (both ways)" logged
`push|ok (0 ops)`, `pull|ok (0 inserted, 0 updated)`, `backup|skipped` with
the server still at 114 accounts / 546 transactions.

**Known follow-up.** Net worth adds USD balances to PKR at 1:1 (the local
`currencies.rate` is NULL and the app never pulls `/api/v1/exchange-rates`),
so the hero card reads `Rs 64,328.705`. The per-account balances are correct;
the cross-currency total needs an exchange-rate pull. The Transactions list
still renders one arbitrary 50-row page — every pulled row shares the same
`updated_at`, so `ORDER BY updated_at DESC LIMIT 50` returns a random slice
(the 2024 rows seen on device) — which needs a date-ordered paging decision.

**Prevention.** Summary screens must read ledger-wide providers, never the
paged list providers. Any new "balance"/"total"/"net worth" surface gets a
provider-limit test with more rows than the page size.

---

## R28 — Transaction order on the phone did not match the website

**Date.** 2026-11-18 (cross-verification session).

**What broke.** With the same 545 legs on both sides, the Transactions list and
the parity checker disagreed with the website in 545 of 545 positions.

**Root cause.** `transactionListProvider` read `ORDER BY updated_at DESC LIMIT
50`. Every pulled row is stamped with the pull time, so `updated_at` says
nothing about the booking order — it produced a semi-random 50-row slice that
ran newest-pulled first, and it hid everything past row 50.

**Fix.** `kTransactionListOrder` is now `date DESC, journal_id DESC` (numeric
cast) over the whole book, which is exactly what Firefly's own
`/transactions` index does, so ties inside one timestamp resolve the same way
on both sides. The header note in `providers.dart` records why.

**Tested.** `test/ui/transaction_list_order_test.dart` seeds legs sharing one
date and asserts journal-id descending order; `scripts/verify_sync_parity.py`
compares the app's order against the server list and reports `order … differs
in 0 positions` (it reported 545 before the fix).

**Prevention.** Any list the user compares against the website must sort on
server-stable fields, never on local bookkeeping (`updated_at`, `seq`).

---

## R29 — `external_id` was dropped on pull and never sent on push

**Date.** 2026-11-18 (cross-verification session).

**What broke.** The website carries a per-journal `external_id` (used by bank
imports and by anything matching transactions across systems). The phone model
had no column for it, so the field silently vanished on every pull and could
never be pushed — a whole field of every transaction was not in parity.

**Fix.** Schema v2 adds `transactions.external_id`; the freezed entity gained
`externalId` (regenerated `.freezed.dart`), `fromJsonApi` reads it, `toRow`
persists it and `toJsonApi` sends it. Migration v3 then clears
`remote_updated_at` so the next pull rewrites every row once and backfills the
new column instead of leaving it empty on rows the pull considered unchanged.

**Tested.** `test/data/db/app_database_test.dart` pins the v1→v3 migration
chain (column present, `remote_updated_at` NULL after v3); the parity checker
compares `external_id` per leg and reported no differences once backfilled.

**Prevention.** Every field the API returns must have a column, a decode, an
encode and a parity check — a field that only exists in the wire model is
invisible drift.

---

## R30 — An account with an opening balance could not be pushed, and one bad op wedged the whole queue

**Date.** 2026-11-18 (cross-verification session).

**What broke.** Creating an asset account on the phone with an opening balance
and leaving the date at "Not set" saved locally but failed to push forever:
`validation.server: The opening balance date field is required when opening
balance is present.` Retries failed identically, and because the pusher stops
at the first failing op, every later local change (transactions included) sat
behind it and never reached the website.

**Root cause.** `accountsConfig` sent `opening_balance` without
`opening_balance_date` whenever the user left the date empty, which Firefly
rejects; the pusher's ordered replay then blocked on that one op.

**Fix.** `_openingBalanceDate(values, updatedAt)` defaults the date to the
write's local day whenever a non-zero opening balance has no date, so the op
is always valid. The queued op for the already-stuck account was discarded
locally (recreated through the form afterwards) rather than touching the
website.

**Tested.** `test/ui/account_opening_balance_date_test.dart` (4 tests) pins:
date supplied → kept; balance without date → local day; zero balance → no
date; edit keeps the original date.

**Prevention.** Never let a client-side validation gap through: a single
permanently-invalid op stops the ordered queue, so every form field the server
requires must be defaulted or blocked in the UI.

---

## R31 — Transactions could not be pushed when they referenced a phone-created account

**Date.** 2026-11-18 (cross-verification session).

**What broke.** A transfer made on the phone between two phone accounts failed
to push: `validation.server: The transactions.0.source_id must be a number.
(and 3 more errors)` — the payload carried `01a1ec0d-…` (a local UUID) where
Firefly expects its numeric account id.

**Root cause.** The form stores local ids on the row and the op payload froze
them at save time. At save time the account may not exist on the server yet
(its own create op is still queued), so there is no numeric id to store.

**Fix.** `OpLogPusher` now resolves references at *replay* time:
`_transactionReferences` lists the reference fields (source/destination account,
currency, category, budget, bill), `_fireflyIdFor` looks the local id up in the
local table and returns the pushed `firefly_id`, and
`_applyResolvedReferences` writes the resolved numeric ids back onto the
`transactions` row after a successful push. Because the account's create op
replays before the transaction's op, the id exists by the time it is needed.
The same resolution runs in the create and the PUT branch of `_replayUpdate`.

**Tested.** `test/data/sync/op_log_pusher_test.dart` gained 3 tests (17 pass
in the file): a local-UUID reference is sent as the numeric id, an unpushed
reference is skipped instead of sending a UUID, and the resolved id is written
back to the row.

**Known limitation.** A reference that has no `firefly_id` at replay time
(created but not yet pushed, or deleted) is left unresolved and the op fails
with a validation error — the UI does not yet warn. Splits are a second gap:
the phone creates one leg per transaction, so a phone edit of a split group
would push a single-leg transaction; split groups pulled from the website stay
read-only in practice.

**Prevention.** Push payloads must never embed local primary keys. Any new
reference field belongs in `_transactionReferences` and needs a resolution
test.

---

## R32 — Every transaction on the phone was badged `conflict` (red triangle)

**Date.** 2026-11-18 (cross-verification session).

**What broke.** After the forced full re-merge that backfilled `external_id`
(R29), all 553 legs and all 118 accounts showed the "Resolved by server" red
triangle, i.e. the app claimed a conflict on every single row although the
content was identical on both sides.

**Root cause.** `_overwriteTransactionLeg` / `_overwriteFromServer` set
`sync_status = conflict` on every server-won overwrite without checking
whether anything actually changed, and the badge never cleared because the
next pull sees the same `updated_at` and skips the row.

**Fix.** The overwrite paths now compare the decoded row with the stored row on
every non-bookkeeping column (`_sameContent`, ignoring `id`, `firefly_id`,
`seq`, `updated_at`, `remote_updated_at`, `sync_status`, `deleted_at`): the
badge is only set when the server really replaced different local data, and an
identical rewrite stays `synced`. A `_healStaleConflict` pass clears a stale
badge when the row's `remote_updated_at` equals the timestamp the server still
reports, so the badge cannot survive forever.

**Tested.** `test/data/sync/pull_engine_test.dart` **21/21**, including two new
pins: an overwrite with identical content stays `synced`, and a stale
`conflict` badge is cleared while the pull still reports `skippedUnchanged`;
the pre-existing P3.5.2 pins (content genuinely changed → `conflict`) still
pass. On device the pulled database went from 553 `conflict` to 553 `synced`
rows after one sync, the list showed green checks, and
`scripts/verify_sync_parity.py` still reported `EXACT MATCH`.

**Prevention.** An informational badge must describe a real difference;
anything set on a code path that also runs for no-op rewrites needs an
"identical content" test.

---

## M1 — Milestone: website ⇄ phone parity is proven by script, not by eye

**Date.** 2026-11-18 (cross-verification session).

`scripts/verify_sync_parity.py` is now the gate. It pulls `/accounts`,
`/currencies`, `/transactions` from the Firefly API and the device database
from `adb`, then compares, per journal leg: existence (missing / extra legs),
every modelled field (description, dates, amounts, foreign amounts/currencies,
tags, notes, category, budget, bill, reconciled, external id, split legs),
the list order the app renders, and per-account fields and balances. It exits
1 on any difference.

Three disposable accounts were used so the real book stayed untouched:
`200 WEB_SYNC_TEST_20261117-170437` (USD), `202 WEB_SYNC_TEST_2_EUR` (EUR),
`204 MOBILE_TEST_3_GBP` (GBP, created on the phone), plus their three
initial-balance accounts. Website→phone, phone→website and a round trip of
three foreign-currency transfers (USD→EUR, GBP→USD, EUR→GBP, each with a
foreign amount, a tag and notes) end in `EXACT MATCH`: 551 groups / 553 legs,
118 accounts, 0 missing, 0 extra, 0 field differences, 0 order differences,
all balances equal. The rest of the book gained exactly the 2 new groups and
nothing else changed.

Also fixed while verifying (R28–R32): list order, `external_id`, the account
opening-balance date, local→numeric reference resolution and the conflict
badge. The API exposes `group_title` on 3 legs (one split group) which the
phone has no column for — the only known wire field still unstored.

---

## R33 — Tags were a raw JSON textbox, so a tag could only be typed as `["a","b"]`

**Date.** 2026-11-18 (Firefly-parity session).

**What broke.** The transaction form's Tags field was a plain text input: the
user had to type a JSON array (`["card","travel"]`), and a stray character
made the whole field invalid. Firefly's own form types one tag at a time,
turns it into a chip on enter, and offers the tags already in the book.

**Fix.** New `TagInputField` (`lib/ui/widgets/tag_input.dart`) and a
`FieldKind.tags` spec kind:

* typing a tag and pressing enter (or typing a comma) commits it as a chip;
* backspace on the empty field removes the last chip; each chip has its own
  delete button; duplicates are ignored case-insensitively;
* the chevron opens a sheet of tags already used in the book
  (`tagSuggestionsProvider` = the `tags` table ∪ every `tags_json` in the
  ledger), with tags already on this transaction filtered out;
* the value handed to the write path is still the stored JSON-array string, so
  `Transaction.tagsJson` / `toJsonApi` needed no change.

**Tested.** `test/ui/tag_input_test.dart` **8/8** (enter commits, comma
commits, duplicates ignored, existing value renders as chips and can be
removed, backspace removes the last chip, tapping the empty field focuses it,
error text renders). On device: `card` renders as a chip on the edit form,
typing `night` + enter produced a second chip, and the chevron listed the
book's real tags (`added-to-balance`, `bill:*`, `bulk-buy`, …). The edit was
discarded, so nothing was written.

## R34 — A currency could only be entered as free text

**Date.** 2026-11-18 (Firefly-parity session).

**What broke.** Every `currencyCode` / `foreignCurrencyCode` field was a text
input, so a typo (`EURO`, `usd`) produced a transaction the server rejected or
stored against the wrong currency. Firefly offers a dropdown of the book's
currencies.

**Fix.** All currency fields on transactions (amount currency and foreign
currency) and on accounts, budgets, budget limits, bills, piggy banks,
recurrences and subscriptions are now `FieldKind.reference` against
`currencyRefOptionsProvider`, i.e. a dropdown of currencies that exist in the
book — no free text.

**Tested.** The device edit form shows `EUR` and `GBP` as dropdowns; the
existing form tests still pass (554 tests overall).

## R35 — Currencies were read-only, so a custom currency could not be added at all

**Date.** 2026-11-18 (Firefly-parity session).

**What broke.** `currenciesConfig` was marked `canWrite: false` with no fields,
a leftover from the assumption that the API has no client write endpoints for
currencies. Firefly's own Currencies page lets you add a currency (BTC, a
loyalty point, a token); the phone could not, so no custom currency could ever
be created from the app.

**Fix.** `currenciesConfig` is writable again (code, name, symbol, decimal
places, enabled, default, rate) and `Settings → Currency & conversion →
Currencies` opens it. The write path already existed
(`CurrencyRepository`, `payloadOf: toJsonApi`) — only the UI gate was wrong.

**Tested.** `entity_form_screen_test.dart` now opens the production
`currenciesConfig` and asserts the Code/Name inputs and Save button are
present (it previously asserted the read-only banner). No currency was created
on the live book.

## R36 — No way to give a custom currency an exchange rate in both directions

**Date.** 2026-11-18 (Firefly-parity session).

**What broke.** Rates came only from the online feed (fawazahmed0), which has
no entry for a currency the user invented, so a BTC amount could not be
converted to anything and the secondary-amount display stayed blank.

**Fix.** `Settings → Currency & conversion → Exchange rates` (new
`ExchangeRatesScreen`) enters a pair by hand, in both directions, the way
Firefly does: `1 BTC = 65000 USD` and `65000.34 USD = 1 BTC` are stored as two
independent entries (`CurrencyDisplaySettings.manualRates`,
`{FROM: {TO: rate}}` in `device_meta.exchange_rates_manual`) and both are
honoured exactly as typed — the second is *not* forced to be the reciprocal of
the first. Typing one side pre-fills the other with its reciprocal until it is
edited. Manual rates are consulted before the online cache
(`convert()` → `manualRate()`), work offline, survive a rates refresh (separate
key), and can be edited or deleted per pair.

**Tested.** `test/core/exchange_rates_manual_test.dart` **5/5**: each
direction uses the typed rate (65,000 USD vs 65,000.34 USD → 1 BTC), manual
wins over the cached rate, a one-way entry converts via its reciprocal, an
empty online cache still converts (offline), lookup is case-insensitive and
unknown pairs return null. On device a pair was added (1 AED = 3.6725 USD
auto-filled 1 USD = 0.27229408 AED), listed in both directions, then deleted.

## R37 — Firefly's transaction "Options" fields were dropped, and a phone edit cleared them server-side

**Date.** 2026-11-18 (Firefly-parity session).

**What broke.** Firefly's transaction form carries five extra dates
(`interest_date`, `book_date`, `process_date`, `due_date`, `payment_date`) plus
`external_url`, `internal_reference` and `order`. The schema had no columns for
them, so the pull threw them away; because Firefly replaces the journal on a
write, editing any such transaction on the phone silently cleared those fields
on the website. Even where the values were empty the form was missing eight
fields the website shows.

**Fix.** Schema **v4** adds the eight columns (`transactions.interest_date`,
`book_date`, `process_date`, `due_date`, `payment_date`, `external_url`,
`internal_reference`, `order_index`) and clears `remote_updated_at` once so the
next pull backfills them (same reasoning as v3). `Transaction` stores and
round-trips all eight (`fromJsonApi` / `fromRow` / `toJsonApi` / `toRow`) and the
transaction form exposes them.

**Note on the one-off badge.** The backfill legitimately changed content
(`order_index` NULL → 0), so the first pull badged all 553 legs `conflict`.
The `_healStaleConflict` pass from R32 cleared them on the next sync: the
pulled DB went 553 `conflict` → 553 `synced` (and accounts 118 `synced`), with
no content change in between.

**Tested.** `app_database_test.dart` asserts the new columns exist on a fresh
install (v1 create + v2/v3/v4 migrations); `transaction_test.dart` pins the
`Options` block through both round trips and updates the expected JSON:API key
set; the full suite is **554 tests, all passing**; `flutter analyze lib` has 0
errors. On device the edit form shows all eight fields, the sync log reported
`Pull ~553 changed`, and `scripts/verify_sync_parity.py` still reports
`EXACT MATCH` (551 groups / 553 legs / 118 accounts, 0 field differences,
0 order differences, all balances equal).

---

## R38 — A failed push cancelled the pull, so website-side deletions never arrived

**Date.** 2026-11-19 (deletion-convergence session).

**What broke.** An account deleted on the website stayed on the phone, even after
"Get from website". Reproduced from the engine: `SyncEngine.sync()` ran push
first and, if *any* queued op failed to replay, returned **before** the pull
(`_pullAll`) ever ran. A queued op that referenced the deleted row (or any op
the server rejects) therefore blocked the only phase that could have learned
about the deletion, and it did so on every future sync: the phone never
converged again.

**Fix.** `sync()` now always pulls after the push, and reports both failures
when both fail. The one exception is a **transport** failure (`NetworkFailure`)
on push — the socket is down, so every pull request would fail the same way
after its own retry budget; that case still skips the pull so a dead network
does not make the failed sync slow. Server-side push failures (404/422/409) now
always pull.

**Tested.** `sync_engine_test.dart`: the two old pins ("push failure skips
pull") are rewritten; the new pin seeds a `synced` row the server no longer
lists plus a rejected op, runs one `sync()`, and asserts the cycle still reports
the push failure **and** the row is tombstoned. The transport case asserts only
the currencies list was attempted.

## R39 — One failing entity aborted the whole pull

**Date.** 2026-11-19 (deletion-convergence session).

**What broke.** `PullEngine.pullAll()` returned on the first `Err` from any of
the 13 entity types. Any single bad endpoint — a 500 on `budgets`, a 404 for the
limits of a budget deleted on the website — meant every later entity was never
pulled, including `accounts` and `transactions`, which is where deletions show
up. The tombstone pass of the failed entity was skipped too.

**Fix.** `pullAll()` records a failed entity in `PullStats.failures` and keeps
walking. A `NetworkFailure` / `AuthFailure` still stops the walk (global
conditions: every request would fail identically), and the cycle is still
reported as failed through `PullStats.firstFailure`, so the sync log shows the
partial outcome with its counters. `budget_limits` also treats a 404 from
`budgets/{id}/limits` as "that budget is gone" and skips it. The UI now refreshes
after a partial pull as well (`mode != 'push'`), because those entities did
merge.

**Tested.** `pull_engine_test.dart`: "pullAll keeps pulling other entities after
one fails" (currencies 500 → accounts and transactions still pulled, the failed
entity's rows untouched); the budget-limits 404 path is exercised by the sync
engine suite. `settings_sync_test.dart` now fails a single list path.

## R40 — Tombstones ignored `conflict` rows and `pending` rows, so a deleted row could be immortal

**Date.** 2026-11-19 (deletion-convergence session).

**What broke.** `_tombstoneUnseen` only selected `sync_status = 'synced'`
rows. Two states were therefore never cleaned up when the server dropped a row:

* **`conflict`** — a row the server won on a previous pull. The badge is
  informational, but it made the row immune to the server's own deletion, so a
  website-side delete left a red-triangle row on the phone forever.
* **`pending`** — a row with a queued edit whose server copy was deleted. The
  pull skipped it (correctly: local wins over an *update*), then the push
  replayed the op against a missing id, got 404/422, and stopped every future
  sync. Nothing in the design could ever resolve that state.

**Fix.** Candidates are now every row with a `firefly_id` (`deleted_at IS NULL
OR sync_status = 'pending'`). `synced` and `conflict` rows are soft-deleted;
`pending` rows are resolved to the server's truth — the row is `DELETE`d and
its `op_log` entries are dropped in the same transaction (the op can never
succeed, and a half-pushed tombstone would linger). A row with **no**
`firefly_id` is a local-only create and is never touched.

**Tested.** `pull_engine_test.dart`: a `conflict` row absent from the list is
tombstoned; a `pending` row with a queued op absent from the list is removed
with its op; a local-only row and an already-tombstoned row are left alone.

## R41 — A 404 on push wedged the queue instead of resolving it

**Date.** 2026-11-19 (deletion-convergence session).

**What broke.** `_replayUpdate` returned the `NotFoundFailure` from
`PUT /{entity}/{id}` as a batch failure. Because the push runs before the pull
and a failed op is retried forever, one edit to a row deleted on the website
failed every sync from then on (each cycle stopped at push), and the sync log
filled with the same 404.

**Fix.** A 404 on update now means "the server no longer has this row": the
local row and all of its queued ops are removed (server is the authority on
existence — recreating it would resurrect data the user deliberately deleted),
the op is acknowledged, and the batch continues. Deletes already treated 404 as
success; the same rule now covers updates.

**Tested.** `op_log_pusher_test.dart`: an update that answers 404 leaves the
category table and the op log empty and reports `PushOutcome.allOk`.

## R42 — The Dashboard/Reports kept showing a deleted account; end-to-end deletion proof

**Date.** 2026-11-19 (deletion-convergence session).

**What broke.** After a successful pull, Settings invalidated
`allEntityListProviders` only. The Dashboard and Reports read
`ledgerTransactionsProvider` / `ledgerAccountsProvider` (whole-history sums), so
an account the website had just deleted stayed on the Dashboard — with its
balance in net worth — until the app was restarted.

**Fix.** New `allSyncedDataProviders` = the entity lists + both ledger providers
+ `tagSuggestionsProvider`; Settings invalidates that full set after any pull
(directional or full, complete or partial).

**Proof end to end.** New `test/data/sync/server_deletion_test.dart` runs the
**committed, verbatim Firefly fixtures** (`test/fixtures/api/accounts.json`,
`transactions.json`) through the real `FireflyApiClient` and the real schema:
pull the server's list, then serve it again minus one account (and minus one
transaction group) and assert the rows disappear from the production
visibility rule (`EntityDao.getAll`) while staying readable with
`includeDeleted: true` for the merge.

**State on the real book.** The user deleted test account `204
MOBILE_TEST_3_GBP` on the website; the server now reports **116 accounts / 549
groups / 551 legs** (was 118/551/553 — the account, its initial-balance
companion and the two legs that touched it). After "Get from website" on the
fixed build the phone must show exactly that, with the two accounts and two legs
soft-deleted locally.

---

## R43 — A "did the list arrive completely?" guard must not trust Firefly's `total` for transactions

**Date.** 2026-11-19 (deletion-convergence session).

**What broke.** While verifying R40–R42 against the live book, a new guard
("never tombstone from a truncated list") compared the number of members
received with `meta.pagination.total`. Firefly's `/transactions` reports
`total: 551` but serialises only **549** groups (its count includes rows it does
not return), and its last page is short. The guard therefore classified every
transaction pull as truncated, skipped the deletion pass for the one entity
where deletions matter, and reproduced the original bug: accounts converged,
deleted legs stayed.

**Fix.** The truncation signal is a **full last page** plus fewer members than
`total` — the shape of a lying `total_pages`. A short last page is a complete
read even when `total` is inflated. Pinned by two tests: 100 members on a
`per_page: 100` page with `total: 250, total_pages: 1` is rejected
(`pull.incomplete-list`, no tombstone); one member with `total: 5` is accepted
and tombstones.

**Verified on the real book.** `test/manual/deletion_convergence_manual_test.dart`
(env-gated, skipped in CI) opens a **copy** of the actual device database pulled
before the fix (`118 accounts / 553 legs`), runs the real
`PullEngine.pullAll()` against the live server, and prints:

```
accounts:      skippedUnchanged 116, tombstoned 2
transactions:  skippedUnchanged 551, tombstoned 2
after: {accounts: 116, legs: 551}
tombstoned accounts: 205 Initial balance for "MOBILE_TEST_3_GBP", 204 MOBILE_TEST_3_GBP
tombstoned legs:     3486 Parity M2W 002, 3487 Parity M2W 003
```

`scripts/verify_sync_parity.py` on the converged database: **EXACT MATCH**
(551 legs, 116 accounts, 0 missing, 0 extra, 0 field differences, 0 order
differences, balances equal). No other row changed.

---

## R44 — Live device proof of website→phone deletion (probe transaction)

**Date.** 2026-11-19, on the real handset (`LDN-L21`, APK built from R38–R43).

**What was done.** Reproduced the reported scenario end to end instead of trusting
the headless harness:

1. Created `CONVERGENCE_PROBE_DELETE_ME` (1.00 EUR) on the **website** inside the
   test account `202 WEB_SYNC_TEST_2_EUR` via the API → group 3486 / journal 3488.
2. Phone → Settings → **Sync website → phone**: `pull` log `inserted 1`;
   device went 551 → 552 legs, the probe row present.
3. Deleted the group on the website via the API (`204`, then `404`).
4. Phone → **Sync website → phone** again: snackbar
   `Received from website: +0 new, ~0 updated, −1 removed`; `pull` log
   `inserted 0, tombstoned 1`; device back to **551 legs**, probe row
   `deleted_at` set, `op_log` empty (nothing left to replay, nothing resurrected).

**Parity after the round trip.** `scripts/verify_sync_parity.py` on the pulled
device database: **EXACT MATCH** — 551 legs, 116 accounts, 0 missing, 0 extra,
0 field differences, 0 ordering differences, all balances equal.

**Earlier evidence.** The account deletion the user actually performed
(`204 MOBILE_TEST_3_GBP`) had already converged on the device
(`deleted_at` 2026-11-18T19:52Z, accounts 118 → 116) together with its two legs
(`3486 Parity M2W 002`, `3487 Parity M2W 003`), leaving every other row
untouched — the tombstone pass now reaches rows that the old code skipped.

---

## R45 — Bills, subscriptions and rules read wire keys Firefly never sends

**Date.** 2026-11-19, on the real book (116 accounts, 552 legs, 5 bills,
5 subscriptions, 2 rules).

**Symptom.** The user's report ("it still doesn't sync — it must match every
detail") was invisible in the transaction and account audit, which read
`EXACT MATCH`. A new all-entity audit (`scripts/audit_entity_parity.py`, every
modelled field of every entity) found 15 differences, all of them in bills and
subscriptions, plus two silent ones it could not see:

| Entity | Phone showed | Website had | Cause |
| --- | --- | --- | --- |
| bills | `amount` `0` | `15.99`, `39.99`, … | app read `amount`; Firefly sends `amount_min` / `amount_max` / `amount_avg` and **no** `amount` |
| bills | next due date missing | `date` | the schema had no column for it |
| subscriptions | title `''` | `Netflix`, `Spotify`, … | app read `title`; the endpoint serialises the **bill** shape and sends `name` |
| subscriptions | `amount` `0` | `15.99` | same `amount_min` bug |
| subscriptions | next date `null` | `2026-11-26` | app read `next_date`; Firefly sends `date` |
| rules | `stop` always `false` | `stop_processing` | app read `stop` |

The write side was broken the same way, which is why nothing ever healed it: the
bill/subscription endpoints (`BillStoreRequest`, reached through both
`/v1/bills` and `/v1/subscriptions`) *require* `amount_min`, `amount_max`,
`transaction_currency_id` and `date`, while the app sent `amount`, `currency_id`
and (for subscriptions) `title`. Every phone-side edit of a bill or
subscription could only ever 422.

**Fix (parsing and payloads, no data patch).**

* `Bill`: `amount` ← `amount_min` ?? `amount` ?? `amount_avg`; new `date` field
  parsed from `date`; push emits `amount_min` + `amount_max` (same figure twice
  for an exact-amount bill), `transaction_currency_id` and `date`.
* `Subscription`: `title` ← `name` ?? `title`; `amount` ← `amount_min` ??
  `amount` ?? `amount_avg`; `nextDate` ← `date` ?? `next_date`; push emits
  `name`, `amount_min`, `amount_max`, `transaction_currency_id`, `date`. The old
  keys stay readable so payloads from an older build still land.
* `Rule`: `stop` ← `stop_processing` ?? `stop`; push emits `stop_processing`.
* Schema **v5** adds `bills.date` (TEXT) and clears the bill LWW cursor so the
  next pull backfills it. The column is deliberately not added to the v1
  `CREATE TABLE` — a fresh install replays every migration in order and would
  fail with "duplicate column name: date" (this caught 136 failing tests before
  the build).
* Bills form gained a required **Next due date** field (seeded to today on
  create) so a bill created on the phone satisfies the endpoint, and an edit
  preserves the pulled date instead of clearing it.

**Proof.** Unit tests 563 passing (`flutter test`), `flutter analyze lib` 0
errors; entity round-trip tests now pin the real wire shape (`name`,
`amount_min`, `amount_max`, `date`, `stop_processing`). Live server payloads
re-read after the change:

```
subscriptions: name=Rent amount_min=950 date=2026-11-15T00:00:00+05:00 next_date=None amount=None
bills:         name=Rent amount_min=950 date=2026-11-15T00:00:00+05:00 amount=None
rules:         stop_processing=False
```

**Still not mirrored (deliberate).** `group_title` on the 3 legs the website
groups, `currencies.rate` / `symbol_first` (server never sends them; Firefly's
own EUR→X table lives at `/api/v1/exchange-rates` and is a separate feature),
and `/exchange-rates` itself. Everything the app models is now read from the
key Firefly actually sends.

---

## R46 — A parser fix never reaches rows the pull treats as unchanged (v6)

**Date.** 2026-11-20, on the real book and the real phone (Huawei LDN-L21,
Android 8, `com.firefly.firefly_mobile`).

**Symptom.** The R45 build was installed on the phone and "Sync website → phone"
was run: bills came out right (`Rent 950`, `Netflix 15.99`, `Internet 39.99`,
dates present), but all five subscriptions were still `title ''`, `amount 0`,
`next_date null` — on the exact build that produced a correct result when the
same pull was replayed against a hand-migrated copy of the device database.

**Cause.** The pull is incremental on purpose: it compares each row's
`remote_updated_at` with the server's `updated_at` and skips rows that are
equal. Rows mirrored *before* the parser fix already carry the server's current
timestamp, so they were classified as unchanged, the parser never ran on them,
and the bad values stayed. Schema v5 cleared the cursor for `bills` only, which
is exactly why bills healed and subscriptions did not. This is the general trap:
**fixing a parser is invisible to every row the LWW cursor considers current.**

**Fix.** Schema **v6** (`_invalidateSubscriptionAndRuleCursor`) sets
`remote_updated_at = NULL` on `subscriptions` and `rules`, forcing one full
re-read of both tables on the next pull. The statements were added as a *new*
version rather than appended to v5 because the phone had already run v5 —
a device sits at whatever version it last opened, so only a higher version runs.

**Rule for the future.** Any change to how a field is parsed, or to the payload
a phone-side write produces, ships together with a migration that invalidates
the LWW cursor of the affected table. Otherwise the change is only ever seen on
rows the server later touches for unrelated reasons.

**Proof, on the device (not a copy).** After `pm install -r`, one "Sync website
→ phone", and a pull of `databases/firefly.db`:

```
user_version            6
bills                   5 rows, all with amount + date
subscriptions           Internet 39.99 / Mobile Plan 25 / Netflix 15.99 /
                        Rent 950 / Spotify 10.99, all with next_date
rules                   2 rows
audit_entity_parity.py  RESULT: EXACT MATCH (every entity, every modelled field)
verify_sync_parity.py   RESULT: EXACT MATCH (552 legs, 116 accounts, balances equal)
```

**Operational note.** `adb install` streamed-install failed repeatedly with an
empty error and the device dropping off the bus mid-transfer (kernel:
`usb usb1-port2: Cannot enable. Maybe the USB cable is bad?`). Installing from
the device's own filesystem works reliably:

```bash
flutter build apk --debug --target-platform android-arm64   # 171 MB vs 204 MB
adb push build/app/outputs/flutter-apk/app-debug.apk /data/local/tmp/ff.apk
adb shell pm install -r /data/local/tmp/ff.apk
```
