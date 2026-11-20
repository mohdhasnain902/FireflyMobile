import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/ui/widgets/sync_badge.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the P2.2.5 sync-state chip: one icon + colour + tooltip per
/// [SyncStatus], never interactive.
///
/// The three statuses are the ones DESIGN §5.1 defines; a future status
/// must fail to compile here first (the widget's switch is exhaustive),
/// which is exactly the forcing function this test provides.
void main() {
  Future<void> pumpBadge(WidgetTester tester, SyncStatus status) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SyncBadge(status: status))),
    );
  }

  testWidgets('pending renders the clock icon with a Pending sync tooltip', (
    tester,
  ) async {
    await pumpBadge(tester, SyncStatus.pending);

    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(find.byTooltip('Pending sync'), findsOneWidget);
  });

  testWidgets('synced renders the check icon with a Synced tooltip', (
    tester,
  ) async {
    await pumpBadge(tester, SyncStatus.synced);

    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byTooltip('Synced'), findsOneWidget);
  });

  testWidgets('conflict renders the warning icon with "Resolved by server"', (
    tester,
  ) async {
    await pumpBadge(tester, SyncStatus.conflict);

    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    expect(find.byTooltip('Resolved by server'), findsOneWidget);
  });

  testWidgets('is purely informational — no gesture detector', (
    tester,
  ) async {
    await pumpBadge(tester, SyncStatus.pending);

    expect(find.byType(GestureDetector), findsNothing);
    expect(find.byType(Tooltip), findsOneWidget);
  });
}
