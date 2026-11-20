// KEPT regression sweep (was throwaway; promoted 2026-10-23 with R23).
// Sweep #2: screens the shell sweep never laid out — About, SyncLog,
// EntityForm (create mode, two configs).
// Harness notes:
//  * No FlutterError.onError override (R22 trap) — the binding records
//    overflow errors itself and prints the widget chain at test end.
//  * Tree is NOT torn down at the end: a trailing pumpWidget(SizedBox.shrink())
//    deactivated every element, so overflow chains came out DEFUNCT. Keeping
//    the tree alive until the framework reports gives a live chain.
//  * pumpAndSettle is wrapped: SyncLog's indeterminate spinner never settles.
//  * Only vertical scrollables are dragged (the dropdown's internal
//    horizontal Scrollable vanishes after one drag → "finder found 0").
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/screens/about_screen.dart';
import 'package:firefly_mobile/ui/screens/entity_form_screen.dart';
import 'package:firefly_mobile/ui/screens/sync_log_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Settles if possible, otherwise pumps a bounded number of frames
/// (indeterminate spinners never let pumpAndSettle return).
///
/// Catches Object: pumpAndSettle's timeout is a FlutterError (an Error, not
/// an Exception), so `on Exception` silently missed it and the sweep tests
/// failed on the uncaught error instead of falling back to bounded pumps.
Future<void> settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle();
  } on Object {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }
}

/// Drives [child] at [logical] width, scrolling every vertical scrollable
/// fully so below-cacheExtent children lay out too.
Future<void> driveScreen(
  WidgetTester tester,
  double logical,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(logical * 3, 640 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // Live-dump overflow errors: at test end the binding prints chains after the
  // tree is torn down (everything DEFUNCT). Forwarding to the previous handler
  // keeps the error a test failure too — a capture sink that swallows it trips
  // the binding's pending-exception assertion (R22).
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details);
    prevOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = prevOnError);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: child),
    ),
  );
  await settle(tester);

  // Snapshot only mounted elements: a drag re-parents scrollables and leaves
  // earlier snapshot entries defunct (Element.widget then throws a null
  // check). Re-snapshot inside the pass instead of trusting one list.
  final scrollables = find
      .byType(Scrollable)
      .evaluate()
      .where((e) => e.mounted)
      .toList();
  for (final element in scrollables) {
    if (!element.mounted) continue;
    final w = element.widget;
    if (w is! Scrollable || w.axisDirection != AxisDirection.down) continue;
    final f = find.byWidget(w);
    if (f.evaluate().isEmpty) continue;
    for (var i = 0; i < 10; i++) {
      await tester.drag(f, const Offset(0, -260));
      await settle(tester);
      if (find.byWidget(w).evaluate().isEmpty) break;
    }
    for (var i = 0; i < 10; i++) {
      if (find.byWidget(w).evaluate().isEmpty) break;
      await tester.drag(f, const Offset(0, 260));
      await settle(tester);
    }
  }
}

void main() {
  final dbOverride = <Override>[
    databaseProvider.overrideWith((_) async => throw UnimplementedError()),
  ];

  for (final w in [320.0, 360.0, 393.0]) {
    testWidgets('sweep2: About @ $w', (tester) async {
      await driveScreen(tester, w, const AboutScreen());
    });

    testWidgets('sweep2: SyncLog @ $w', (tester) async {
      await driveScreen(tester, w, const SyncLogScreen());
    });

    testWidgets('sweep2: EntityForm (transactions) @ $w', (tester) async {
      await driveScreen(
        tester,
        w,
        EntityFormScreen(config: transactionsConfig),
        overrides: dbOverride,
      );
    });

    testWidgets('sweep2: EntityForm (budgets) @ $w', (tester) async {
      await driveScreen(
        tester,
        w,
        EntityFormScreen(config: budgetsConfig),
        overrides: dbOverride,
      );
    });
  }
}
