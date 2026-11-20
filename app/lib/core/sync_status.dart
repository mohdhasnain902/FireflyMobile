/// App-bar sync snapshot and its state resolution (P2.3).
///
/// Pure Dart — no Flutter/Riverpod imports — so the resolution rules and the
/// last-sync formatter are unit-testable without a widget harness.
library;

/// Snapshot powering the app-bar sync indicator (P2.3).
///
/// Named [AppSyncStatus] (not `SyncStatus`) to avoid colliding with the
/// per-row `SyncStatus` enum in `domain/entities/sync_bookkeeping.dart` —
/// that one is a row lifecycle, this one is the whole app's connection state.
class AppSyncStatus {
  /// Creates a snapshot.
  // ignore: unnecessary_type_name_in_constructor — generative ctor, not redirecting.
  const AppSyncStatus({
    required this.pendingOps,
    this.lastSyncTsMs,
    this.lastSyncStatus,
  });

  /// Ops still queued in `op_log` (not yet acknowledged by the server).
  final int pendingOps;

  /// Epoch-ms timestamp of the last successful sync, null when never synced.
  final int? lastSyncTsMs;

  /// Last sync outcome string from device_meta (`ok`, `error`), null if unset.
  final String? lastSyncStatus;

  /// Derived app-bar state: error beats pending beats synced beats never.
  SyncState get state {
    if (lastSyncStatus == 'error') return SyncState.error;
    if (pendingOps > 0) return SyncState.pending;
    if (lastSyncTsMs != null) return SyncState.synced;
    return SyncState.never;
  }
}

/// The four connection states the DESIGN §3.2 app-bar indicator can show.
///
/// `syncing` is intentionally absent until P3's sync engine exists — the
/// indicator must never claim work that isn't happening.
enum SyncState {
  /// No sync has ever completed and nothing is queued.
  never,

  /// Local ops are queued and waiting to be pushed.
  pending,

  /// Last sync succeeded and the op log is empty.
  synced,

  /// The most recent sync attempt reported an error.
  error,
}

/// Formats [tsMs] for the indicator: `HH:mm` when it was today (local time),
/// otherwise `yyyy-MM-dd HH:mm`. [now] is injectable for deterministic tests.
String formatLastSync(int tsMs, {DateTime? now}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
  final n = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final sameDay =
      dt.year == n.year && dt.month == n.month && dt.day == n.day;
  if (sameDay) {
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}
