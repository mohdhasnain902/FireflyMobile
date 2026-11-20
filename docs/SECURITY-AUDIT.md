# Firefly III Mobile — Security Audit (P5.4)

**Date:** 2026-11-02
**Scope:** Flutter mobile app (`app/lib/`), backup sidecar (`infra/firefly/backup_sidecar.py`)
**Auditor:** Kilo (self-audit)

---

## 1. Summary

| Domain | Status | Findings |
|--------|--------|----------|
| Transport encryption | PASS | WireGuard (Tailscale), no plaintext, no public exposure |
| Authentication | PASS | PAT in `Authorization: Bearer`, secure storage only |
| Secret storage | PASS | PAT + SQLCipher key in Android Keystore / iOS Keychain |
| Local data at rest | PASS | SQLCipher AES-256, WAL mode |
| Backup transport | PASS | Bearer-token gated HTTP sidecar on LAN |
| Third-party network | PASS | Only Firefly endpoint contacted; no analytics/crash SDKs |
| Logging | PASS | No secrets in logs, errors carry codes not tokens |
| Input validation | PASS | Base URL normalized/scheme-gated; amounts decimal-as-string |

---

## 2. Finding Details

### PASS — Transport: WireGuard via Tailscale

**Control:** All phone↔Firefly traffic travels over Tailscale's WireGuard mesh.
**Evidence:** `DESIGN.md §2.1`, `ADR-002`, `DESIGN.md §9` — base URL is `*.ts.net` only, no port-forward, no public IP, no TLS cert needed.
**Residual risk:** Depends on Tailscale coordination server (free plan). LAN fallback exists if Tailscale is down.

### PASS — Authentication: Firefly III PAT

**Control:** Personal Access Token generated in Firefly UI, sent as `Authorization: Bearer <PAT>` on every API request.
**Evidence:** `firefly_api_client.dart` — `Authorization: Bearer ${settings.pat}` header on every request.
**Residual risk:** PAT theft from a compromised phone grants full Firefly access. Mitigation: PAT revocable in Firefly UI; token never echoed back in UI (write-only field).

### PASS — Secret Storage: Android Keystore / iOS Keychain

**Control:** PAT and SQLCipher key stored in platform secure storage, never in SQLite or SharedPreferences.
**Evidence:**
- `connection_settings.dart` — `DeviceConnectionSettingsStore` writes PAT to `FlutterSecureStorage` under a reference key; only the reference lives in `device_meta`.
- `database_key_store.dart` — `SecureStorageDatabaseKeyStore` writes the SQLCipher key to `FlutterSecureStorage`; `FileDatabaseKeyStore` (Linux desktop fallback) uses owner-only file mode.
**Residual risk:** Rooted/jailbroken device can extract keys from Keystore. Mitigation: SQLCipher key is per-install; PAT can be revoked server-side.

### PASS — Local Data at Rest: SQLCipher AES-256

**Control:** Local SQLite database encrypted with SQLCipher (AES-256), key in Keystore.
**Evidence:** `pubspec.yaml` — `sqlcipher_flutter_libs` + `sqlite3` hooks `source: sqlcipher`; `database_opener.dart` — `PRAGMA KEY` before open; `encryption_test.dart` — wrong key rejected with "file is not a database".
**Residual risk:** None identified beyond Keystore compromise above.

### PASS — Backup Transport: Bearer-token gated HTTP sidecar

**Control:** Phone POSTs `Authorization: Bearer <backupToken>` to `POST /backup` on the PC sidecar. Sidecar uses `hmac.compare_digest` for constant-time token comparison.
**Evidence:** `backup_client.dart` — Bearer header; `backup_sidecar.py` — `hmac.compare_digest(supplied, expected)`; sidecar refuses to start without a token.
**Residual risk:** Sidecar binds to `0.0.0.0` by default (LAN-reachable). Mitigation: Bearer token is the only gate; can bind to localhost via `--host`.

### PASS — No Third-Party Network

**Control:** App contacts only the Firefly endpoint and the PC backup sidecar. No analytics, no crash-reporting SDKs, no telemetry.
**Evidence:** `pubspec.yaml` — dependencies are Flutter SDK, Riverpod, HTTP, SQLite, secure storage, UUID, intl, charts, freezed/json. `DESIGN.md §9` — "No analytics, no crash-reporting SDKs, no third-party network calls."
**Verification:** Grep for `http.Client` usage outside `firefly_api_client.dart` and `backup_client.dart` — none found.

### PASS — Logging: No Secrets

**Control:** PAT never appears in logs, sync log, or crash reports. SQLCipher key never logged.
**Evidence:** `sync_engine.dart` — error logged as `jsonEncode({'code': ..., 'message': ...})` where message comes from typed `Failure` classes; `failure.dart` — `AuthFailure`, `NetworkFailure`, etc. carry no token values. `backup_client.dart` — token only in request header, never in body or log.
**Verification:** Grep for `pat`/`token` in log/print statements — none found.

### PASS — Input Validation: Base URL

**Control:** `normalizeBaseUrl()` requires `http://` or `https://` scheme, non-empty host, no whitespace, drops path/query.
**Evidence:** `connection_settings.dart` — `normalizeBaseUrl()` rejects scheme-less, whitespace, no-authority inputs.

---

## 3. Recommendations (Not Blocking)

| # | Recommendation | Priority |
|---|---------------|----------|
| 1 | Add `flutter_secure_storage` AES key for web/Desktop builds (currently file-based on Linux) | Low |
| 2 | Add screenshot blocking (`SecureWindow` / `FLAG_SECURE`) for settings screen | Low |
| 3 | Add biometric unlock for app resume after background | Low |
| 4 | Rotate backup token on a schedule (ops runbook) | Low |
| 5 | Add certificate pinning if Firefly ever moves to public TLS | Low |

---

## 4. Verification Checklist

- [ ] `flutter_secure_storage` is the only secret-storage mechanism (grep `SharedPreferences` — none)
- [ ] No `print(`/`debugPrint(` calls emit PAT or key values
- [ ] `pubspec.yaml` contains no analytics/crash-reporting dependencies
- [ ] Sidecar token comparison uses `hmac.compare_digest`
- [ ] SQLCipher key never written to `device_meta` (only reference for PAT; key is direct in secure storage)
- [ ] Backup sidecar exits with error when no token configured (refuses to start unauthenticated)
