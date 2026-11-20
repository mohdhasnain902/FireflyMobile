# Firefly III Mobile — Operations Runbook

**Audience:** The self-hosting user (you). Covers Firefly upgrades, Tailscale key rotation, backup rotation, and incident response.

---

## 1. Firefly III Upgrade Checklist

The Docker image is **pinned** to `fireflyiii/core:version-6.7.9` (see `infra/firefly/docker-compose.yml`). Never use `latest` — DESIGN R9 makes the golden-API-fixture contract depend on a fixed server version.

### Before upgrading

1. Read the Firefly III changelog for the target version.
2. Run the golden-fixture diff locally:
   ```sh
   cd app
   flutter test test/api_fixtures_smoke_test.dart
   ```
   If fixtures changed, re-capture them against the new instance and commit.
3. Back up the Firefly database volume:
   ```sh
   docker cp firefly_iii_core:/var/www/html/storage/database/database.sqlite \
     ~/firefly-backups/pre-upgrade-$(date +%Y%m%dT%H%M%S).sqlite
   ```

### Upgrade

1. Edit `infra/firefly/docker-compose.yml`: change the `image:` pin.
2. `docker compose pull && docker compose up -d`
3. Verify: open `http://localhost:8080`, log in, confirm data intact.
4. Re-run golden fixtures: `flutter test test/api_fixtures_smoke_test.dart`
5. Run a live e2e sync: `FIREFLY_LIVE=1 flutter test test/integration/live_sync_e2e_test.dart`

---

## 2. Tailscale Key Rotation

Tailscale auth keys expire. When the phone can no longer reach `firefly.<host>.ts.net`:

1. On the PC: `tailscale up --authkey <new-key>` (or re-authenticate via web).
2. On the phone: re-authenticate in the Tailscale app.
3. Verify: `ping firefly.<pc-hostname>.ts.net` from the phone.
4. If sync was failing, the sync log shows a clear error; once Tailscale is restored, the next auto-sync (app foreground) resumes automatically.

---

## 3. Backup Rotation Policy

The sidecar keeps the last `BACKUP_KEEP` (default 30) snapshots and CSV dirs. Older ones are deleted on every backup run.

### To change retention

Edit the sidecar's environment or `.env`:
```
BACKUP_KEEP=60
```
Then restart the sidecar.

### To manually trigger a backup

```sh
cd infra/firefly
python3 backup_sidecar.py --once
```

### To restore from a snapshot

1. Copy the snapshot into the Firefly volume:
   ```sh
   docker cp firefly-20261031T120000Z.sqlite \
     firefly_iii_core:/var/www/html/storage/database/database.sqlite
   ```
2. Restart the `firefly_iii_core` container.
3. On the phone: **Settings → Restore from server**.

---

## 4. Incident Response

| Symptom | Likely Cause | First Response |
|---------|-------------|----------------|
| Sync fails with "unreachable" | Tailscale down, PC off | Check Tailscale on both ends; ping `*.ts.net` |
| Sync fails with "HTTP 401" | Bad/expired PAT | Regenerate PAT in Firefly UI; update in Settings |
| Backup fails with 401 | Expired sidecar token | Regenerate token in `.backup_token`; restart sidecar |
| Rows show `conflict` badge | Server won LWW on a prior pull | Informational only; edit locally to override on next push |
| App can't open (wrong SQLCipher key) | DB key mismatch | Uninstall + reinstall; restore from server |
| Missing rows after sync | Pull skipped pending rows | Push pending ops first (auto on next foreground sync) |

### Data loss scenarios

- **Phone lost/stolen:** SQLCipher-encrypted DB + Keystore-protected PAT. Revoke the PAT in Firefly UI. Restore from the latest PC backup on a new phone.
- **PC disk failure:** Restore Firefly from the latest `firefly-*.sqlite` snapshot in `~/firefly-backups/`.
- **App killed mid-sync:** Op-log is intact (SQLite WAL). On relaunch, sync resumes from where it left off; no duplicates (op_id idempotency + firefly_id check).

---

## 5. Maintenance Commands

```sh
# Check sidecar health
curl http://<pc-tailscale-ip>:8095/healthz

# List backups (newest first)
ls -t ~/firefly-backups/firefly-*.sqlite | head -5

# Check Docker container status
docker compose -f infra/firefly/docker-compose.yml ps

# View Firefly logs
docker logs firefly_iii_core
docker logs firefly_iii_cron

# Prune old backups manually (beyond sidecar rotation)
ls -t ~/firefly-backups/firefly-*.sqlite | tail -n +31 | xargs rm -f
```

---

## 6. Installing a build on the phone (USB drops)

`adb install` uses a streamed install; on the LDN-L21 the transfer drops
mid-stream (`adb: failed to install …:` with no reason, and the device
disappearing from `adb devices`) — the kernel log shows
`usb usb1-port2: Cannot enable. Maybe the USB cable is bad?`. A smaller APK plus
an install from the device's own filesystem is reliable:

```sh
cd app
/mnt/data/opencode/tools/flutter/bin/flutter build apk --debug \
    --target-platform android-arm64        # 171 MB vs 204 MB universal

adb push build/app/outputs/flutter-apk/app-debug.apk /data/local/tmp/ff.apk
adb shell pm install -r /data/local/tmp/ff.apk     # prints Success
adb shell am force-stop com.firefly.firefly_mobile
adb shell am start -n com.firefly.firefly_mobile/.MainActivity
```

If the phone appears in `lsusb` (`12d1:107d`) but not in `adb devices`:

```sh
adb kill-server && adb start-server
```

`pm install -r` keeps app data, so the encrypted database (and its Keystore
key) survives and only schema migrations run — the intended upgrade path.

After installing, verify on the phone itself, not on a database copy:

```sh
adb shell "run-as com.firefly.firefly_mobile cat databases/firefly.db" > /tmp/d/firefly.db
adb shell "run-as com.firefly.firefly_mobile cat databases/firefly.db-wal" > /tmp/d/firefly.db-wal
python3 scripts/audit_entity_parity.py  --db /tmp/d/firefly.db --token-file <token>
python3 scripts/verify_sync_parity.py   --db /tmp/d/firefly.db --token-file <token>
```
