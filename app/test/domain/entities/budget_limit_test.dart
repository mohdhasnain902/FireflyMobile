import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `BudgetLimit` entity (DESIGN §5.1, §6.4).
///
/// Mirrors `category_test.dart` plus the budget-limit-specific quirks:
/// `budget_id`, `start` and `end` are required, and a malformed date falls
/// back to the Unix epoch rather than throwing.
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
    'type': 'budget_limits',
    'id': '11',
    'attributes': <String, dynamic>{
      'budget_id': '3',
      'start': '2026-10-01T00:00:00Z',
      'end': '2026-10-31T23:59:59Z',
      'amount': '400.000000000000',
      'currency_code': 'EUR',
      'currency_id': '1',
      'notes': 'October groceries',
      'updated_at': '2026-10-11T08:00:00Z',
      'created_at': '2026-09-30T00:00:00Z',
      'user_id': '1',
    },
  };

  BudgetLimit parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      BudgetLimit.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('BudgetLimit.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final limit = parse();

      expect(limit.budgetId, '3');
      expect(limit.start, DateTime.utc(2026, 10));
      expect(limit.end, DateTime.utc(2026, 10, 31, 23, 59, 59));
      expect(limit.amount, '400.000000000000');
      expect(limit.fireflyId, '11');
      expect(limit.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(limit.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final limit = parse();

      expect(limit.id, 'local-uuid-1');
      expect(limit.updatedAt, localWrite);
      expect(limit.seq, 7);
      expect(limit.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final limit = BudgetLimit.fromJsonApi(
        <String, dynamic>{
          'type': 'budget_limits',
          'id': '1',
          'attributes': <String, dynamic>{
            'budget_id': '9',
            'start': '2026-01-01T00:00:00Z',
            'end': '2026-01-31T00:00:00Z',
            'amount': '1.00',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(limit.currencyCode, isNull);
      expect(limit.notes, isNull);
      expect(limit.remoteUpdatedAt, isNull);
    });

    test('falls back to the epoch for a missing or bad start/end', () {
      final limit = BudgetLimit.fromJsonApi(
        <String, dynamic>{
          'type': 'budget_limits',
          'id': '1',
          'attributes': <String, dynamic>{
            'budget_id': '9',
            'start': 'not-a-timestamp',
            'amount': '1.00',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(limit.start, DateTime.utc(1970));
      expect(limit.end, DateTime.utc(1970));
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final limit = parse();

      expect(limit.remoteUpdatedAt!.isUtc, isTrue);
      expect(limit.updatedAt.isUtc, isTrue);
      expect(limit.start.isUtc, isTrue);
      expect(limit.end.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('BudgetLimit.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'budget_id',
        'start',
        'end',
        'amount',
        'currency_code',
        'currency_id',
        'notes',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('firefly_id')));
      expect(attributes.keys, isNot(contains('deleted_at')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '11');
      expect(parse().toJsonApi()['type'], 'budget_limits');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = BudgetLimit.fromJsonApi(
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
      expect(attributes['start'], '2026-10-01T00:00:00.000Z');
      expect(attributes['end'], '2026-10-31T23:59:59.000Z');
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = BudgetLimit.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(row['start'], '2026-10-01T00:00:00.000Z');
      expect(row['end'], '2026-10-31T23:59:59.000Z');
      expect(row['budget_id'], '3');
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['amount'], '400.000000000000');
    });

    test('an unparseable timestamp never throws', () {
      final limit = BudgetLimit.fromJsonApi(
        <String, dynamic>{
          'type': 'budget_limits',
          'id': '1',
          'attributes': <String, dynamic>{
            'budget_id': '1',
            'start': 'nope',
            'end': 'nope',
            'amount': '1.00',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(limit.remoteUpdatedAt, isNull);
      expect(limit.start, DateTime.utc(1970));
      expect(limit.end, DateTime.utc(1970));
    });
  });
}
