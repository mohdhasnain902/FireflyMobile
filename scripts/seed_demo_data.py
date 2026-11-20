#!/usr/bin/env python3
"""Seed Firefly III with ~6 weeks of realistic demo data.

Creates: accounts, categories, tags, budgets, piggy banks, bills,
rules, recurrences, and ~250 transactions spread over ~45 days.
Idempotent-ish: skips entities that already exist by name.
"""
import json
import os
import random
import socket
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta

# IPv6-unroutable host workaround (see MEMORY.md)
_o = socket.getaddrinfo
socket.getaddrinfo = lambda h, p, family=0, type=0, proto=0, flags=0: _o(
    h, p, socket.AF_INET, type, proto, flags
)

BASE = os.environ.get("FIREfly_BASE", "http://localhost:8080")
PAT = os.environ["FIIII_PAT"]
TODAY = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
START = TODAY - timedelta(days=45)  # ~6.5 weeks of history

rng = random.Random(42)  # deterministic


def api(method: str, path: str, payload: dict | None = None) -> dict:
    url = f"{BASE}/api/v1/{path}"
    data = json.dumps(payload).encode() if payload else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {PAT}")
    req.add_header("Content-Type", "application/json")
    req.add_header("Accept", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"  HTTP {e.code} {method} {path}: {body[:200]}", file=sys.stderr)
        raise


def get_all(path: str) -> list[dict]:
    items, page = [], 1
    while True:
        d = api("GET", f"{path}?page={page}&limit=100")
        items.extend(d.get("data", []))
        if page >= d.get("meta", {}).get("pagination", {}).get("total_pages", 1):
            return items
        page += 1


def ensure_account(name: str, atype: str, currency: str = "EUR") -> dict:
    for a in get_all("accounts"):
        if a["attributes"]["name"] == name:
            return a
    payload: dict = {
        "name": name, "type": atype, "currency_code": currency,
        "active": True,
    }
    if atype == "asset":
        payload["account_role"] = "defaultAsset"
    r = api("POST", "accounts", payload)
    print(f"  + account {name} ({atype})")
    return r.get("data", {})


def ensure_simple(name: str, kind: str) -> dict:
    """kind = categories|tags|budgets"""
    field = "tag" if kind == "tags" else "name"
    for x in get_all(kind):
        if x["attributes"][field] == name:
            return x
    r = api("POST", kind, {field: name})
    print(f"  + {kind[:-1]} {name}")
    return r.get("data", {})


def ensure_piggy(name: str, target: str, account: str) -> dict:
    for x in get_all("piggy-banks"):
        if x["attributes"]["name"] == name:
            return x
    r = api("POST", "piggy-banks", {
        "name": name, "target_amount": str(target),
        "accounts": [{"account_id": account}],
        "start_date": iso(TODAY - timedelta(days=45))[:10],
        "transaction_currency_id": 1,
    })
    print(f"  + piggy {name} -> {target}")
    return r.get("data", {})


def ensure_bill(name: str, amount: str, freq: str, next_date: str,
                cat: str, acct: str) -> dict:
    for x in get_all("bills"):
        if x["attributes"]["name"] == name:
            return x
    # NOTE: category_name triggers Firefly 500 on bills ("Undefined array key name")
    # Firefly bills API uses `name` not `title`
    r = api("POST", "bills", {
        "name": name, "amount_min": amount, "amount_max": amount,
        "repeat_freq": freq, "date": next_date[:10],
        "next_date": next_date[:10], "currency_code": "EUR",
    })
    print(f"  + bill {name} {amount}/{freq}")
    return r.get("data", {})


def ensure_rule_group(title: str) -> int:
    """Get-or-create a rule group; returns its id."""
    for x in get_all("rule-groups"):
        if x["attributes"]["title"] == title:
            return x["id"]
    r = api("POST", "rule-groups", {"title": title})
    gid = r.get("data", {}).get("id")
    print(f"  + rule group {title} (id={gid})")
    return gid


def ensure_rule(title: str, trig_field: str, trig_val: str,
                cat: str, group_id: int) -> dict:
    for x in get_all("rules"):
        if x["attributes"]["title"] == title:
            return x
    r = api("POST", "rules", {
        "title": title, "active": True, "strict": True,
        "rule_group_id": group_id,
        "trigger": "store-journal",
        "triggers": [{
            "type": "description_contains", "value": trig_val,
            "active": True, "stop_processing": False,
        }],
        "actions": [{
            "type": "set_category", "value": cat,
            "active": True, "stop_processing": False,
        }],
    })
    print(f"  + rule {title}")
    return r.get("data", {})


