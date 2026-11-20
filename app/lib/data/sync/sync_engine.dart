import 'dart:convert';

import 'package:firefly_mobile/core/errors/failure.dart';
import 'package:firefly_mobile/core/utils/result.dart';
import 'package:firefly_mobile/data/api/firefly_api_client.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/sync/backup_client.dart';
import 'package:firefly_mobile/data/sync/op_log_pusher.dart';
import 'package:firefly_mobile/data/sync/pull_engine.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// A single line in the in-app sync log (P3.4).
///
/// The log is a human-readable audit trail of the last [kMaxSyncLogEntries]
/// cycles, shown on the settings/sync screen so a user can see what the last
/// sync actually did without leaving the app.
class SyncLogEntry {
  /// Builds one log row.
  const new({
    required this.id,
    required this.startedAtMs,
    required this.phase,
    required this.status,
    this.pushedOps,
    this.pullInserted,
    this.pullUpdated,
    this.pullTombstoned,
    this.error,
  });

  /// Reads a row back out of the `sync_log` table.
  factory fromRow(Map<String, Object?> row) => SyncLogEntry(
    id: row['id']! as int,
    startedAtMs: row['started_at']! as int,
    phase: row['phase']! as String,
    status: row['status']! as String,
    pushedOps: row['pushed_ops'] as int?,
    pullInserted: row['pull_inserted'] as int?,
    pullUpdated: row['pull_updated'] as int?,
    pullTombstoned: row['pull_tombstoned'] as int?,
    error: row['error'] as String?,
  );

  /// Auto-increment primary key.
  final int id;

  /// Epoch-ms when the cycle started.
  final int startedAtMs;

  /// The phase that produced this line: `push` or `pull`.
  final String phase;

  /// `ok` or `error`.
  final String status;

  /// Ops acknowledged during the push phase (push lines only).
  final int? pushedOps;

  /// Rows inserted by the pull phase (pull lines only).
  final int? pullInserted;

  /// Rows updated by the pull phase (pull lines only).
  final int? pullUpdated;

  /// Rows tombstoned by the pull phase (pull lines only).
  final int? pullTombstoned;

  /// Failure message when [status] is `error`, else null.
  final String? error;
}

/// Cap on retained sync-log rows; older rows are pruned after each cycle.
const int kMaxSyncLogEntries = 500;

/// Outcome of one [SyncEngine.sync] call: whether it succeeded, how much it
/// pushed and pulled, and the failure (if any) that stopped it.
class SyncOutcome {
  /// Builds the aggregate result of a full cycle.
  const new({
    required this.ok,
    required this.pushedOps,
    required this.pull,
    this.failure,
  });

  /// True when the whole cycle (push and pull) completed without failure.
  final bool ok;

  /// Ops acknowledged during push. Always 0 when push failed.
  final int pushedOps;

  /// Pull stats; null only when the pull could not run at all.
  final PullStats? pull;

  /// The failure that stopped the cycle, or null on success.
  final Failure? failure;
}

class _PhaseResult {
  const _PhaseResult({required this.ok, required this.pushedOps, this.failure});
  final bool ok;
  final int pushedOps;
  final Failure? failure;
}

class _PullPhaseResult {
  const _PullPhaseResult({required this.ok, this.stats, this.failure});
  final bool ok;
  final PullStats? stats;
  final Failure? failure;
}

/// Runs one full sync cycle: push the op log, then pull a server diff.
///
/// The engine is the caller [OpLogPusher] was written for (see its docstring).
/// It owns the push→pull ordering and the two side effects neither sub-engine
/// handles:
///
/// 1. **device_meta bookkeeping** — `last_sync_ts` and `last_sync_status` are
///    written after each phase so the app-bar indicator (P2.3) reflects the
///    outcome of the last cycle.
/// 2. **the in-app sync log** — one `push` line and (when reached) one `pull`
///    line are appended per cycle and pruned to [kMaxSyncLogEntries].
///
/// Ordering follows DESIGN §7: push first (so our local edits are on the
/// server before we read its state back), then pull. A replay failure is
/// reported by [OpLogPusher.pushBatch] as `Ok(PushOutcome.stopped)`, which
/// this engine reclassifies into a failing cycle (the client already retried
/// transient errors internally).
///
/// **A failed push never skips the pull.** Until R38 a single unreplayable op
/// (for example an edit to a row the user just deleted on the website, which
/// answers 404/422 forever) returned before the pull ran, so website-side
/// deletions and edits never reached the phone: the account disappeared from
/// Firefly and stayed on the device for good. The pull is the only phase that
/// can heal that state, so it runs unconditionally; the cycle still reports
/// the push failure when there is one.
///
/// Pure Dart: no Flutter/Riverpod imports. Time and database access are
/// injected so every branch is unit-testable against an in-memory SQLite
/// connection and a fixed clock.
void _syncLog(String msg) {
  // ignore: avoid_print
  print('[sync] $msg');
}

