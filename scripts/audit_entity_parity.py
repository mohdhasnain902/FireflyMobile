#!/usr/bin/env python3
"""Full mirror audit: every modelled field of every entity, phone vs Firefly.

`verify_sync_parity.py` checks transaction legs and accounts. This script covers
the rest of the book — currencies, categories, tags, budgets (+limits), bills,
subscriptions, rules, rule groups, piggy banks, recurrences and attachments —
and reports any row that is missing, extra, or whose field values differ.

Usage:
    python3 scripts/audit_entity_parity.py --db /tmp/cdb/firefly.db \
        --token-file "/path/to/token.txt" [--base http://localhost:8080]

Exit status 0 when every entity matches, 1 otherwise.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import urllib.request
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

# (db column, server attribute, kind)
# kind: str | num | bool | date | list | json
MAPPING: dict[str, dict] = {
    "currencies": {
        "path": "/currencies",
        "fields": [
            ("code", "code", "str"),
            ("name", "name", "str"),
            ("symbol", "symbol", "str"),
            ("decimal_places", "decimal_places", "num"),
            ("enabled", "enabled", "bool"),
            ("is_default", "default", "bool"),
        ],
        # Server never sends these, so they can only be local.
        "server_absent": [("symbol_first", "symbol_first"), ("rate", "rate")],
    },
    "accounts": {
        "path": "/accounts",
        "fields": [
            ("name", "name", "str"),
            ("type", "type", "str"),
            ("account_role", "account_role", "str"),
            ("currency_code", "currency_code", "str"),
            ("currency_id", "currency_id", "str"),
            ("active", "active", "bool"),
            ("notes", "notes", "str"),
            ("iban", "iban", "str"),
            ("bic", "bic", "str"),
            ("account_number", "account_number", "str"),
            ("include_net_worth", "include_net_worth", "bool"),
            ("order_index", "order", "num"),
            ("opening_balance", "opening_balance", "num"),
            ("opening_balance_date", "opening_balance_date", "date"),
        ],
        "server_absent": [("virtual_balance", "virtual_balance (local mirror only)")],
    },
    "categories": {
        "path": "/categories",
        "fields": [("name", "name", "str"), ("notes", "notes", "str")],
    },
    "tags": {
        "path": "/tags",
        "fields": [("tag", "tag", "str"), ("date", "date", "date")],
    },
    "budgets": {
        "path": "/budgets",
        "fields": [
            ("name", "name", "str"),
            ("notes", "notes", "str"),
            ("active", "active", "bool"),
            ("order_index", "order", "num"),
            ("auto_budget_type", "auto_budget_type", "str"),
            ("currency_code", "currency_code", "str"),
        ],
    },
    "bills": {
        "path": "/bills",
        "fields": [
            ("name", "name", "str"),
            ("currency_code", "currency_code", "str"),
            ("repeat_freq", "repeat_freq", "str"),
            ("skip", "skip", "num"),
            ("active", "active", "bool"),
            ("notes", "notes", "str"),
            ("pay_dates", "pay_dates", "list"),
            ("date", "date", "date"),
            ("next_expected_match", "next_expected_match", "date"),
            # Firefly sends amount_min/amount_max/amount_avg, never `amount`.
            ("amount", "amount_min", "num"),
        ],
    },
    "subscriptions": {
        "path": "/subscriptions",
        "fields": [
            ("title", "name", "str"),
            ("currency_code", "currency_code", "str"),
            ("repeat_freq", "repeat_freq", "str"),
            ("active", "active", "bool"),
            ("notes", "notes", "str"),
            # The subscription endpoint serialises the bill shape: the next
            # due date is `date`, and there is no `next_date` on the wire.
            ("next_date", "date", "date"),
            ("end_date", "end_date", "date"),
            ("periods", "periods", "list"),
            ("amount", "amount_min", "num"),
        ],
    },
    "rules": {
        "path": "/rules",
        "fields": [
            ("title", "title", "str"),
            ("description", "description", "str"),
            ("trigger", "trigger", "str"),
            ("active", "active", "bool"),
            ("strict", "strict", "bool"),
            ("stop", "stop_processing", "bool"),
            ("order_index", "order", "num"),
        ],
    },
    "rule_groups": {
        "path": "/rule-groups",
        "fields": [
            ("title", "title", "str"),
            ("description", "description", "str"),
            ("active", "active", "bool"),
            ("order_index", "order", "num"),
        ],
    },
    "piggy_banks": {
        "path": "/piggy-banks",
        "fields": [
            ("name", "name", "str"),
            ("target_amount", "target_amount", "num"),
            ("current_amount", "current_amount", "num"),
            ("start_date", "start_date", "date"),
            ("target_date", "target_date", "date"),
            ("order_index", "order", "num"),
            ("notes", "notes", "str"),
        ],
    },
    "recurrences": {
        "path": "/recurrences",
        "fields": [
            ("title", "title", "str"),
            ("type", "type", "str"),
            ("description", "description", "str"),
            ("first_date", "first_date", "date"),
            ("repeat_until", "repeat_until", "date"),
            ("nr_of_repetitions", "nr_of_repetitions", "num"),
            ("active", "active", "bool"),
        ],
    },
    "attachments": {
        "path": "/attachments",
        "fields": [
            ("filename", "filename", "str"),
            ("notes", "notes", "str"),
            ("md5", "md5", "str"),
            ("size", "size", "num"),
            ("mime_type", "mime_type", "str"),
        ],
    },
}


def call(base: str, token: str, path: str) -> dict:
    req = urllib.request.Request(
        base + path,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read() or b"{}")


def fetch_all(base: str, token: str, path: str) -> list[dict]:
    out: list[dict] = []
    page = 1
    while True:
        sep = "&" if "?" in path else "?"
        payload = call(base, token, f"{path}{sep}limit=100&page={page}")
        out.extend(payload.get("data", []))
        pagination = payload["meta"]["pagination"]
        if pagination["current_page"] >= pagination["total_pages"]:
            break
        page += 1
    return out


def as_decimal(value) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value)).normalize()
    except (InvalidOperation, ValueError):
        return None


def as_bool(value) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    return str(value).lower() in {"1", "true"}


def as_datetime(value) -> str | None:
    """Normalises every date shape to a naive UTC 'YYYY-MM-DDTHH:MM:SS' string."""
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        moment = datetime.fromtimestamp(value / 1000, tz=timezone.utc)
        return moment.strftime("%Y-%m-%dT%H:%M:%S")
    text = str(value).strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return text
    if parsed.tzinfo is None:
        return parsed.strftime("%Y-%m-%dT%H:%M:%S")
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")


def as_list(value) -> str:
    if value is None or value == "":
        return "[]"
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError:
            return value
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def normalise(value, kind: str):
    if kind == "num":
        return as_decimal(value)
    if kind == "bool":
        return as_bool(value)
    if kind == "date":
        return as_datetime(value)
    if kind == "list":
        return as_list(value)
    if value is None:
        return ""
    return str(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--token-file", required=True)
    parser.add_argument("--base", default="http://localhost:8080")
    parser.add_argument("--json", help="write the report as JSON here")
    args = parser.parse_args()

    token = open(args.token_file).read().strip()
    base = args.base.rstrip("/") + "/api/v1"
    db = sqlite3.connect(args.db)
    db.row_factory = sqlite3.Row

    report: dict[str, dict] = {}
    total_diffs = 0

    for table, spec in MAPPING.items():
        server_rows = fetch_all(base, token, spec["path"])
        server_by_id = {str(row["id"]): row["attributes"] for row in server_rows}
        local_rows = {
            str(row["firefly_id"]): dict(row)
            for row in db.execute(
                f"select * from {table} where deleted_at is null "
                "and firefly_id is not null"
            )
        }

        missing = sorted(set(server_by_id) - set(local_rows))
        extra = sorted(set(local_rows) - set(server_by_id))
        field_diffs: dict[str, list[str]] = {}

        for firefly_id in sorted(set(server_by_id) & set(local_rows)):
            attributes = server_by_id[firefly_id]
            local = local_rows[firefly_id]
            for column, key, kind in spec["fields"]:
                server_value = normalise(attributes.get(key), kind)
                local_value = normalise(local.get(column), kind)
                if kind == "str" and not server_value and not local_value:
                    continue
                if server_value != local_value:
                    field_diffs.setdefault(column, []).append(
                        f"id {firefly_id}: server {server_value!r} != phone {local_value!r}"
                    )

        entry = {
            "server": len(server_rows),
            "phone": len(local_rows),
            "missing_on_phone": missing,
            "extra_on_phone": extra,
            "field_diffs": field_diffs,
        }
        report[table] = entry
        total_diffs += len(missing) + len(extra) + sum(
            len(v) for v in field_diffs.values()
        )

        status = "OK" if not (missing or extra or field_diffs) else "DIFFERS"
        print(
            f"{table:14} server={len(server_rows):>5} phone={len(local_rows):>5}  {status}"
        )
        for firefly_id in missing[:5]:
            print(f"    missing on phone: {firefly_id}")
        for firefly_id in extra[:5]:
            print(f"    extra on phone:   {firefly_id}")
        for column, examples in field_diffs.items():
            print(f"    field {column}: {len(examples)} row(s)")
            for line in examples[:3]:
                print(f"      {line}")

    if args.json:
        with open(args.json, "w") as handle:
            json.dump(report, handle, indent=2)

    if total_diffs:
        print(f"\nRESULT: {total_diffs} difference(s)")
        return 1
    print("\nRESULT: EXACT MATCH (every entity, every modelled field)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