def account_id(name: str) -> int:
    """Resolve an account display name to its id."""
    for x in get_all("accounts"):
        if x["attributes"]["name"] == name:
            return x["id"]
    raise SystemExit(f"account not found: {name}")


def ensure_recurrence(title: str, rtype: str, repeat_freq: str,
                      date: str, amount: str, src: str, dst: str,
                      cat: str) -> dict:
    for x in get_all("recurrences"):
        if x["attributes"]["title"] == title:
            return x
    # Firefly needs numeric ids for src/dst, a "moment" (day-of-month) for
    # monthly recurrences, and never accepts *_name in the recurrence payload.
    day = date[8:10].lstrip("0") or "1"
    r = api("POST", "recurrences", {
        "title": title, "type": rtype,
        "first_date": date, "nr_of_repetitions": 12,
        "repetitions": [{"type": repeat_freq, "moment": day}],
        "transactions": [{
            "type": "withdrawal" if rtype == "withdrawal" else "deposit",
            "date": date, "amount": amount,
            "description": title, "currency_code": "EUR",
            "source_id": account_id(src), "destination_id": account_id(dst),
            "category_name": cat,
        }],
    })
    print(f"  + recurrence {title}")
    return r.get("data", {})


def post_transactions(txs: list[dict], chunk: int = 50) -> None:
    # Firefly's `transactions` array = splits of ONE transaction group and all
    # splits must share a type, so independent txs are posted one per request.
    total = len(txs)
    for i, tx in enumerate(txs, 1):
        api("POST", "transactions", {
            "error_if_duplicate_hash": False,
            "apply_rules": True,
            "fire_webhooks": False,
            "transactions": [tx],
        })
        if i % 20 == 0 or i == total:
            print(f"  tx {i}/{total}")


def iso(d: datetime) -> str:
    """Full ISO datetime with a realistic random time of day."""
    hour = rng.choices(
        range(24),
        weights=[1,1,1,1,1,2,3,5,8,10,12,14,15,14,12,11,10,9,8,7,6,4,3,2],
    )[0]
    minute = rng.randint(0, 59)
    second = rng.randint(0, 59)
    t = d.replace(hour=hour, minute=minute, second=second)
    return t.strftime("%Y-%m-%dT%H:%M:%S+01:00")


