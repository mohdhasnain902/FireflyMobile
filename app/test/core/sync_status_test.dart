import 'package:firefly_mobile/core/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-Dart unit tests for the app-bar sync snapshot (P2.3).
///
/// Covers every state-resolution path plus the `formatLastSync` helper.
void main() {
  group('AppSyncStatus.state resolution', () {
    test('no data → never', () {
      const s = AppSyncStatus(pendingOps: 0);
      expect(s.state, SyncState.never);
    });

    test('pending only → pending', () {
      const s = AppSyncStatus(pendingOps: 3);
      expect(s.state, SyncState.pending);
    });

    test('synced only → synced', () {
      const s = AppSyncStatus(
        pendingOps: 0,
        lastSyncTsMs: 1700000000000,
        lastSyncStatus: 'ok',
      );
      expect(s.state, SyncState.synced);
    });

    test('error status wins over synced timestamp', () {
      const s = AppSyncStatus(
        pendingOps: 0,
        lastSyncTsMs: 1700000000000,
        lastSyncStatus: 'error',
      );
      expect(s.state, SyncState.error);
    });

    test('error status wins over pending backlog', () {
      const s = AppSyncStatus(pendingOps: 5, lastSyncStatus: 'error');
      expect(s.state, SyncState.error);
    });

    test('pending wins when last sync succeeded but backlog remains', () {
      const s = AppSyncStatus(
        pendingOps: 2,
        lastSyncTsMs: 1700000000000,
        lastSyncStatus: 'ok',
      );
      expect(s.state, SyncState.pending);
    });
  });

  group('formatLastSync', () {
    final fixedNow = DateTime(2026, 10, 16, 14, 30);

    test('same-day timestamp formats as HH:mm', () {
      final ts = DateTime(2026, 10, 16, 9, 5).millisecondsSinceEpoch;
      expect(formatLastSync(ts, now: fixedNow), '09:05');
    });

    test('cross-day timestamp formats as yyyy-MM-dd HH:mm', () {
      final ts = DateTime(2026, 10, 15, 23, 59).millisecondsSinceEpoch;
      expect(formatLastSync(ts, now: fixedNow), '2026-10-15 23:59');
    });

    test('minute is zero-padded', () {
      final ts = DateTime(2026, 10, 16, 7, 3).millisecondsSinceEpoch;
      expect(formatLastSync(ts, now: fixedNow), '07:03');
    });
  });
}
