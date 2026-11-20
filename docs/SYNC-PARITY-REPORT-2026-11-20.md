# Sync parity report — website → phone, 2026-11-20

This is the full record of the "it still doesn't sync" work: what the goal was,
what was actually wrong, everything that was tried (including what did not
work), what was changed, and the evidence that the phone now mirrors the
website. Regression entries R38–R46 in `docs/REGRESSION-LOG.md` are the
per-defect versions of this; this file is the narrative.

---

## 1. Goal and definition of done

The user's words: *"when I sync it means it matches every single detail on every
single transaction, accounts and everything else like currencies, etc"* — and
*"don't change, delete, create anything anywhere but except on the 3 test
accounts so my data remains safe"*.

So "synced" was defined as:

* every modelled field of every entity the app stores equals the website's value
  after one pull — transactions, accounts, currencies, categories, tags,
  budgets, bills, subscriptions, rules, rule groups, piggy banks, recurrences,
  attachments;
* website-side **deletes** and **edits** also land (not just new rows);
* nothing is fixed by editing rows by hand — the app must reach that state from
  the server payload alone, because the server is the source of truth;
* the user's real data is never modified to make a check pass; probe rows are
  created only on the test accounts (200 USD, 202 EUR, 204 deleted) and cleaned
  up afterwards.

"Matches" was deliberately read as *field-by-field*, not *row-count equal*:
row counts were already equal for months while bills showed `0` and
subscriptions showed blank titles.

---

## 2. How parity is actually measured

Three tools, each answering a different question:

| Tool | Question it answers |
| --- | --- |
| `scripts/verify_sync_parity.py` | are all transaction legs + accounts present, are amounts/dates/ids equal, do asset balances match, does the app's sort order match? |
| `scripts/audit_entity_parity.py` | for **every** entity and **every** modelled field: does server value == phone value? |
| `app/test/manual/deletion_convergence_manual_test.dart` | does a row deleted on the website disappear locally after a pull (env-gated, `VERIFY_DB=…`)? |

Both scripts take `--db` and `--token-file` and compare the local SQLite file
against the live Firefly API, printing `RESULT: EXACT MATCH` only when nothing
differs.

The all-entity audit had to be *written* during this work, and that matters:
the two scripts that existed before (transactions/accounts only) printed
`EXACT MATCH` while 15 real field differences were sitting in bills,
subscriptions and rules. A passing check that covers half the data is worse than
no check.

---

## 3. What was wrong

### 3.1 Deletions and edits were skipped (R38–R44)

Earlier work in this thread: pushes of locally deleted rows got 404s that were
treated as fatal, `conflict`/`pending` rows were left alive after the server had
already removed the row, one failing entity aborted the whole pull, and the
"did the page arrive whole?" guard trusted Firefly's `total` field. Those were
fixed (tombstone pass + per-entity resilience + a completeness guard keyed on a
full last page), and proved live: a probe transaction on account 204 was deleted
on the website and disappeared from the phone, accounts going 118 → 116 with
only the probe legs affected.

### 3.2 Bills, subscriptions and rules read keys Firefly never sends (R45)

| Entity | Phone showed | Website had | Real cause |
| --- | --- | --- | --- |
| bills | `amount 0` | `15.99`, `39.99`, … | app read `amount`; Firefly sends `amount_min`/`amount_max`/`amount_avg` and no `amount` |
| bills | no due date | `date` | the column did not exist locally |
| subscriptions | title `''` | `Netflix`, `Spotify`, … | `/v1/subscriptions` serialises the **bill** shape and sends `name` |
| subscriptions | `amount 0` | `15.99` | same `amount_min` bug |
| subscriptions | `next_date null` | `2026-11-26` | app read `next_date`, Firefly sends `date` |
| rules | `stop` always `false` | `stop_processing` | app read `stop` |

