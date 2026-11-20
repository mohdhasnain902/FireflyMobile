#!/usr/bin/env python3
"""Backup sidecar — the PC half of the mobile app's P4 backup feature.

DESIGN §8.2: after every successful push+pull sync the phone POSTs here
(`POST /backup`, `Authorization: Bearer <token>`); this process then takes a
SQLite snapshot of the Firefly database and a CSV export of all entities
onto the PC. The phone only *triggers* — it never receives backup bytes.

Scope decisions (pinned in IMPLEMENTATION-PLAN P4):
  * Transport is this tiny HTTP sidecar (user choice 2026-10-19), not ADB.
  * Snapshot uses SQLite's online backup API (PHP ``SQLite3::backup`` inside
    the container) — a plain ``cp`` of a live SQLite file can capture a torn
    write; the backup API never does.
  * Backup dir defaults to ``/mnt/data/firefly-backups`` (design wrote ``~``;
    /home/arcore is off-limits for created files and /mnt/data survives).
  * Rotation keeps the newest ``BACKUP_KEEP`` (default 30) snapshots.
  * CSV export reuses Firefly's own ``/api/v1/data/export/{entity}`` with the
    existing ``FIIII_PAT`` — same source of truth the capture fixtures use.

Stdlib only — no pip, no venv needed on the PC.
"""

from __future__ import annotations

import argparse
import hmac
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib import request as urlrequest
from urllib.error import HTTPError, URLError

# --- configuration ------------------------------------------------------------

# Directory of this script — .credentials and .backup_token live next to it.
HERE = Path(__file__).resolve().parent

# The 9 entities Firefly actually exposes on /api/v1/data/export/{type}
# (routes/api.php export group, verified live against the 6.7.9 container:
#  subscriptions is an alias of bills, piggy-banks/recurring are the route
#  spellings). DESIGN §8.2 wrote "currencies, rule_groups, recurrences" —
#  those have NO export route; they are fully covered by the SQLite snapshot,
#  and the snapshot is the authoritative restore artifact anyway.
ENTITIES = (
    "accounts",
    "bills",
    "budgets",
    "categories",
    "piggy-banks",
    "recurring",
    "rules",
    "tags",
    "transactions",
)

CONTAINER = "firefly_iii_core"
# Path of the SQLite database *inside* the app container.
CONTAINER_DB = "/var/www/html/storage/database/database.sqlite"
# Container-side scratch path the snapshot is written to before `docker cp`.
CONTAINER_SNAP = "/tmp/backup-sidecar-snap.sqlite"


def _env(name: str, default: str | None = None) -> str | None:
    """Reads an env var, falling back to [default] (None = unset)."""
    value = os.environ.get(name)
    return value if value else default


def _load_dotenv_file(path: Path) -> dict[str, str]:
    """Parses a KEY=VALUE file (no export/quotes handling needed for ours).

    Used for ``.credentials`` (FIIII_PAT) so the sidecar needs no env setup
    when launched by hand or by a systemd unit.
    """
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        out[key.strip()] = value.strip()
    return out


def backup_token() -> str:
    """Returns the shared trigger token (env wins over .backup_token file).

    Raises SystemExit when neither exists — an unauthenticated listener on
    0.0.0.0 would be an open remote-trigger, so the server refuses to start.
    """
    token = _env("BACKUP_TOKEN")
    if token:
        return token
    token_file = Path(_env("BACKUP_TOKEN_FILE", str(HERE / ".backup_token")) or "")
    if token_file.is_file():
        return token_file.read_text(encoding="utf-8").strip()
    sys.exit(
        "backup_sidecar: no token — set BACKUP_TOKEN or create "
        f"{HERE / '.backup_token'}"
    )


def _firefly_pat() -> str:
    """Returns the PAT used for CSV export (env, else .credentials file)."""
    pat = _env("FIREFLY_PAT")
    if pat:
        return pat
    pat = _load_dotenv_file(HERE / ".credentials").get("FIIII_PAT")
    if not pat:
        sys.exit("backup_sidecar: no PAT — set FIREFLY_PAT or add FIIII_PAT to .credentials")
    return pat


