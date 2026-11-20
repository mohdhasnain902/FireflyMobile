import 'dart:async';
import 'dart:convert';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:firefly_mobile/core/utils/result.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

/// Result of a backup trigger: when the PC ran (`time`) and which snapshot
/// it created (`snapshot`), or the disabled marker when no URL is set.
@immutable
class BackupReport {
  /// Result of an accepted (HTTP 2xx, sidecar `ok:true`) trigger.
  const new({required this.time, required this.snapshot});

  /// Report returned when no backup URL is configured (feature off).
  ///
  /// The engine distinguishes this by `isDisabled` and skips the log line.
  const new disabled() : time = '', snapshot = null;

  /// Sidecar timestamp tag of the run that was created (`20261019T103129Z`).
  final String time;

  /// Absolute path of the snapshot the PC created, when reported.
  final String? snapshot;

  /// True when [BackupClient.trigger] short-circuited because no backup
  /// URL is set.
  bool get isDisabled => time.isEmpty;
}

/// Best-effort trigger for the PC backup sidecar (P4, DESIGN §8).
///
/// After every successful sync the `SyncEngine` fires one `POST {backupUrl}/backup`
/// so the PC snapshots its SQLite DB and dumps CSV exports to
/// `/mnt/data/firefly-backups`. Contract, mirroring the sidecar
/// (`infra/firefly/backup_sidecar.py`):
///
/// * **Disabled = Ok, not error** — no [ConnectionSettings.backupUrl] means
///   the feature is off; [trigger] returns [BackupReport.disabled]-style Ok
///   and the engine records NO log line (today's behaviour unchanged).
/// * **Never throws, never retries** — transport failures, timeouts, 4xx/5xx
///   all become a typed [Failure] inside [Result]. The next successful sync
///   retries naturally; a dead PC must not stall or fail the sync cycle
///   (DESIGN §8: backup failure must never fail the sync).
/// * **Sidecar `ok:false` = [ServerFailure]** — a 200 whose body reports a
///   failed snapshot/CSV run is surfaced as an error log line, because the
///   phone can then tell "PC ran but failed" from "PC reached at all".
/// * **Settings read fresh per call** — a URL/token change on the settings
///   screen takes effect on the next sync without rebuilding the client.
///
/// The token is sent as `Authorization: Bearer {backupToken}`; a missing
/// token simply produces the sidecar's 401 (surfaced as [AuthFailure]) rather
/// than a silent skip.
class BackupClient {
  /// Creates a client.
  ///
  /// `settings` is read on every [trigger]; `httpClient` and `timeout` are
  /// injectable for tests. The default 8 s covers a local-LAN snapshot (~1 s)
  /// plus 9 CSV exports (~2 s) with headroom, while bounding how long a
  /// hung PC can delay the post-sync flow.
  new({
    required this._settings,
    http.Client? httpClient,
    this._timeout = const Duration(seconds: 8),
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  final ConnectionSettingsStore _settings;
  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  /// Releases the underlying HTTP client when this instance owns it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// POSTs `/backup` to the configured sidecar. Never throws.
  Future<Result<BackupReport>> trigger() async {
    final conn = await _settings.read();
    if (!conn.isBackupConfigured) {
      return const Ok(BackupReport.disabled());
    }

    final uri = Uri.parse('${conn.backupUrl}/backup');
    final request = _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer ${conn.backupToken ?? ''}',
        'Content-Type': 'application/json',
      },
      body: '{}',
    );

    final http.Response resp;
    try {
      resp = await request.timeout(_timeout);
    } on TimeoutException {
      return Err(
        NetworkFailure(
          'Backup PC did not answer within '
          '${_timeout.inSeconds}s — is it awake on ${conn.backupUrl}?',
        ),
      );
    } on http.ClientException catch (exc) {
      // Covers connection-refused/DNS etc.: package:http's IOClient wraps
      // dart:io SocketException in a ClientException (http 1.6.0 io_client).
      return Err(NetworkFailure('Backup PC unreachable: $exc'));
    } on Object catch (exc) {
      return Err(NetworkFailure('Backup trigger failed: $exc'));
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return Err(
        AuthFailure('Backup token rejected by PC (HTTP ${resp.statusCode})'),
      );
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return Err(ServerFailure('Backup PC returned HTTP ${resp.statusCode}'));
    }

    // 2xx: parse the sidecar JSON body when present.
    var body = <String, dynamic>{};
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      // Non-JSON 200 still means the trigger was accepted; report generically.
    }

    if (body['ok'] == false) {
      return Err(ServerFailure(_sidecarFailureMessage(body)));
    }

    return Ok(
      BackupReport(
        time: body['time'] as String? ?? '',
        snapshot: body['snapshot'] as String?,
      ),
    );
  }

  /// Human-readable summary of a sidecar `ok:false` body.
  static String _sidecarFailureMessage(Map<String, dynamic> body) {
    final snapErr = body['snapshot_error'];
    if (snapErr is String && snapErr.isNotEmpty) {
      return 'Backup failed on PC: $snapErr';
    }
    final csvErr = body['csv_error'];
    if (csvErr is String && csvErr.isNotEmpty) {
      return 'Backup CSV export failed on PC: $csvErr';
    }
    final failed = body['csv_failed'];
    if (failed is List && failed.isNotEmpty) {
      return 'Backup ran on PC but ${failed.length} CSV export(s) failed';
    }
    return 'Backup reported failure on PC';
  }
}
