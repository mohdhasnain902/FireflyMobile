import 'package:firefly_mobile/ui/widgets/tag_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tag chips, Firefly style: type a tag, press enter, it becomes a chip;
/// a comma commits too; backspace on an empty field removes the last chip;
/// the value handed back is the JSON-array string the entity stores.
void main() {
  Future<String?> pumpInput(
    WidgetTester tester, {
    String? initial,
  }) async {
    String? emitted;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TagInputField(
              label: 'Tags',
              hint: 'Press enter to add a tag',
              value: initial,
              onChanged: (value) => emitted = value,
            ),
          ),
        ),
      ),
    );
    return emitted;
  }

  testWidgets('enter commits the typed tag as a chip', (tester) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), 'groceries');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'groceries'), findsOneWidget);
    // The field is cleared so the next tag can be typed straight away.
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('the value is the stored JSON array', (tester) async {
    String? emitted;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TagInputField(
              label: 'Tags',
              onChanged: (value) => emitted = value,
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'card');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(emitted, '["card"]');

    await tester.enterText(find.byType(TextField), 'travel');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(emitted, '["card","travel"]');
  });

  testWidgets('a comma also commits, so pasted lists become chips', (
    tester,
  ) async {
    await pumpInput(tester);
    await tester.enterText(find.byType(TextField), 'one,');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'one'), findsOneWidget);
  });

  testWidgets('duplicates are ignored case-insensitively', (tester) async {
    await pumpInput(tester);
    for (final tag in <String>['Card', 'card']) {
      await tester.enterText(find.byType(TextField), tag);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }
    expect(find.byType(InputChip), findsOneWidget);
  });

  testWidgets('an existing value comes back as chips and can be removed', (
    tester,
  ) async {
    String? emitted;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TagInputField(
              label: 'Tags',
              value: '["card","travel"]',
              onChanged: (value) => emitted = value,
            ),
          ),
        ),
      ),
    );
    expect(find.widgetWithText(InputChip, 'card'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'travel'), findsOneWidget);

    // Chip delete affordance: tap the delete icon inside the "card" chip.
    final deleteFinder = find.descendant(
      of: find.widgetWithText(InputChip, 'card'),
      matching: find.byTooltip('Delete'),
    );
    if (deleteFinder.evaluate().isNotEmpty) {
      await tester.tap(deleteFinder);
    } else {
      // Fallback: the rendered delete icon (no tooltip on this theme).
      await tester.tap(
        find
            .descendant(
              of: find.widgetWithText(InputChip, 'card'),
              matching: find.byType(GestureDetector),
            )
            .last,
      );
    }
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'card'), findsNothing);
    expect(emitted, '["travel"]');
  });

  testWidgets('backspace on an empty field removes the last chip', (
    tester,
  ) async {
    String? emitted;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TagInputField(
              label: 'Tags',
              value: '["a","b"]',
              onChanged: (value) => emitted = value,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'b'), findsNothing);
    expect(emitted, '["a"]');
  });

  testWidgets('tapping the empty field focuses it so typing works', (
    tester,
  ) async {
    // Regression guard: the hint is painted by the InputDecorator, so a tap on
    // the visible "Type a tag..." line must still land on the inner TextField
    // and open the keyboard.
    await pumpInput(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'card');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, 'card'), findsOneWidget);
  });

  testWidgets('a validation error is shown in place', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TagInputField(
              label: 'Tags',
              errorText: 'Tags must be a list of tags',
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Tags must be a list of tags'), findsOneWidget);
  });
}
