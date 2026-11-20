#!/usr/bin/env python3
"""Field-by-field parity check between Firefly III and the phone's database.

The phone is a mirror: every journal leg the server holds should exist locally
with the same values, and the list the app shows should follow the server's
order. This script pulls the server over the API, reads a copy of the device
database (WAL must be merged, see --db) and reports every difference.

Usage:
    python3 scripts/verify_sync_parity.py --db /tmp/cdb/firefly.db \
        --token-file "/path/to/token.txt" [--base http://localhost:8080] \
        [--json out.json]

Exit status is 0 when the mirror is exact, 1 when anything differs.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import urllib.request
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

# Fields the phone schema models, as (local row key, server journal key).
SCALAR_FIELDS = [
    ("type", "type"),
    ("description", "description"),
    ("amount", "amount"),
    ("currency_code", "currency_code"),
    ("currency_id", "currency_id"),
    ("source_account_id", "source_id"),
    ("dest_account_id", "destination_id"),
    ("source_name", "source_name"),
    ("dest_name", "destination_name"),
    ("category_id", "category_id"),
    ("category_name", "category_name"),
    ("budget_id", "budget_id"),
    ("budget_name", "budget_name"),
    ("bill_id", "bill_id"),
    ("bill_name", "bill_name"),
    ("notes", "notes"),
    ("foreign_amount", "foreign_amount"),
    ("foreign_currency_code", "foreign_currency_code"),
    ("external_id", "external_id"),
]

# Server keys the schema has no column for. Counted so their blast radius is
# visible instead of silently assumed empty.
UNSTORED_KEYS = [
    "internal_reference", "external_url", "original_source",
    "sepa_cc", "sepa_ct_op", "sepa_ct_id", "sepa_db", "sepa_country",
    "sepa_ep", "sepa_ci", "sepa_batch_id", "interest_date", "book_date",
    "process_date", "due_date", "payment_date", "invoice_date", "longitude",
    "latitude", "zoom_level", "recurrence_id", "subscription_id",
]


def fetch_all(base: str, token: str, path: str, extra: str = "") -> list[dict]:
    """Returns every resource of a paginated collection, in server order."""
    out: list[dict] = []
    page = 1
    while True:
        url = f"{base}/api/v1/{path}?limit=100&page={page}{extra}"
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.load(resp)
        out.extend(body["data"])
        pagination = body["meta"]["pagination"]
        if page >= pagination["total_pages"]:
            return out
        page += 1


def dec(value) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except InvalidOperation:
        return None


def instant(value) -> datetime | None:
    if not value:
        return None
    text = str(value).replace("Z", "+00:00")
    return datetime.fromisoformat(text)


def tags_of(local_json) -> list[str]:
    if not local_json:
        return []
    try:
        loaded = json.loads(local_json)
    except json.JSONDecodeError:
        return [local_json]
    return sorted(str(t) for t in loaded)


def server_legs(groups: list[dict]) -> list[dict]:
    """Flattens transaction groups into legs, preserving server order."""
    legs = []
    for group in groups:
        attributes = group["attributes"]
        for index, journal in enumerate(attributes.get("transactions") or []):
            legs.append(
                {
                    "group_id": str(group["id"]),
                    "group_title": attributes.get("group_title"),
                    "group_updated_at": attributes.get("updated_at"),
                    "order": index,
                    "journal": journal,
                }
            )
    return legs


def compare_leg(server: dict, local: dict) -> dict[str, str]:
    """Returns {field: description} for every difference on one leg."""
    journal = server["journal"]
    diffs: dict[str, str] = {}

    if str(local["firefly_id"]) != server["group_id"]:
        diffs["firefly_id"] = f"{local['firefly_id']} != {server['group_id']}"

    server_date = instant(journal.get("date"))
    local_date = instant(local["date"])
    if server_date != local_date:
        diffs["date"] = f"{local['date']} != {journal.get('date')}"

    for local_key, wire_key in SCALAR_FIELDS:
        want = journal.get(wire_key)
        have = local[local_key]
        if wire_key in ("amount", "foreign_amount"):
            if dec(have) != dec(want):
                diffs[local_key] = f"{have!r} != {want!r}"
            continue
        if (have if have != "" else None) != (want if want != "" else None):
            diffs[local_key] = f"{have!r} != {want!r}"

    if bool(local["reconciled"]) != bool(journal.get("reconciled")):
        diffs["reconciled"] = f"{local['reconciled']} != {journal.get('reconciled')}"

    want_tags = sorted(str(t) for t in (journal.get("tags") or []))
    have_tags = tags_of(local["tags_json"])
    if have_tags != want_tags:
        diffs["tags"] = f"{have_tags} != {want_tags}"

    return diffs


def money_strings_differ(server: dict, local: dict) -> list[str]:
    """Numeric-equal but textually different decimals (cosmetic drift)."""
    notes = []
    for key in ("amount", "foreign_amount"):
        want = server["journal"].get(key)
        have = local[key]
        if want is None and have is None:
            continue
        if dec(have) == dec(want) and str(have) != str(want):
            notes.append(f"{key}: local {have!r} vs server {want!r}")
    return notes


def local_balances(conn: sqlite3.Connection) -> dict[str, Decimal]:
    """Opening balance plus every leg, in each account's own currency.

    Mirrors `accountBalance()` in the app: a leg counts in the account's own
    currency, using `foreign_amount` when the leg's currency is a different one.
    """
    accounts = {
        str(row["firefly_id"]): row
        for row in conn.execute(
            "SELECT firefly_id, currency_code, opening_balance FROM accounts "
            "WHERE deleted_at IS NULL AND firefly_id IS NOT NULL"
        )
    }
    balances = {
        key: dec(row["opening_balance"]) or Decimal(0)
        for key, row in accounts.items()
    }
    rows = conn.execute(
        "SELECT type, amount, currency_code, foreign_amount, "
        "foreign_currency_code, source_account_id, dest_account_id "
        "FROM transactions WHERE deleted_at IS NULL"
    )
    for row in rows:
        amount = dec(row["amount"]) or Decimal(0)
        foreign = dec(row["foreign_amount"])
        for side, sign in (("source_account_id", -1), ("dest_account_id", 1)):
            account_id = row[side]
            if account_id is None or account_id not in accounts:
                continue
            currency = accounts[account_id]["currency_code"]
            if row["currency_code"] == currency or row["currency_code"] is None:
                value = amount
            elif row["foreign_currency_code"] == currency and foreign is not None:
                value = foreign
            else:
                value = amount
            balances[account_id] += sign * value
    return balances


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--base", default="http://localhost:8080")
    parser.add_argument("--json")
    parser.add_argument("--max-examples", type=int, default=8)
    args = parser.parse_args()

    token = Path(args.token_file).read_text().strip()
    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row

    groups = fetch_all(args.base, token, "transactions")
    server_accounts = fetch_all(args.base, token, "accounts")
    legs = server_legs(groups)
    local_rows = {
        str(row["journal_id"]): row
        for row in conn.execute(
            "SELECT * FROM transactions WHERE deleted_at IS NULL"
        )
    }

    report: dict = {}
    problems: list[str] = []

    print(f"server: {len(groups)} groups, {len(legs)} legs, "
          f"{len(server_accounts)} accounts")
    print(f"device: {len(local_rows)} live legs")

    missing = [leg for leg in legs
               if str(leg["journal"]["transaction_journal_id"]) not in local_rows]
    extra = [key for key in local_rows
             if key not in {str(l["journal"]["transaction_journal_id"])
                            for l in legs}]
    print(f"legs missing on phone: {len(missing)}  extra on phone: {len(extra)}")
    if missing:
        problems.append(f"{len(missing)} legs missing on phone")
        for leg in missing[:args.max_examples]:
            print("  missing", leg["journal"]["transaction_journal_id"],
                  leg["journal"].get("description"),
                  leg["journal"].get("date"))
    if extra:
        problems.append(f"{len(extra)} legs unknown to server")
        for key in extra[:args.max_examples]:
            row = local_rows[key]
            print("  extra", key, row["description"], row["date"])

    field_counts: dict[str, int] = {}
    examples: dict[str, list[str]] = {}
    cosmetic = 0
    for leg in legs:
        journal_id = str(leg["journal"]["transaction_journal_id"])
        local = local_rows.get(journal_id)
        if local is None:
            continue
        diffs = compare_leg(leg, local)
        cosmetic += len(money_strings_differ(leg, local))
        for field, text in diffs.items():
            field_counts[field] = field_counts.get(field, 0) + 1
            bucket = examples.setdefault(field, [])
            if len(bucket) < args.max_examples:
                bucket.append(f"{journal_id} {text}")

    if field_counts:
        print("\nfield differences (legs affected):")
        for field, count in sorted(field_counts.items(),
                                   key=lambda kv: -kv[1]):
            print(f"  {field:<22} {count}")
            for line in examples[field]:
                print(f"      {line}")
        problems.append(
            "field differences: " + ", ".join(
                f"{k}={v}" for k, v in sorted(field_counts.items())))
    else:
        print("\nfield differences: none (every modelled field matches)")

    if cosmetic:
        print(f"cosmetic decimal formatting differences: {cosmetic}")

    # --- order -------------------------------------------------------------
    server_order = [str(leg["journal"]["transaction_journal_id"]) for leg in legs]
    # The list provider's own ORDER BY (kTransactionListOrder in providers.dart).
    phone_dao_order = [str(row["journal_id"]) for row in conn.execute(
        "SELECT journal_id FROM transactions WHERE deleted_at IS NULL "
        "ORDER BY date DESC, CAST(journal_id AS INTEGER) DESC")]

    def first_mismatch(a: list[str], b: list[str]) -> int | None:
        for index, (left, right) in enumerate(zip(a, b)):
            if left != right:
                return index
        return None

    mismatched_positions = sum(
        1 for left, right in zip(server_order, phone_dao_order) if left != right)
    print(f"\norder: server {len(server_order)} legs; "
          f"app sort (date DESC, journal id DESC) differs in "
          f"{mismatched_positions} positions")
    if mismatched_positions:
        index = first_mismatch(server_order, phone_dao_order) or 0

        print(f"  first divergence at #{index}: server "
              f"{server_order[index]} vs phone {phone_dao_order[index]}")
        problems.append(f"list order differs in {mismatched_positions} positions")

    # --- accounts ----------------------------------------------------------
    local_accounts = {
        str(row["firefly_id"]): row for row in conn.execute(
            "SELECT * FROM accounts WHERE deleted_at IS NULL "
            "AND firefly_id IS NOT NULL")
    }
    account_diffs: dict[str, int] = {}
    account_examples: list[str] = []
    for account in server_accounts:
        a = account["attributes"]
        row = local_accounts.get(str(account["id"]))
        if row is None:
            account_diffs["missing"] = account_diffs.get("missing", 0) + 1
            account_examples.append(f"missing account {account['id']} {a['name']}")
            continue
        checks = {
            "name": (row["name"], a.get("name")),
            "type": (row["type"], a.get("type")),
            "currency_code": (row["currency_code"], a.get("currency_code")),
            "active": (bool(row["active"]), bool(a.get("active"))),
            "include_net_worth": (bool(row["include_net_worth"]),
                                  bool(a.get("include_net_worth"))),
            "notes": (row["notes"] or None, a.get("notes") or None),
        }
        for field, (have, want) in checks.items():
            if have != want:
                account_diffs[field] = account_diffs.get(field, 0) + 1
                if len(account_examples) < args.max_examples:
                    account_examples.append(
                        f"{account['id']} {a['name']} {field}: {have!r} != {want!r}")
        if dec(row["opening_balance"]) != dec(a.get("opening_balance")):
            account_diffs["opening_balance"] = \
                account_diffs.get("opening_balance", 0) + 1
            if len(account_examples) < args.max_examples:
                account_examples.append(
                    f"{account['id']} {a['name']} opening: "
                    f"{row['opening_balance']!r} != {a.get('opening_balance')!r}")

    print(f"\naccounts: server {len(server_accounts)}, device {len(local_accounts)}")
    if account_diffs:
        print("  account differences:",
              ", ".join(f"{k}={v}" for k, v in sorted(account_diffs.items())))
        for line in account_examples:
            print("     ", line)
        problems.append("account differences: " + json.dumps(account_diffs))
    else:
        print("  account fields: identical")

    balances = local_balances(conn)
    balance_bad = 0
    for account in server_accounts:
        if account["attributes"].get("type") != "asset":
            continue
        want = dec(account["attributes"].get("current_balance"))
        have = balances.get(str(account["id"]))
        if have is None:
            continue
        # Firefly rounds its own current_balance to the currency's precision,
        # so a sub-cent difference is the server's display rounding, not drift.
        if want is not None and abs(have - want) >= Decimal("0.01"):
            balance_bad += 1
            print(f"  balance {account['attributes']['name']}: "
                  f"phone {have} vs server {want}")
    if balance_bad:
        problems.append(f"{balance_bad} asset balances differ")
    else:
        print("  asset balances: all match")

    # --- unstored server fields -------------------------------------------
    non_empty: dict[str, int] = {}
    for leg in legs:
        for key in UNSTORED_KEYS:
            if leg["journal"].get(key) not in (None, "", []):
                non_empty[key] = non_empty.get(key, 0) + 1
    titled = sum(1 for leg in legs if leg["group_title"])
    print("\nserver-only data (no local column): "
          + (", ".join(f"{k}={v}" for k, v in sorted(non_empty.items()))
             if non_empty else "none populated")
          + (f"; group_title on {titled} legs" if titled else
             "; group_title empty everywhere"))

    report["problems"] = problems
    report["server_legs"] = len(legs)
    report["device_legs"] = len(local_rows)
    if args.json:
        Path(args.json).write_text(json.dumps(report, indent=2))

    print("\nRESULT:", "EXACT MATCH" if not problems else "DIFFERENCES FOUND")
    return 0 if not problems else 1


if __name__ == "__main__":
    sys.exit(main())
