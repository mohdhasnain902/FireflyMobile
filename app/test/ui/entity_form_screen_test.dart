import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/repositories/entity_repositories.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/models/field_spec.dart';
import 'package:firefly_mobile/ui/screens/entity_form_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Riverpod 3 hides `Override` behind misc.dart; flutter_riverpod re-exports it.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db/app_database_test.dart';
import 'support/tags_test_config.dart';

/// Widget tests for the generic FieldSpec-driven form (P2.2.2/3), backed by
/// the real in-memory SQLite write path.
///
/// Covers: create/edit/cancel pop results, required + grounded validation
/// rules (decimal positive, choice membership, JSON parse), the choice
/// dropdown, read-only gating (both the helper config and the production
/// pull-only `currenciesConfig`), and the optional-date picker.
void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late DeviceMetaDao meta;
  late TagRepository tags;

  setUpAll(() async {
    db = await openTestDatabase();
    meta = DeviceMetaDao(db);
    tags = TagRepository(db: db, meta: meta);
  });

  setUp(() async {
    await db.delete('op_log');
    await db.delete('tags');
    await db.delete('device_meta');
  });

  /// Pop result of the form under test; `null` means "still open".
  bool? formResult;

  setUp(() => formResult = null);

  Override repoOverride() => tagRepositoryProvider.overrideWith(
    (ref) async => TagRepository(db: db, meta: meta),
  );

  Future<Tag> seed(String name) {
    return tags.create(
      (id, at, seq) => Tag(id: id, tag: name, updatedAt: at, seq: seq),
    );
  }

  /// Pumps a launcher whose button pushes the form, so the test can assert
  /// both what the form shows and what it pops back.
  Future<void> openForm(
    WidgetTester tester, {
    required EntityConfig<Tag> config,
    Tag? existing,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repoOverride()],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    formResult = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => EntityFormScreen<Tag>(
                          config: config,
                          existing: existing,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Pumps the form directly (no launcher) for read-only inspection tests
  /// that never pop a result.
  Future<void> pumpForm(
    WidgetTester tester, {
    required EntityConfig<Tag> config,
    Tag? existing,
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [repoOverride()],
        child: MaterialApp(
          home: EntityFormScreen<Tag>(config: config, existing: existing),
        ),
      ),
    );
  }

  /// The rules config: one field per validation family the generic form
  /// handles — required text, positive decimal, grounded choice, JSON.
  EntityConfig<Tag> rulesConfig() => tagsConfigForTest(
    canWrite: true,
    repoOf: (ref) async => tags,
    fields: const [
      FieldSpec(
        key: 'tag',
        label: 'Tag',
        kind: FieldKind.text,
        required: true,
      ),
      FieldSpec(
        key: 'amount',
        label: 'Amount',
        kind: FieldKind.decimal,
        required: true,
        positive: true,
      ),
      FieldSpec(
        key: 'kind',
        label: 'Kind',
        kind: FieldKind.choice,
        required: true,
        choices: ['income', 'expense'],
      ),
      FieldSpec(
        key: 'meta',
        label: 'Meta',
        kind: FieldKind.json,
        required: true,
      ),
    ],
  );

  testWidgets('create mode shows New tag, its fields and no read-only note', (
    tester,
  ) async {
    await openForm(tester, config: tagsConfig);

    expect(find.text('New tag'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Tag'), findsOneWidget);
    // Optional date field starts unset (required dates would pin to today).
    expect(find.text('Not set'), findsOneWidget);
    expect(
      find.text('Read-only — this entity cannot be edited on the phone.'),
      findsNothing,
    );
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
  });

  testWidgets('empty required field blocks save with the field error', (
    tester,
  ) async {
    await openForm(tester, config: tagsConfig);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Tag is required'), findsOneWidget);
    // Still on the form, nothing written.
    expect(formResult, isNull);
    expect(find.text('New tag'), findsOneWidget);
    expect(await db.query('tags'), isEmpty);
  });

  testWidgets('valid create pops true and writes a row plus one queued op', (
    tester,
  ) async {
    await openForm(tester, config: tagsConfig);
    await tester.enterText(find.widgetWithText(TextFormField, 'Tag'), 'Coffee');

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(formResult, isTrue);
    expect(find.text('New tag'), findsNothing);

    final rows = await db.query('tags');
    expect(rows, hasLength(1));
    expect(rows.single['tag'], 'Coffee');
    expect(rows.single['deleted_at'], isNull);
    expect(rows.single['date'], isNull); // left unset
    expect(await db.query('op_log'), hasLength(1)); // queued create
  });

  testWidgets('edit mode prefills the row and updates it in place', (
    tester,
  ) async {
    final existing = await seed('Tea');

    await openForm(tester, config: tagsConfig, existing: existing);
    expect(find.text('Edit tag'), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget); // prefilled controller text

    await tester.enterText(find.widgetWithText(TextFormField, 'Tag'), 'Chai');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(formResult, isTrue);

    final rows = await db.query('tags');
    expect(rows, hasLength(1), reason: 'edit must not duplicate the row');
    expect(rows.single['id'], existing.id, reason: 'id must be kept');
    expect(rows.single['tag'], 'Chai');
    // 1 create (seed) + 1 update = 2 queued ops.
    expect(await db.query('op_log'), hasLength(2));
  });

  testWidgets('Cancel discards edits and pops false without writing', (
    tester,
  ) async {
    await openForm(tester, config: tagsConfig);
    await tester.enterText(find.widgetWithText(TextFormField, 'Tag'), 'Coffee');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(formResult, isFalse);
    expect(find.text('New tag'), findsNothing);
    expect(await db.query('tags'), isEmpty);
    expect(await db.query('op_log'), isEmpty);
  });

  testWidgets('grounded validation rules surface per-field errors', (
    tester,
  ) async {
    await openForm(tester, config: rulesConfig());

    await tester.enterText(find.widgetWithText(TextFormField, 'Tag'), 'Coffee');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '0', // number-shaped but not positive (IsValidPositiveAmount)
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Meta'),
      '{oops', // invalid JSON
    );
    // 'kind' left empty on purpose.

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Amount must be greater than zero'), findsOneWidget);
    expect(find.text('Kind is required'), findsOneWidget);
    expect(find.text('Meta must be valid JSON'), findsOneWidget);
    expect(find.text('Tag is required'), findsNothing); // tag was filled

    expect(formResult, isNull);
    expect(await db.query('tags'), isEmpty);
  });

  testWidgets('choice dropdown selects a grounded option and saves', (
    tester,
  ) async {
    await openForm(tester, config: rulesConfig());
    await tester.enterText(find.widgetWithText(TextFormField, 'Tag'), 'Coffee');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '12.34',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Meta'), '{}');

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('income'), findsOneWidget);
    expect(find.text('expense'), findsOneWidget);

    await tester.tap(find.text('income'));
    await tester.pumpAndSettle();
    expect(find.text('income'), findsOneWidget); // now the closed selection

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(formResult, isTrue);
    final rows = await db.query('tags');
    expect(rows, hasLength(1));
    expect(rows.single['tag'], 'Coffee');
  });

  testWidgets('canWrite: false hides all write actions and disables inputs', (
    tester,
  ) async {
    final readOnly = tagsConfigForTest(
      canWrite: false,
      repoOf: (ref) async => tags,
    );

    await pumpForm(tester, config: readOnly);

    expect(
      find.text('Read-only — this entity cannot be edited on the phone.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
    final field = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(field.enabled, isFalse, reason: 'input must be inert');
  });

  testWidgets('production currenciesConfig can add a custom currency', (
    tester,
  ) async {
    // Currencies became writable so a custom currency (BTC and friends) can be
    // created from Settings, exactly like Firefly's own Currencies page.
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: EntityFormScreen<Currency>(config: currenciesConfig),
        ),
      ),
    );

    expect(find.text('New currency'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Code'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(
      find.text('Read-only — this entity cannot be edited on the phone.'),
      findsNothing,
    );
  });

  testWidgets('date picker cancel keeps the optional field unset', (
    tester,
  ) async {
    await openForm(tester, config: tagsConfig);
    expect(find.text('Not set'), findsOneWidget);

    await tester.tap(find.text('Not set'));
    await tester.pumpAndSettle();
    // Material 3 date picker: en_US 'Cancel' / 'OK' (M2 uppercased, M3 not).
    final cancel = find.widgetWithText(TextButton, 'Cancel');
    expect(cancel, findsOneWidget);
    expect(find.text('OK'), findsOneWidget);

    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('OK'), findsNothing);
  });
}
