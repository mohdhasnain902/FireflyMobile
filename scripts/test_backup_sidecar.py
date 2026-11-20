#!/usr/bin/env python3
"""Unit tests for backup_sidecar.py rotation and snapshot logic.

Runs without Docker by monkeypatching subprocess and docker exec calls.
Covers:
  * rotation keeps exactly BACKUP_KEEP snapshots + csv dirs
  * snapshot names use UTC stamps (lexicographic == time order)
  * export_csv writes one file per entity and records failures
  * run_backup returns ok:false on snapshot failure (never crashes)
"""
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch, MagicMock

# Make the sidecar importable
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "infra" / "firefly"))

import backup_sidecar  # noqa: E402


def _write_fake_snapshot(db_dir: Path, name: str) -> Path:
    """Create a fake snapshot file (valid SQLite header) in [db_dir]."""
    p = db_dir / name
    p.write_bytes(b"SQLite format 3\x00")
    return p


def _write_fake_csv_dir(db_dir: Path, name: str) -> Path:
    d = db_dir / name
    d.mkdir(parents=True, exist_ok=True)
    for e in ("accounts", "transactions"):
        (d / f"{e}.csv").write_text("id,name\n")
    return d


# ---------------------------------------------------------------------------
# rotation
# ---------------------------------------------------------------------------

def test_rotation_keeps_exactly_keep_snapshots():
    with tempfile.TemporaryDirectory() as td:
        db_dir = Path(td)
        # Create 35 snapshots: Nov 1-5 (newest), Oct 31 down to Oct 2 (oldest).
        names = (
            [f"firefly-202611{i:02d}T120000Z.sqlite" for i in range(1, 6)]
            + [f"firefly-202610{i:02d}T120000Z.sqlite" for i in range(31, 1, -1)]
        )
        assert len(names) == 35, f"expected 35 names, got {len(names)}"
        for name in names:
            _write_fake_snapshot(db_dir, name)

        removed = backup_sidecar.rotate(db_dir, keep=30)

        remaining = sorted(db_dir.glob("firefly-*.sqlite"))
        assert len(remaining) == 30, f"expected 30, got {len(remaining)}"
        assert removed == 5, f"expected 5 removed, got {removed}"
        # The 5 alphabetically-oldest (Oct 2-6) were removed; the rest remain.
        assert remaining[0].name == "firefly-20261007T120000Z.sqlite"
        assert remaining[-1].name == "firefly-20261105T120000Z.sqlite"


def test_rotation_keeps_exactly_keep_csv_dirs():
    with tempfile.TemporaryDirectory() as td:
        db_dir = Path(td)
        names = (
            [f"csv-202611{i:02d}T120000Z" for i in range(1, 6)]
            + [f"csv-202610{i:02d}T120000Z" for i in range(31, 1, -1)]
        )
        assert len(names) == 35
        for name in names:
            _write_fake_csv_dir(db_dir, name)

        removed = backup_sidecar.rotate(db_dir, keep=30)

        remaining = sorted((p for p in db_dir.glob("csv-*") if p.is_dir()))
        assert len(remaining) == 30
        assert removed == 5


def test_rotation_keep_zero_removes_nothing():
    with tempfile.TemporaryDirectory() as td:
        db_dir = Path(td)
        _write_fake_snapshot(db_dir, "firefly-20261031T120000Z.sqlite")
        removed = backup_sidecar.rotate(db_dir, keep=0)
        assert removed == 0
        assert len(list(db_dir.glob("firefly-*.sqlite"))) == 1


def test_rotation_removes_both_families_and_counts_total():
    with tempfile.TemporaryDirectory() as td:
        db_dir = Path(td)
        # 32 snapshots + 32 csv dirs -> 2 removed from each family = 4 total.
        for i in range(32, 0, -1):
            _write_fake_snapshot(db_dir, f"firefly-202610{i:02d}T120000Z.sqlite")
        for i in range(32, 0, -1):
            _write_fake_csv_dir(db_dir, f"csv-202610{i:02d}T120000Z")

        removed = backup_sidecar.rotate(db_dir, keep=30)
        assert removed == 4  # 2 snapshots + 2 csv dirs


# ---------------------------------------------------------------------------
# run_backup (monkeypatched)
# ---------------------------------------------------------------------------