The write direction was broken the same way, which is why nothing ever healed:
`BillStoreRequest` (shared by `/v1/bills` and `/v1/subscriptions` — verified in
the server's own source) **requires** `amount_min`, `amount_max`,
`transaction_currency_id` and `date`, while the app sent `amount`,
`currency_id`, and `title` for subscriptions. Any phone-side bill or
subscription edit could only 422.

Fix, at parse/payload level only, old keys kept as fallbacks:

* `Bill` — `amount` ← `amount_min` ?? `amount` ?? `amount_avg`; new `date`;
  push sends `amount_min`+`amount_max`, `transaction_currency_id`, `date`.
* `Subscription` — `title` ← `name` ?? `title`; `amount` ← `amount_min` ?? …;
  `nextDate` ← `date` ?? `next_date`; push sends `name`, `amount_min/max`,
  `transaction_currency_id`, `date`.
* `Rule` — `stop` ← `stop_processing` ?? `stop`; push sends `stop_processing`.
* Schema **v5** adds `bills.date` and clears the bill LWW cursor.
* Bills form gained a required **Next due date** (seeded to today on create) so a
  phone-created bill satisfies the endpoint.

### 3.3 The fix did not appear on the phone (R46)

After installing the v5 build, bills were right but subscriptions were still
blank — 5 × (`''`, `0`, `null`). This was the most instructive failure of the
whole thread, because the same build produced a perfect result against a
hand-migrated copy of the *same* database.

Cause: the pull is incremental. It compares each row's `remote_updated_at` with
the server's `updated_at` and skips equal rows. Rows mirrored before the parser
fix already carried the server's current timestamp, so they were "unchanged" and
the parser never ran. v5 cleared the cursor for `bills` only.

Fix: schema **v6** (`_invalidateSubscriptionAndRuleCursor`) nulls
`remote_updated_at` on `subscriptions` and `rules`. Added as a new version, not
appended to v5, because the phone had already executed v5 and a device only runs
versions above its current `user_version`.

**Rule extracted:** any parser or payload change must ship with a migration that
invalidates the LWW cursor of the affected table. Without it, the fix is visible
only on rows the server later touches for unrelated reasons.

---

## 4. Things that were tried and did not work (kept here on purpose)

1. **Checking transactions and accounts only.** Both scripts read
   `EXACT MATCH` for weeks while bills/subs/rules were wrong. Lesson: the audit
   must enumerate every entity, and it must be re-run *after* every fix.
2. **Patching rows to match the website.** Rejected on the user's data-safety
   requirement and for the right reason: it would drift again on the next pull
   and would have hidden the wire-key bug. Every change ended up in the parser
   or the migration instead.
3. **Trusting row counts.** Counts matched (5 bills, 5 subs, 2 rules) while all
   their values were wrong.
4. **Proving a client fix against a database copy.** The `/tmp` copy was
   migrated by hand (v4 → v5 by `sqlite3`), which ran the cursor-clearing
   statement that the real device had already passed. The copy said EXACT
   MATCH, the phone still showed blanks. Lesson: migrations must be proved by
   upgrading a database at the *old version*, not one you prepared to look like
   a new one, and the final check belongs on the device.
5. **Appending the cursor clears to v5.** Would have been a no-op on the phone.
   Only a higher `user_version` runs.
6. **Adding `date` to the v1 `CREATE TABLE`.** A fresh install replays every
   migration in order, so v5's `ALTER TABLE bills ADD COLUMN date` then failed
   with "duplicate column name: date" — this broke 136 tests in one run. The
   v1 table stays as shipped; new columns live only in their migration.
7. **`adb install` (streamed install).** Failed repeatedly with an empty error
   while the device dropped off the USB bus mid-transfer (kernel:
   `usb usb1-port2: Cannot enable. Maybe the USB cable is bad?`). Distance did
   not help: the 204 MB universal debug APK was the problem as much as the
   cable. Working procedure, now in OPERATIONS.md:

   ```bash
   flutter build apk --debug --target-platform android-arm64   # 171 MB
   adb push build/app/outputs/flutter-apk/app-debug.apk /data/local/tmp/ff.apk
   adb shell pm install -r /data/local/tmp/ff.apk
   ```
8. **`adb kill-server && adb start-server`** was needed twice when the phone
   showed on `lsusb` as `12d1:107d` but `adb devices` was empty.

---

## 5. Data safety

* No production row was edited, created or deleted by the app changes. The only
  writes to the live book were probe rows on the test accounts (200 USD, 202
  EUR), all removed again; test journal 3489's description was restored to
  `test` via `PUT /api/v1/transactions/3487` (200 → 202).
* `device_meta` and the Keystore-held database key were never wiped. The v5/v6
  migrations only null `remote_updated_at` so the next pull re-reads rows.
* `Restore from server` (which erases local records) was **not** used. The pull
  path heals the rows on its own.
* The definitive checks were read-only: copy `databases/firefly.db` (+ `-wal`,
  `-shm`) out and compare against the API.

---

## 6. Final state, verified on the device

Phone: Huawei LDN-L21 (`26EBB18620154875`), Wi-Fi reachable to
`http://192.168.18.136:8080`, app data preserved across the upgrade.

After `pm install -r` and one "Sync website → phone":

```
user_version            6
bills                   Internet 39.99 / Mobile Plan 25 / Netflix 15.99 /
                        Rent 950 / Spotify 10.99   (all with date)
subscriptions           same five, correctly titled, priced, with next_date
rules                   2 rows

audit_entity_parity.py  currencies 42=42, accounts 116=116, categories 29=29,
                        tags 52=52, budgets 4=4, bills 5=5, subscriptions 5=5,
                        rules 2=2, rule_groups 2=2
                        RESULT: EXACT MATCH (every entity, every modelled field)

verify_sync_parity.py   server 550 groups / 552 legs, device 552 live legs,
                        missing 0, extra 0, field differences none,
                        order differs in 0 positions, 116 accounts,
                        all asset balances match
                        RESULT: EXACT MATCH
```

Build checks: `flutter test` → **563 passing**, `flutter analyze lib` → 0
errors.

## 7. Known, deliberate gaps

* `group_title` on the 3 legs the website groups — Firefly sends it per leg, the
  local table has no column for it.
* `currencies.rate` / `symbol_first` — not in Firefly's currency payload; the
  rate table lives at `/api/v1/exchange-rates`, unused by the app (the app uses
  the external fawazahmed0 exchange-api for secondary-currency display).
* Multi-currency *converted* totals are computed for display and are not
  expected to equal the website's own conversion.

## 8. Reproducing all of this

```bash
# device database
adb shell "run-as com.firefly.firefly_mobile cat databases/firefly.db"  > /tmp/d/firefly.db
adb shell "run-as com.firefly.firefly_mobile cat databases/firefly.db-wal" > /tmp/d/firefly.db-wal

python3 scripts/audit_entity_parity.py --db /tmp/d/firefly.db --token-file <token>
python3 scripts/verify_sync_parity.py --db /tmp/d/firefly.db --token-file <token>

cd app && /mnt/data/opencode/tools/flutter/bin/flutter test
```

## 9. Repo state

All of this is **uncommitted** (`git status`: modified `app/lib/domain/entities/
{bill,subscription,rule}.dart`, `app/lib/data/db/schema.dart`,
`app/lib/ui/configs/entity_configs.dart`, plus generated freezed files and
tests; new `scripts/*.py`, this report, R45/R46 in `docs/REGRESSION-LOG.md`).