class SyncEngine {
  /// Builds an engine bound to an open connection, an API client, and the two
  /// sub-engines.
  ///
  /// [now] is injectable for deterministic tests; it defaults to the real
  /// clock. It is called at most three times per cycle (once each for the
  /// push, pull and — when the PC backup is configured — backup lines).
  /// [backup] is optional; when null the cycle behaves exactly as before P4.
  new({
    required Database db,
    required FireflyApiClient client,
    BackupClient? backup,
    DateTime Function()? now,
  }) : this.withEngines(
         db: db,
         pusher: OpLogPusher(db: db, client: client),
         puller: PullEngine(db: db, client: client),
         backup: backup,
         now: now,
       );

  /// Builds an engine from pre-constructed sub-engines (test seam).
  new withEngines({
    required Database db,
    required this._pusher,
    required this._puller,
    this._backup,
    DateTime Function()? now,
  }) : _db = db,
       _meta = DeviceMetaDao(db),
       _now = now ?? DateTime.now;

  final Database _db;
  final OpLogPusher _pusher;
  final PullEngine _puller;
  final BackupClient? _backup;
  final DeviceMetaDao _meta;
  final DateTime Function() _now;

  /// Runs one push→pull cycle (both directions).
  ///
  /// Push loops in batches until the queue reports [PushOutcome.empty]; the
  /// first [PushOutcome.stopped] stops the cycle before pull and records a
  /// failing `push` line. Pull runs once and records a `pull` line. The return
  /// value mirrors what actually happened: `ok` is true only when both phases
  /// finished clean.
  Future<SyncOutcome> sync() async {
    _syncLog('cycle start: push then pull');
    final push = await _pushAll();
    // The pull runs even when the push failed for a *server-side* reason: the
    // server is the authority on what still exists, and a stuck op (404/422)
    // must not stop the phone from learning about a website-side deletion
    // (R38). A transport failure is the one exception — the socket is down, so
    // every pull request would fail the same way after its retries.
    if (!push.ok && push.failure is NetworkFailure) {
      _syncLog('pull skipped: push failed with a network error');
      return SyncOutcome(
        ok: false,
        pushedOps: push.pushedOps,
        pull: null,
        failure: push.failure,
      );
    }
    final pull = await _pullAll();
    if (!pull.ok) {
      return SyncOutcome(
        ok: false,
        pushedOps: push.pushedOps,
        pull: pull.stats,
        failure: push.ok || push.failure == null
            ? pull.failure
            : ServerFailure(
                'Phone → website failed (${push.failure!.message}); '
                'website → phone failed (${pull.failure!.message}).',
                code: pull.failure!.code,
              ),
      );
    }
    if (!push.ok) {
      return SyncOutcome(
        ok: false,
        pushedOps: push.pushedOps,
        pull: pull.stats,
        failure: push.failure,
      );
    }
    // PC backup (best-effort) only after a fully successful two-way cycle.
    await _runBackup();
    return SyncOutcome(ok: true, pushedOps: push.pushedOps, pull: pull.stats);
  }

  /// Syncs phone data to the website only (push local queued ops).
  Future<SyncOutcome> pushOnly() async {
    _syncLog('pushOnly start (phone -> website)');
    final push = await _pushAll();
    return SyncOutcome(
      ok: push.ok,
      pushedOps: push.pushedOps,
      pull: null,
      failure: push.failure,
    );
  }

  /// Syncs website data to the phone only (pull server diff/records).
  Future<SyncOutcome> pullOnly() async {
    _syncLog('pullOnly start (website -> phone)');
    final pull = await _pullAll();
    return SyncOutcome(
      ok: pull.ok,
      pushedOps: 0,
      pull: pull.stats,
      failure: pull.failure,
    );
  }