def _utc_stamp() -> str:
    """UTC timestamp used in file names (lexicographic sort == time order)."""
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    """Runs a command, raising with stderr context on failure."""
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(
            f"command failed ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr.strip()}"
        )
    return proc


# --- the three backup steps ---------------------------------------------------


def snapshot(db_dir: Path) -> Path:
    """Copies the live Firefly SQLite database into [db_dir] safely.

    Uses SQLite's online backup API *inside* the container (PHP SQLite3 is
    already there; the host cannot read the docker volume directly), then
    ``docker cp``s the result out. Torn reads are impossible: backup API
    handles concurrent writers. Returns the new snapshot's path.
    """
    db_dir.mkdir(parents=True, exist_ok=True)
    ts = _utc_stamp()
    dest = db_dir / f"firefly-{ts}.sqlite"

    # Online backup to a container-side temp file …
    _run([
        "docker", "exec", CONTAINER, "php", "-r",
        "$s=new SQLite3('" + CONTAINER_DB + "');"
        "$d=new SQLite3('" + CONTAINER_SNAP + "');"
        "$s->backup($d); $d->close(); $s->close();",
    ])
    try:
        # … then pull it out and verify it is a readable SQLite database
        # before declaring success (a corrupt snapshot must not count).
        _run(["docker", "cp", f"{CONTAINER}:{CONTAINER_SNAP}", str(dest)])
        probe = subprocess.run(
            ["python3", "-c",
             "import sqlite3,sys; c=sqlite3.connect(sys.argv[1]);"
             "r=c.execute('PRAGMA integrity_check').fetchone();"
             "sys.exit(0 if r and r[0]=='ok' else 1)", str(dest)],
            capture_output=True,
        )
        if probe.returncode != 0:
            dest.unlink(missing_ok=True)
            raise RuntimeError("snapshot failed PRAGMA integrity_check")
    finally:
        # Always drop the container-side temp copy (even on failure).
        subprocess.run(
            ["docker", "exec", CONTAINER, "rm", "-f", CONTAINER_SNAP],
            capture_output=True,
        )
    return dest


def rotate(db_dir: Path, keep: int) -> int:
    """Deletes oldest ``firefly-*.sqlite`` AND ``csv-*`` dirs beyond [keep].

    Both artifact families rotate on the same keep-count — an unbounded
    ``csv-`` dir pile would grow a few MB per day forever. Returns total
    deletions (snapshots + csv dirs).
    """
    if keep <= 0:
        return 0
    removed = 0
    snaps = sorted(
        db_dir.glob("firefly-*.sqlite"), key=lambda p: p.name, reverse=True
    )
    for old in snaps[keep:]:
        old.unlink(missing_ok=True)
        removed += 1
    csv_dirs = sorted(
        (p for p in db_dir.glob("csv-*") if p.is_dir()),
        key=lambda p: p.name,
        reverse=True,
    )
    for old in csv_dirs[keep:]:
        shutil.rmtree(old, ignore_errors=True)
        removed += 1
    return removed


def export_csv(csv_dir: Path, base_url: str, pat: str) -> list[str]:
    """Writes all [ENTITIES] exports into [csv_dir]; returns failure names.

    One failed entity is recorded but does not stop the others — a partial
    CSV set is still a useful restore aid, and the caller reports [ok]=false.
    """
    csv_dir.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []
    for entity in ENTITIES:
        url = f"{base_url.rstrip('/')}/api/v1/data/export/{entity}"
        req = urlrequest.Request(url, headers={"Authorization": f"Bearer {pat}"})
        try:
            with urlrequest.urlopen(req, timeout=30) as resp:
                body = resp.read()
        except (HTTPError, URLError, TimeoutError) as exc:
            failures.append(f"{entity}: {exc}")
            continue
        (csv_dir / f"{entity}.csv").write_bytes(body)
    return failures


