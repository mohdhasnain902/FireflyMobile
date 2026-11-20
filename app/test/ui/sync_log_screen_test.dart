import 'dart:async';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/data/sync/sync_engine.dart' show SyncLogEntry;
import 'package:firefly_mobile/ui/screens/sync_log_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the in-app sync audit trail (P3.4, Story 2).
///
/// The log provider is always stubbed at the Future level — these tests
/// cover rendering, ordering, the three async states and pull-to-refresh,
/// not the query (that path is pinned by the engine's own sync-log tests).
/// No network and no database are touched anywhere here.
void main() {
  /// Epoch helper: local wall-clock milliseconds for [_fmtTime]'s format.
  int ms(int h, int m, int s) =>
      DateTime(2026, 10, 18, h, m, s).millisecondsSinceEpoch;

  /// Pumps [SyncLogScreen] whose log query is served by [load].
  /// [settle] is false for pending loads: the indeterminate spinner keeps
  /// scheduling frames, so `pumpAndSettle` would never return.
  Future<void> pumpLog(
    WidgetTester tester, {
    required Future<List<SyncLogEntry>> Function() load,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syncLogProvider.overrideWith((_) => load())],
        child: const MaterialApp(home: SyncLogScreen()),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('renders rows newest first with counters, time and errors', (
    tester,
  ) async {
    await pumpLog(
      tester,
      load: () async => <SyncLogEntry>[
        SyncLogEntry(
          id: 3,
          startedAtMs: ms(9, 5, 3),
          phase: 'pull',
          status: 'error',
          error: 'HTTP 500 from server',
        ),
        SyncLogEntry(
          id: 2,
          startedAtMs: ms(9, 4, 10),
          phase: 'pull',
          status: 'ok',
          pullInserted: 3,
          pullUpdated: 2,
          pullTombstoned: 1,
        ),
        SyncLogEntry(
          id: 1,
          startedAtMs: ms(9, 0, 0),
          phase: 'push',
          status: 'ok',
          pushedOps: 12,
        ),
      ],
    );

    // App-bar route title.
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Sync log'),
      ),
      findsOneWidget,
    );
    // One push row + two pull rows; newest (error) first.
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Pull'), findsNWidgets(2));
    expect(find.text('12 ops pushed'), findsOneWidget);
    expect(find.text('+3 new, ~2 changed, −1 removed'), findsOneWidget);
    expect(find.text('HTTP 500 from server'), findsOneWidget);
    expect(find.text('2026-10-18 09:05:03'), findsOneWidget);

    // Vertical order: id3 (error) on top, id1 (push) at the bottom.
    final errorY = tester.getTopLeft(
      find.text('HTTP 500 from server'),
    ).dy;
    final countsY = tester.getTopLeft(
      find.text('+3 new, ~2 changed, −1 removed'),
    ).dy;
    final pushY = tester.getTopLeft(find.text('Push')).dy;
    expect(errorY, lessThan(countsY));
    expect(countsY, lessThan(pushY));
  });

  testWidgets('empty log explains how to create one', (tester) async {
    await pumpLog(tester, load: () async => <SyncLogEntry>[]);

    expect(find.text('No syncs yet'), findsOneWidget);
    expect(
      find.text('Run one from Settings → Sync now.'),
      findsOneWidget,
    );
  });

  testWidgets('failed query shows the error state with a retry hint', (
    tester,
  ) async {
    await pumpLog(
      tester,
      load: () async => throw StateError('disk exploded'),
    );

    expect(find.textContaining('Sync log unavailable'), findsOneWidget);
    expect(find.text('Pull down to retry.'), findsOneWidget);
  });

  testWidgets('shows the loading spinner while the query is pending', (
    tester,
  ) async {
    final pending = Completer<List<SyncLogEntry>>();
    await pumpLog(tester, load: () => pending.future, settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No syncs yet'), findsNothing);
    // Never completed on purpose: nothing to settle after this.
  });

  testWidgets('pull-to-refresh surfaces rows added by a newer cycle', (
    tester,
  ) async {
    var current = <SyncLogEntry>[
      const SyncLogEntry(
        id: 1,
        startedAtMs: 1760758800000,
        phase: 'push',
        status: 'ok',
        pushedOps: 1,
      ),
    ];
    await pumpLog(tester, load: () async => List<SyncLogEntry>.of(current));

    expect(find.text('1 ops pushed'), findsOneWidget);
    expect(find.text('+9 new'), findsNothing);

    // A second cycle completes elsewhere; refresh re-runs the query.
    current = <SyncLogEntry>[
      const SyncLogEntry(
        id: 2,
        startedAtMs: 1760758860000,
        phase: 'pull',
        status: 'ok',
        pullInserted: 9,
      ),
      ...current,
    ];
    await tester.fling(
      find.byType(ListView).first,
      const Offset(0, 300),
      1000,
    );
    await tester.pump();
    // Finish the drag so RefreshIndicator fires onRefresh.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('+9 new'), findsOneWidget);
    expect(find.text('1 ops pushed'), findsOneWidget);
  });
}
