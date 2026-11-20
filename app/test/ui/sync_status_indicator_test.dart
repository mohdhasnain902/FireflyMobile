import 'dart:async';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/sync_status.dart' show AppSyncStatus;
import 'package:firefly_mobile/ui/widgets/sync_status.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod re-exports it.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the app-bar SyncStatusIndicator (P2.3).
///
/// Overrides `syncStatusProvider` directly — the widget only consumes the
/// snapshot, so this exercises the real render branches (loading, error,
/// never/pending/synced) without needing a database.
void main() {
  /// Pumps the indicator under a MaterialApp with a one-off scope.
  Future<void> pumpIndicator(
    WidgetTester tester,
    List<Override> overrides,
  ) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        // Scaffold present so the "Sync now" stub can post a SnackBar the
        // same way it does inside the real HomeScreen app bar.
        child: MaterialApp(
          // MaterialApp/Scaffold aren't const-constructible in this SDK, but
          // prefer_const_constructors still fires — known false positive.
          // ignore: prefer_const_constructors
          home: Scaffold(appBar: AppBar(title: SyncStatusIndicator())),
        ),
      ),
    );
  }

  testWidgets('loading branch shows a spinner', (tester) async {
    // A never-completing provider keeps the FutureProvider in loading —
    // plain pump() because the spinner never settles.
    final pending = Completer<AppSyncStatus>();
    await pumpIndicator(
      tester,
      [syncStatusProvider.overrideWith((ref) => pending.future)],
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Sync now'), findsNothing);
  });

  testWidgets('provider failure degrades to a neutral cloud_off chip', (
    tester,
  ) async {
    await pumpIndicator(
      tester,
      [
        syncStatusProvider.overrideWith(
          (ref) async => throw Exception('boom'),
        ),
      ],
    );
    await tester.pumpAndSettle();

    // Offline-first: a broken status source must never block the app bar.
    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.byTooltip('Sync status unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('never-synced state shows cloud_off with the never label', (
    tester,
  ) async {
    await pumpIndicator(
      tester,
      [
        syncStatusProvider.overrideWith(
          (ref) async => const AppSyncStatus(pendingOps: 0),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    expect(find.bySemanticsLabel('Never synced'), findsOneWidget);
    expect(find.byKey(const Key('sync-pending-count')), findsNothing);
  });

  testWidgets('pending backlog shows amber upload icon + count badge', (
    tester,
  ) async {
    await pumpIndicator(
      tester,
      [
        syncStatusProvider.overrideWith(
          (ref) async => const AppSyncStatus(pendingOps: 4),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
    expect(find.byKey(const Key('sync-pending-count')), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('synced state shows green cloud_done, no count badge', (
    tester,
  ) async {
    await pumpIndicator(
      tester,
      [
        syncStatusProvider.overrideWith(
          (ref) async => AppSyncStatus(
            pendingOps: 0,
            lastSyncTsMs: DateTime.now()
                .subtract(const Duration(minutes: 2))
                .millisecondsSinceEpoch,
            lastSyncStatus: 'ok',
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
    expect(find.byKey(const Key('sync-pending-count')), findsNothing);
  });

  testWidgets('error state shows red sync_problem icon', (tester) async {
    await pumpIndicator(
      tester,
      [
        syncStatusProvider.overrideWith(
          (ref) async => const AppSyncStatus(
            pendingOps: 0,
            lastSyncStatus: 'error',
          ),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.sync_problem), findsOneWidget);
  });


}