def run_backup() -> dict:
    """Runs snapshot + rotation + CSV export; returns the JSON response body.

    Never raises for partial failures: the phone's trigger gets a truthful
    ``ok`` plus details, because the app treats this as best-effort.
    """
    db_dir = Path(_env("BACKUP_DIR", "/mnt/data/firefly-backups") or "")
    keep = int(_env("BACKUP_KEEP", "30") or "30")
    base_url = _env("FIREFLY_URL", "http://127.0.0.1:8080") or ""
    ts = _utc_stamp()

    body: dict = {"ok": True, "time": ts}
    try:
        snap = snapshot(db_dir)
        body["snapshot"] = str(snap)
        body["snapshot_bytes"] = snap.stat().st_size
    except Exception as exc:  # noqa: BLE001 — reported, never crashes the server
        body["ok"] = False
        body["snapshot_error"] = str(exc)
        body["snapshot"] = None

    csv_dir = db_dir / f"csv-{ts}"
    try:
        failures = export_csv(csv_dir, base_url, _firefly_pat())
        body["csv_dir"] = str(csv_dir)
        body["csv_failed"] = failures
        if failures:
            body["ok"] = False
    except Exception as exc:  # noqa: BLE001 — PAT missing etc.
        body["ok"] = False
        body["csv_error"] = str(exc)

    # Rotation LAST so this run's snapshot + csv dir already count toward the
    # keep-budget (rotating first would transiently keep keep+1 of each).
    try:
        body["rotated_removed"] = rotate(db_dir, keep)
    except Exception as exc:  # noqa: BLE001 — rotation is housekeeping
        body["rotated_removed"] = 0
        body["rotate_error"] = str(exc)
    return body


# --- HTTP front end -----------------------------------------------------------


class BackupHandler(BaseHTTPRequestHandler):
    """POST /backup (Bearer-token gated) and unauthenticated GET /healthz."""

    server_version = "firefly-backup/1"

    def _send(self, code: int, payload: dict) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802 — stdlib naming
        if self.path == "/healthz":
            self._send(200, {"ok": True, "service": "firefly-backup"})
        else:
            self._send(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:  # noqa: N802 — stdlib naming
        if self.path != "/backup":
            self._send(404, {"ok": False, "error": "not found"})
            return
        # Constant-time token compare — the token is the ONLY gate, so no
        # timing oracle on prefix bytes.
        supplied = self.headers.get("Authorization", "")
        expected = f"Bearer {backup_token()}"
        if not hmac.compare_digest(supplied, expected):
            self._send(401, {"ok": False, "error": "unauthorized"})
            return
        try:
            self._send(200, run_backup())
        except Exception as exc:  # noqa: BLE001 — keep the server alive
            self._send(500, {"ok": False, "error": str(exc)})

    def log_message(self, fmt: str, *args) -> None:
        """Compact one-line access log to stderr (a backup run is rare)."""
        sys.stderr.write(
            f"[sidecar] {datetime.now(timezone.utc).isoformat(timespec='seconds')} "
            f"{fmt % args}\n"
        )


def main() -> int:
    ap = argparse.ArgumentParser(description="Firefly backup sidecar (P4)")
    ap.add_argument("--once", action="store_true",
                    help="run one backup, print JSON, exit (drill/tests)")
    ap.add_argument("--host", default=_env("SIDECAR_HOST", "0.0.0.0") or "0.0.0.0",
                    help="bind address (default 0.0.0.0 so the phone on LAN "
                         "can reach it; the Bearer token is the only gate)")
    ap.add_argument("--port", type=int, default=int(_env("SIDECAR_PORT", "8095") or 8095))
    args = ap.parse_args()

    if args.once:
        body = run_backup()
        print(json.dumps(body, indent=2))
        return 0 if body.get("ok") else 1

    # --once skips token checks by design (local drill); serving requires it.
    backup_token()
    server = ThreadingHTTPServer((args.host, args.port), BackupHandler)
    print(f"[sidecar] listening on {args.host}:{args.port} "
          f"(backup dir: {_env('BACKUP_DIR', '/mnt/data/firefly-backups')})",
          file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