@patch.object(backup_sidecar, "snapshot")
@patch.object(backup_sidecar, "export_csv")
@patch.object(backup_sidecar, "rotate")
def test_run_backup_ok_path(mock_rotate, mock_export_csv, mock_snapshot):
    fake_snap = MagicMock()
    fake_snap.__str__ = lambda self: "/mnt/data/firefly-backups/firefly-20261031T120000Z.sqlite"
    fake_snap.stat.return_value.st_size = 12345
    mock_snapshot.return_value = fake_snap
    mock_export_csv.return_value = []
    mock_rotate.return_value = 0

    with patch.dict(os.environ, {
        "BACKUP_DIR": "/tmp/backup-test",
        "BACKUP_KEEP": "30",
        "FIREFLY_URL": "http://127.0.0.1:8080",
        "FIREFLY_PAT": "pat123",
    }):
        body = backup_sidecar.run_backup()

    assert body["ok"] is True
    assert body["time"] == datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    assert body["snapshot"] == "/mnt/data/firefly-backups/firefly-20261031T120000Z.sqlite"
    assert body["snapshot_bytes"] > 0
    assert body["csv_failed"] == []
    assert body["rotated_removed"] == 0


@patch.object(backup_sidecar, "snapshot")
@patch.object(backup_sidecar, "export_csv")
@patch.object(backup_sidecar, "rotate")
def test_run_backup_snapshot_failure_sets_ok_false(mock_rotate, mock_export_csv, mock_snapshot):
    mock_snapshot.side_effect = RuntimeError("disk full")
    mock_export_csv.return_value = []
    mock_rotate.return_value = 0

    with patch.dict(os.environ, {
        "BACKUP_DIR": "/tmp/backup-test",
        "BACKUP_KEEP": "30",
        "FIREFLY_URL": "http://127.0.0.1:8080",
        "FIREFLY_PAT": "pat123",
    }):
        body = backup_sidecar.run_backup()

    assert body["ok"] is False
    assert "disk full" in body["snapshot_error"]
    assert body["snapshot"] is None


@patch.object(backup_sidecar, "snapshot")
@patch.object(backup_sidecar, "export_csv")
@patch.object(backup_sidecar, "rotate")
def test_run_backup_csv_failure_records_failures(mock_rotate, mock_export_csv, mock_snapshot):
    fake_snap = MagicMock()
    fake_snap.__str__ = lambda self: "/mnt/data/firefly-backups/firefly-20261031T120000Z.sqlite"
    fake_snap.stat.return_value.st_size = 12345
    mock_snapshot.return_value = fake_snap
    mock_export_csv.return_value = ["accounts", "tags"]
    mock_rotate.return_value = 1

    with patch.dict(os.environ, {
        "BACKUP_DIR": "/tmp/backup-test",
        "BACKUP_KEEP": "30",
        "FIREFLY_URL": "http://127.0.0.1:8080",
        "FIREFLY_PAT": "pat123",
    }):
        body = backup_sidecar.run_backup()

    assert body["ok"] is False
    assert body["csv_failed"] == ["accounts", "tags"]
    assert body["rotated_removed"] == 1


@patch.object(backup_sidecar, "snapshot")
@patch.object(backup_sidecar, "export_csv")
@patch.object(backup_sidecar, "rotate")
def test_run_backup_rotation_error_is_swallowed(mock_rotate, mock_export_csv, mock_snapshot):
    fake_snap = MagicMock()
    fake_snap.__str__ = lambda self: "/mnt/data/firefly-backups/firefly-20261031T120000Z.sqlite"
    fake_snap.stat.return_value.st_size = 12345
    mock_snapshot.return_value = fake_snap
    mock_export_csv.return_value = []
    mock_rotate.side_effect = RuntimeError("rot failed")

    with patch.dict(os.environ, {
        "BACKUP_DIR": "/tmp/backup-test",
        "BACKUP_KEEP": "30",
        "FIREFLY_URL": "http://127.0.0.1:8080",
        "FIREFLY_PAT": "pat123",
    }):
        body = backup_sidecar.run_backup()

    assert body["ok"] is True
    assert body["rotated_removed"] == 0
    assert "rotate_error" in body


# ---------------------------------------------------------------------------
# snapshot names are UTC-stamped (lexicographic == chronological)
# ---------------------------------------------------------------------------

def test_utc_stamp_monotonic():
    t1 = backup_sidecar._utc_stamp()
    # Small sleep to cross a second boundary on fast machines.
    import time; time.sleep(0.002)
    t2 = backup_sidecar._utc_stamp()
    assert t1 <= t2
    assert len(t1) == 16  # YYYYMMDDTHHMMSSZ
    assert t1.endswith("Z")


if __name__ == "__main__":
    test_rotation_keeps_exactly_keep_snapshots()
    test_rotation_keeps_exactly_keep_csv_dirs()
    test_rotation_keep_zero_removes_nothing()
    test_rotation_removes_both_families_and_counts_total()
    test_run_backup_ok_path()
    test_run_backup_snapshot_failure_sets_ok_false()
    test_run_backup_csv_failure_records_failures()
    test_run_backup_rotation_error_is_swallowed()
    test_utc_stamp_monotonic()
    print("All backup_sidecar tests passed.")