def main() -> None:
    print("== accounts ==")
    checking = ensure_account("Checking", "asset")
    savings = ensure_account("Savings", "asset")
    cash = ensure_account("Cash Wallet", "asset")
    credit = ensure_account("Credit Card", "asset")
    ensure_account("Salary Income", "revenue")
    ensure_account("Freelance Income", "revenue")
    ensure_account("Interest Income", "revenue")
    expense_names = [
        "Grocery Store", "SuperMart", "Fresh Market",
        "Electric Company", "Water Utility", "Gas Company",
        "Internet Provider", "Mobile Provider",
        "City Transit", "Gas Station", "RideShare Co",
        "Pizza Palace", "Burger Barn", "Sushi World",
        "Coffee Corner", "Bakery Bliss", "Deli Delight",
        "Cinema Plus", "StreamFlix", "GameHub",
        "Pharmacy Central", "City Clinic", "Dental Care",
        "Clothing Co", "TechStore", "HomeGoods",
        "Book Nook", "Pet Supplies", "Gym FitLife",
        "Hardware Hub", "Plant Paradise", "Toy Town",
    ]
    for n in expense_names:
        ensure_account(n, "expense")
    ensure_account("Rent Landlord", "expense")
    ensure_account("Insurance Corp", "expense")

    print("== categories ==")
    cats = [
        "Groceries", "Utilities", "Dining Out", "Transport",
        "Entertainment", "Health", "Shopping", "Rent",
        "Subscriptions", "Savings", "Income", "Misc",
    ]
    for c in cats:
        ensure_simple(c, "categories")

    print("== tags ==")
    for t in ["recurring", "personal", "work", "weekend", "bulk-buy", "treat"]:
        ensure_simple(t, "tags")

    print("== budgets ==")
    for b in ["Monthly Essentials", "Fun Money", "Groceries Budget",
              "Transport Budget"]:
        ensure_simple(b, "budgets")

    print("== piggy banks ==")
    checking_id = checking.get("id") or checking["id"]
    ensure_piggy("Vacation Fund", "2000", checking_id)
    ensure_piggy("Emergency Fund", "5000", checking_id)
    ensure_piggy("New Laptop", "1500", checking_id)

    print("== bills ==")
    ensure_bill("Netflix", "15.99", "monthly",
                iso(TODAY + timedelta(days=7)), "Subscriptions",
                "StreamFlix")
    ensure_bill("Spotify", "10.99", "monthly",
                iso(TODAY + timedelta(days=3)), "Subscriptions",
                "StreamFlix")
    ensure_bill("Internet", "39.99", "monthly",
                iso(TODAY + timedelta(days=5)), "Utilities",
                "Internet Provider")
    ensure_bill("Mobile Plan", "25.00", "monthly",
                iso(TODAY + timedelta(days=12)), "Utilities",
                "Mobile Provider")
    ensure_bill("Rent", "950.00", "monthly",
                iso(TODAY + timedelta(days=1)), "Rent",
                "Rent Landlord")

    print("== rules ==")
    gid = ensure_rule_group("Auto-categorization")
    ensure_rule("Auto-cat groceries", "description-contains", "Grocery",
                "Groceries", gid)
    ensure_rule("Auto-cat salary", "description-contains", "Salary",
                "Income", gid)

    print("== recurrences ==")
    ensure_recurrence("Monthly Salary", "deposit", "monthly",
                      iso(TODAY.replace(day=1) + timedelta(days=30)),
                      "2800.00", "Salary Income", "Checking", "Income")
    ensure_recurrence("Monthly Rent", "withdrawal", "monthly",
                      iso(TODAY.replace(day=1) + timedelta(days=1)),
                      "950.00", "Checking", "Rent Landlord", "Rent")

    print("== transactions ==")
    txs: list[dict] = []
    groceries = ["Grocery Store", "SuperMart", "Fresh Market"]
    dining = ["Pizza Palace", "Burger Barn", "Sushi World",
              "Coffee Corner", "Bakery Bliss", "Deli Delight"]
    utilities = ["Electric Company", "Water Utility", "Gas Company",
                 "Internet Provider", "Mobile Provider"]
    transport = ["City Transit", "Gas Station", "RideShare Co"]
    entertainment = ["Cinema Plus", "StreamFlix", "GameHub"]
    health = ["Pharmacy Central", "City Clinic", "Dental Care"]
    shopping = ["Clothing Co", "TechStore", "HomeGoods",
                "Book Nook", "Pet Supplies", "Hardware Hub",
                "Plant Paradise", "Toy Town"]

    def w(day: int, dest: str, amt: float, cat: str,
          tag: str | None = None, src: str = "Checking") -> dict:
        t = {
            "type": "withdrawal", "date": iso(START + timedelta(days=day)),
            "amount": f"{amt:.2f}", "description": dest,
            "source_name": src, "destination_name": dest,
            "currency_code": "EUR", "category_name": cat,
        }
        if tag:
            t["tags"] = [tag]
        return t

    def dep(day: int, src: str, amt: float, desc: str,
            cat: str = "Income") -> dict:
        return {
            "type": "deposit", "date": iso(START + timedelta(days=day)),
            "amount": f"{amt:.2f}", "description": desc,
            "source_name": src, "destination_name": "Checking",
            "currency_code": "EUR", "category_name": cat,
        }

    # Salary: every ~30 days
    for d in (2, 32):
        txs.append(dep(d, "Salary Income", 2800.00, "Monthly Salary"))
    # Freelance: a few one-offs
    for d in (8, 22, 40):
        txs.append(dep(d, "Freelance Income", rng.choice([350, 500, 720]),
                       "Freelance Project", "Income"))

    # Rent: monthly
    for d in (1, 31):
        txs.append(w(d, "Rent Landlord", 950.00, "Rent", "recurring"))

    # Utilities: monthly-ish
    for d in (4, 34):
        txs.append(w(d, "Electric Company", rng.uniform(45, 90),
                     "Utilities", "recurring"))
        txs.append(w(d, "Water Utility", rng.uniform(20, 35),
                     "Utilities", "recurring"))
        txs.append(w(d, "Internet Provider", 39.99, "Utilities", "recurring"))
        txs.append(w(d, "Mobile Provider", 25.00, "Utilities", "recurring"))
    # Gas heating extra in colder weeks
    for d in (10, 17, 38):
        txs.append(w(d, "Gas Company", rng.uniform(30, 60),
                     "Utilities", "recurring"))

    # Subscriptions (weekly/monthly)
    for d in range(0, 46, 7):
        txs.append(w(d, "StreamFlix", 15.99, "Subscriptions", "recurring"))
    for d in range(3, 46, 7):
        txs.append(w(d, "StreamFlix", 10.99, "Subscriptions", "recurring"))

    # Groceries: 2-3x per week
    for d in range(0, 46):
        if rng.random() < 0.35:
            dest = rng.choice(groceries)
            amt = rng.uniform(18, 85)
            tag = "bulk-buy" if amt > 55 else "personal"
            txs.append(w(d, dest, amt, "Groceries", tag,
                         src=rng.choice(["Checking", "Credit Card"])))

    # Dining: 3-5x per week
    for d in range(0, 46):
        if rng.random() < 0.55:
            dest = rng.choice(dining)
            amt = rng.uniform(3, 28)
            tag = "weekend" if (START + timedelta(days=d)).weekday() >= 5 \
                else "personal"
            txs.append(w(d, dest, amt, "Dining Out", tag,
                         src=rng.choice(["Checking", "Credit Card", "Cash Wallet"])))

    # Transport: most weekdays
    for d in range(0, 46):
        day_of_week = (START + timedelta(days=d)).weekday()
        if day_of_week < 5 and rng.random() < 0.7:
            dest = rng.choice(transport)
            amt = rng.uniform(2, 45) if dest != "City Transit" else 2.80
            txs.append(w(d, dest, amt, "Transport", "work"))

    # Entertainment: weekends mostly
    for d in range(0, 46):
        if rng.random() < 0.20:
            dest = rng.choice(entertainment)
            amt = rng.uniform(5, 40)
            txs.append(w(d, dest, amt, "Entertainment", "treat",
                         src=rng.choice(["Checking", "Credit Card"])))

    # Health: occasional
    for d in rng.sample(range(0, 46), 6):
        dest = rng.choice(health)
        txs.append(w(d, dest, rng.uniform(12, 80), "Health", "personal"))

    # Shopping: occasional
    for d in rng.sample(range(0, 46), 10):
        dest = rng.choice(shopping)
        amt = rng.uniform(8, 120)
        txs.append(w(d, dest, amt, "Shopping",
                     "weekend" if (START + timedelta(days=d)).weekday() >= 5
                     else "personal",
                     src=rng.choice(["Checking", "Credit Card"])))

    # Gym: monthly
    for d in (6, 36):
        txs.append(w(d, "Gym FitLife", 29.99, "Health", "recurring"))

    # Insurance: monthly
    for d in (9, 39):
        txs.append(w(d, "Insurance Corp", 85.00, "Misc", "recurring"))

    # Cash ATM withdrawals
    for d in rng.sample(range(0, 46), 8):
        txs.append({
            "type": "withdrawal", "date": iso(START + timedelta(days=d)),
            "amount": f"{rng.choice([20, 40, 60, 80]):.2f}",
            "description": "ATM Cash Withdrawal",
            "source_name": "Checking", "destination_name": "Cash Wallet",
            "currency_code": "EUR",
        })

    # Credit card payment (transfer-like: withdrawal from checking to CC)
    for d in (15, 45):
        txs.append(w(d, "Credit Card", rng.uniform(150, 400),
                     "Misc", "recurring"))

    # Savings transfers
    for d in (2, 32):
        txs.append({
            "type": "withdrawal", "date": iso(START + timedelta(days=d)),
            "amount": "300.00", "description": "Transfer to Savings",
            "source_name": "Checking", "destination_name": "Savings",
            "currency_code": "EUR", "category_name": "Savings",
            "tags": ["recurring"],
        })

    rng.shuffle(txs)
    print(f"  total transactions to post: {len(txs)}")
    post_transactions(txs)

    # Final count
    total = api("GET", "transactions?limit=1")["meta"]["pagination"]["total"]
    print(f"\nDONE. transactions on server: {total}")


if __name__ == "__main__":
    main()