  Future<_PhaseResult> _pushAll() async {
    var pushed = 0;
    while (true) {
      final result = await _pusher.pushBatch();
      final failure = result.failureOrNull;
      if (failure != null) {
        await _record('push', 'error', error: failure, startedAt: _now());
        await _setLastStatus('error');
        return _PhaseResult(ok: false, pushedOps: pushed, failure: failure);
      }
      final outcome = result.valueOrNull!;
      if (outcome == PushOutcome.empty) break;
      if (outcome == PushOutcome.stopped) {
        const failure = ServerFailure(
          'sync stopped during push; an op failed to replay',
        );
        await _record('push', 'error', error: failure, startedAt: _now());
        await _setLastStatus('error');
        return _PhaseResult(ok: false, pushedOps: pushed, failure: failure);
      }
      pushed += kSyncBatchSize;
    }
    _syncLog('push ok: pushedOps=$pushed');
    await _record('push', 'ok', pushedOps: pushed, startedAt: _now());
    await _setLastStatus('ok');
    return _PhaseResult(ok: true, pushedOps: pushed);
  }

  Future<_PullPhaseResult> _pullAll() async {
    final pullResult = await _puller.pullAll();
    final pullFailure = pullResult.failureOrNull;
    if (pullFailure != null) {
      _syncLog('pull error: ${pullFailure.code} ${pullFailure.message}');
      await _record('pull', 'error', error: pullFailure, startedAt: _now());
      await _setLastStatus('error');
      return _PullPhaseResult(ok: false, failure: pullFailure);
    }
    final pullStats = pullResult.valueOrNull!;
    // A pull continues past an entity that failed (R39) — the other entities
    // still converge — but the cycle is reported as failed so the user knows
    // something did not arrive.
    final entityFailure = pullStats.firstFailure;
    if (entityFailure != null) {
      _syncLog(
        'pull partial: ${entityFailure.code} ${entityFailure.message}; '
        'entities failed: ${pullStats.failures.keys.join(', ')}',
      );
      await _record(
        'pull',
        'error',
        error: entityFailure,
        startedAt: _now(),
        pullInserted: pullStats.inserted,
        pullUpdated: pullStats.updated,
        pullTombstoned: pullStats.tombstoned,
      );
      await _setLastSynced(_now().millisecondsSinceEpoch);
      await _setLastStatus('error');
      return _PullPhaseResult(
        ok: false,
        stats: pullStats,
        failure: entityFailure,
      );
    }
    _syncLog('pull ok: inserted=${pullStats.inserted} updated=${pullStats.updated} tombstoned=${pullStats.tombstoned}');
    await _record(
      'pull',
      'ok',
      pullInserted: pullStats.inserted,
      pullUpdated: pullStats.updated,
      pullTombstoned: pullStats.tombstoned,
      startedAt: _now(),
    );
    await _setLastSynced(_now().millisecondsSinceEpoch);
    await _setLastStatus('ok');
    return _PullPhaseResult(ok: true, stats: pullStats);
  }

  /// Full "restore from server" pass: wipe every local synced-entity row and
  /// re-download the whole account, used when the user re-installs or links a
  /// new account.
  ///
  /// Restore is an explicit "discard local, take the server" action, so a
  /// single transaction drops the queued edits (`op_log`) *and* every entity
  /// table [kPullEntityTypes] plus `recurrence_repetitions` (14 tables
  /// total) before [PullEngine.pullAll] runs. The wipe matters because the
  /// pull's merge is LWW-on-seen: rows that exist only locally — or were
  /// deleted server-side since the last sync — would otherwise survive the
  /// merge untouched. `attachments` is deliberately kept (it points at server
  /// files by id, so re-downloads stay valid), and `device_meta`/`sync_log`
  /// are device/audit state, not synced entities. If the pull fails
  /// afterwards the local data stays wiped and the status flips to `error`,
  /// which is the honest state: local == empty, server unreachable. Returns
  /// the [PullStats] the pull produced.
  Future<Result<PullStats>> restoreFromServer() async {
    // Wipe + op_log in one transaction so a crash cannot leave a half-wiped
    // queue behind.
    await _db.transaction((txn) async {
      await txn.delete('op_log');
      for (final table in kPullEntityTypes) {
        await txn.delete(table);
      }
      await txn.delete('recurrence_repetitions');
    });
    final result = await _puller.pullAll();
    final failure = result.failureOrNull;
    if (failure != null) {
      await _setLastStatus('error');
      return Err<PullStats>(failure);
    }
    final entityFailure = result.valueOrNull!.firstFailure;
    if (entityFailure != null) {
      await _setLastSynced(_now().millisecondsSinceEpoch);
      await _setLastStatus('error');
      return Err<PullStats>(entityFailure);
    }
    await _setLastSynced(_now().millisecondsSinceEpoch);
    await _setLastStatus('ok');
    return result;
  }

