import 'package:firefly_mobile/ui/widgets/confirm_delete_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the P2.2.4 confirm-before-delete contract: `true` only from the
/// destructive button, `false` from cancel, back or a route dismissal — and
/// no repository/database involvement at all (pure UI, per the widget's doc).
void main() {
  /// Set by the dialog under test; asserted by each case after the pop.
  bool? dialogResult;

  setUp(() => dialogResult = null);

  /// Pumps a launcher that opens the dialog and records its result — the
  /// standard way to await a dialog route inside `testWidgets`.
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showConfirmDeleteDialog(
                    context,
                    singular: 'tag',
                    rowTitle: 'Coffee',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the singular title and the row title in the copy', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete tag?'), findsOneWidget);
    expect(
      find.textContaining('"Coffee" will be marked for deletion'),
      findsOneWidget,
    );
  });

  testWidgets('Delete button confirms with true', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(dialogResult, isTrue);
    expect(find.text('Delete tag?'), findsNothing);
  });

  testWidgets('Cancel button returns false', (tester) async {
    await openDialog(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(dialogResult, isFalse);
  });

  testWidgets('dismissing the route (null result) coerces to false', (
    tester,
  ) async {
    await openDialog(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Pop with no result — e.g. system back / barrier behaviour — which the
    // widget's `confirmed ?? false` must normalise to an explicit false.
    Navigator.of(tester.element(find.text('Delete tag?'))).pop();
    await tester.pumpAndSettle();

    expect(dialogResult, isFalse);
  });
}
