import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Budget` entity (DESIGN §5.1, §6.2).
///
/// Mirrors `category_test.dart` plus the budget-specific quirks: wire `order`
/// maps to [Budget.orderIndex] and `auto_budget_type` is an optional string.
///
///  1. JSON:API -> model reads the enveloped `data.id` and `attributes`.
///  2. model -> JSON:API emits only fields the schema stores.
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality.
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);

  /// A JSON:API member exactly as Firefly returns one, plus the local-only
  /// values the caller supplies because JSON:API never carries them.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'budgets',
    'id': '3',
    'attributes': <String, dynamic>{
      'name': 'Groceries',
      'notes': 'Weekly shop',
      'currency_code': 'EUR',
      'currency_id': '1',
      'active': true,
      'order': 2,
      'auto_budget_type': 'rollover',
      'updated_at': '2026-10-11T08:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
      'user_id': '1',
    },
  };

  Budget parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Budget.fromJsonApi(
    member(),
    id: 'local-uuid-1',
    updatedAt: localWrite,
    seq: 7,
    syncStatus: syncStatus,
  );

  group('Budget.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final budget = parse();

      expect(budget.name, 'Groceries');
      expect(budget.notes, 'Weekly shop');
      expect(budget.autoBudgetType, 'rollover');
      expect(budget.fireflyId, '3');
      expect(budget.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(budget.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final budget = parse();

      expect(budget.id, 'local-uuid-1');
      expect(budget.updatedAt, localWrite);
      expect(budget.seq, 7);
      expect(budget.deletedAt, isNull);
    });

    test('maps the wire `order` attribute onto orderIndex', () {
      expect(parse().orderIndex, 2);
    });

    test('tolerates attributes the model does not store', () {
      final budget = Budget.fromJsonApi(
        <String, dynamic>{
          'type': 'budgets',
          'id': '1',
          'attributes': <String, dynamic>{'name': 'Bare'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(budget.name, 'Bare');
      expect(budget.notes, isNull);
      expect(budget.currencyCode, isNull);
      expect(budget.autoBudgetType, isNull);
      expect(budget.active, isTrue);
      expect(budget.orderIndex, isNull);
      expect(budget.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final budget = parse();

      expect(budget.remoteUpdatedAt!.isUtc, isTrue);
      expect(budget.updatedAt.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Budget.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'name',
        'notes',
        'currency_code',
        'currency_id',
        'auto_budget_type',
        'active',
        'order',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('firefly_id')));
      expect(attributes.keys, isNot(contains('deleted_at')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '3');
      expect(parse().toJsonApi()['type'], 'budgets');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Budget.fromJsonApi(
        original.toJsonApi(),
        id: original.id,
        updatedAt: original.updatedAt,
        seq: original.seq,
        syncStatus: original.syncStatus,
      );

      expect(rebuilt, original);
      expect(rebuilt.toJsonApi(), original.toJsonApi());

      final attributes =
          rebuilt.toJsonApi()['attributes']! as Map<String, dynamic>;
      expect(attributes['order'], 2);
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = Budget.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(row['order_index'], 2);
      expect(row['active'], 1);
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['name'], 'Groceries');
    });

    test('an unparseable timestamp never throws', () {
      final budget = Budget.fromJsonApi(
        <String, dynamic>{
          'type': 'budgets',
          'id': '1',
          'attributes': <String, dynamic>{
            'name': 'Bad date',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(budget.remoteUpdatedAt, isNull);
    });
  });
}