  /// Reads the most recent [limit] sync-log lines, newest first.
  Future<List<SyncLogEntry>> recentLog({int limit = 20}) async {
    final rows = await _db.query(
      'sync_log',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(SyncLogEntry.fromRow).toList();
  }

  // -------------------------------------------------------------------------
  // Side effects
  // -------------------------------------------------------------------------

  /// Fires the PC backup sidecar and records one `backup` log line (P4).
  ///
  /// Rules:
  /// * no [BackupClient] injected, or the backup URL is unset → one
  ///   `backup`/`skipped` line saying why, so an unconfigured backup cannot
  ///   be mistaken for a broken button;
  /// * success → one `backup`/`ok` line;
  /// * failure (unreachable PC, rejected token, sidecar `ok:false`) → one
  ///   `backup`/`error` line carrying the failure message;
  /// * an unexpected throw is swallowed — this method can never fail a sync
  ///   cycle that already succeeded.
  ///
  /// Deliberately NOT called from `restoreFromServer`: restoring local state
  /// from the server must not re-trigger the very backup workflow it is
  /// part of (DESIGN §8 restore drill).
  Future<void> _runBackup() async {
    final client = _backup;
    if (client == null) {
      await _recordBackupSkipped(
        'No backup URL saved — set one in Settings to back up to the PC.',
      );
      return;
    }
    try {
      final result = await client.trigger();
      final failure = result.failureOrNull;
      if (failure != null) {
        await _record('backup', 'error', error: failure, startedAt: _now());
        return;
      }
      final report = result.valueOrNull!;
      if (report.isDisabled) {
        await _recordBackupSkipped(
          'No backup URL saved — set one in Settings to back up to the PC.',
        );
        return;
      }
      await _record('backup', 'ok', startedAt: _now());
    } on Object catch (_) {
      // Best-effort by contract (class docs): the successful sync stands.
    }
  }

  /// Logs that a backup was asked for but could not run because nothing is
  /// configured.
  ///
  /// Silently doing nothing made "backup" look broken: the sync finished, no
  /// backup file appeared and the log had no row about it at all.
  Future<void> _recordBackupSkipped(String reason) => _record(
    'backup',
    'skipped',
    startedAt: _now(),
    error: ValidationFailure(reason, code: 'backup.unconfigured'),
  );

  /// Appends one sync-log line and prunes the table to [kMaxSyncLogEntries].
  Future<void> _record(
    String phase,
    String status, {
    required DateTime startedAt, int? pushedOps,
    int? pullInserted,
    int? pullUpdated,
    int? pullTombstoned,
    Failure? error,
  }) async {
    await _db.insert('sync_log', {
      'started_at': startedAt.millisecondsSinceEpoch,
      'phase': phase,
      'status': status,
      'pushed_ops': pushedOps,
      'pull_inserted': pullInserted,
      'pull_updated': pullUpdated,
      'pull_tombstoned': pullTombstoned,
      'error': error == null
          ? null
          : jsonEncode({'code': error.code, 'message': error.message}),
    });
    // Keep only the newest rows (DESIGN §7.4).
    await _db.execute('''
      DELETE FROM sync_log
      WHERE id NOT IN (
        SELECT id FROM sync_log ORDER BY id DESC LIMIT $kMaxSyncLogEntries
      )
    ''');
  }

  Future<void> _setLastSynced(int tsMs) =>
      _meta.set(DeviceMetaDao.lastSyncTsKey, tsMs.toString());

  Future<void> _setLastStatus(String status) =>
      _meta.set(DeviceMetaDao.lastSyncStatusKey, status);
}
