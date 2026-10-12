#!/usr/bin/env bash
#
# capture_fixtures.sh — dump golden JSON:API fixtures from the pinned Firefly III
# instance into app/test/fixtures/api/.
#
# Why: DESIGN.md L476 ("Golden API fixtures"). Committing the raw contract makes a
# Firefly version bump diff-able — if the API shape changes, this script re-runs and
# the fixture diff shows exactly what moved, so we can fix the app before shipping.
#
# Auth: reads the PAT from .credentials (gitignored). The PAT is a bearer token minted
# via POST /oauth/personal-access-tokens — see docs/IMPLEMENTATION_LOG.md.
#
# Usage:  ./capture_fixtures.sh            # write fixtures
#         ./capture_fixtures.sh --check     # fetch only, diff against committed, exit 1 on drift
set -euo pipefail

# --- resolve paths (script lives in infra/firefly, fixtures land in app/test/...) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/app/test/fixtures/api"
CREDS="$SCRIPT_DIR/.credentials"
CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

# --- credentials: fail loudly rather than silently capturing 401 HTML as "fixtures" ---
[[ -f "$CREDS" ]] || { echo "ERROR: missing $CREDS (need FIIII_BASE + FIIII_PAT)" >&2; exit 1; }
BASE="$(grep '^FIIII_BASE=' "$CREDS" | cut -d= -f2-)"
PAT="$(grep '^FIIII_PAT=' "$CREDS" | cut -d= -f2-)"
[[ -n "$BASE" && -n "$PAT" ]] || { echo "ERROR: FIIII_BASE / FIIII_PAT not set in $CREDS" >&2; exit 1; }

# --- endpoint table: <url path> -> <fixture file stem> -------------------------
# Kept flat so a reviewer can see the whole contract surface at a glance.
ENDPOINTS=(
  "about:about"
  "accounts:accounts"
  "accounts/1:account_1"
  "transactions:transactions"
  "transactions/1:transaction_1"
  "budgets:budgets"
  "categories:categories"
  "tags:tags"
  "rules:rules"
  "rule-groups:rule_groups"
  "piggy-banks:piggy_banks"
  "currencies:currencies"
  "subscriptions:subscriptions"
  "bills:bills"
  "users:users"
  "preferences:preferences"
  "attachments:attachments"
)

mkdir -p "$FIXTURE_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
DRIFT=0

# --- fetch one endpoint, pretty-print it, and optionally diff vs the commit ----
capture () {
  # NOTE: separate `local` statements — `local a=1 b=$a` expands `$a` before it is
  # assigned, which trips `set -u` with "stem: unbound variable".
  local path="$1"
  local stem="$2"
  local out="$WORK/$stem.json"
  local code
  code="$(curl -sS -o "$out" -w '%{http_code}' --max-time 30 \
      -H "Authorization: Bearer $PAT" \
      -H "Accept: application/json" \
      "$BASE/api/v1/$path")"

  # A non-200 means the contract probe failed — never write an error page as a fixture.
  if [[ "$code" != "200" ]]; then
    echo "FAIL  $path  HTTP $code" >&2
    head -c 300 "$out" >&2; echo >&2
    return 1
  fi

  # Normalise in one pass, applied identically to the write and --check paths so the
  # two are byte-comparable:
  #   1. REDACT  — Firefly stores secrets as preference ROWS, i.e. the credential is
  #                in `attributes.data` while the discriminator is `attributes.name`
  #                (access_token, mfa_recovery, slack_webhook_url, pushover_*). So we
  #                redact by row name, not by key name — a plain key-name match would
  #                miss every one of them.
  #   2. VOLATILE — *_at / *_date carry wall-clock values (current_balance_date moves
  #                on every request) which would report phantom drift forever. Mask
  #                only when the value is a string, so a real type change (string ->
  #                null / number) still surfaces as a diff.
  #   3. sort_keys + indent — stable ordering, so diffs show contract change only.
  python3 - "$out" <<'PY'
import json, sys

# Matched case-insensitively against a row's `name` field.
SENSITIVE_NAME_SUBSTR = ("token", "secret", "password", "key",
                         "webhook", "recovery", "apikey")
# Matched case-insensitively against a literal key, as a backstop for any
# endpoint that does not use the name/data row shape.
SENSITIVE_KEY_EXACT = {"access_token", "password", "secret",
                       "api_key", "token", "refresh_token"}


def transform(node, key=None):
    if isinstance(node, dict):
        # Does this row hold a credential in its `data` field?
        row_name = node.get("name")
        redact_row = (
            isinstance(row_name, str)
            and any(s in row_name.lower() for s in SENSITIVE_NAME_SUBSTR)
        )
        out = {}
        for k, v in node.items():
            if v is not None and (k in SENSITIVE_KEY_EXACT
                                  or (redact_row and k == "data")):
                out[k] = "<redacted>"
            else:
                out[k] = transform(v, k)
        return out
    if isinstance(node, list):
        return [transform(v, key) for v in node]
    # Volatile wall-clock values: mask only strings, preserve key + shape.
    if isinstance(node, str) and key:
        if key.endswith("_at"):
            return "<timestamp>"
        if key.endswith("_date"):
            return "<date>"
    return node


path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
data = transform(data)
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)
    f.write("\n")
PY

  if $CHECK_ONLY; then
    local target="$FIXTURE_DIR/$stem.json"
    if [[ ! -f "$target" ]]; then
      echo "DRIFT  $stem.json is new (not committed)" >&2; DRIFT=1
    elif ! diff -q "$target" "$out" >/dev/null; then
      echo "DRIFT  $stem.json differs from live API" >&2
      diff "$target" "$out" | head -40 >&2 || true
      DRIFT=1
    else
      echo "ok     $stem.json"
    fi
  else
    cp "$out" "$FIXTURE_DIR/$stem.json"
    echo "wrote  $stem.json ($(wc -c < "$out") bytes)"
  fi
}

echo "==> capturing from $BASE (check=$CHECK_ONLY)"
for entry in "${ENDPOINTS[@]}"; do
  capture "${entry%%:*}" "${entry##*:}"
done

# --- manifest: pins which Firefly build these fixtures came from --------------
# The smoke test asserts manifest.api_version == the image tag in
# infra/firefly/docker-compose.yml, so a drifting pin fails fast.
VERSION="$(curl -sS --max-time 20 -H "Authorization: Bearer $PAT" -H "Accept: application/json" \
  "$BASE/api/v1/about" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["version"])')"
python3 - "$FIXTURE_DIR/manifest.json" "$VERSION" "$BASE" <<'PY'
import json, sys
out, version, base = sys.argv[1], sys.argv[2], sys.argv[3]
manifest = {
    "firefly_version": version,
    "base_url": base,
    "note": "Regenerate with infra/firefly/capture_fixtures.sh",
}
with open(out, "w") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
PY
echo "==> manifest: firefly_version=$VERSION"

if $CHECK_ONLY && [[ $DRIFT -ne 0 ]]; then
  echo "==> FIXTURE DRIFT DETECTED (contract changed)" >&2
  exit 1
fi
echo "==> done"
