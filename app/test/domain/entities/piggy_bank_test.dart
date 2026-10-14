import 'package:firefly_mobile/domain/entities/piggy_bank.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `PiggyBank` entity (DESIGN §5.1, §6.2).
///
/// Mirrors `category_test.dart` plus the piggy-bank-specific quirks: wire
/// `order` maps to [PiggyBank.orderIndex], and `target_amount` /
/// `current_amount` are decimal strings.
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
    'type': 'piggy_banks',
    'id': '5',
    'attributes': <String, dynamic>{
      'name': 'Vacation fund',
      'account_id': '7',
      'target_amount': '2000.000000000000',
      'current_amount': '450.000000000000',
      'start_date': '2026-01-01T00:00:00Z',
      'target_date': '2026-12-31T00:00:00Z',
      'currency_code': 'EUR',
      'currency_id': '1',
      'notes': 'Summer trip',
      'order': 1,
      'updated_at': '2026-10-11T08:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
      'user_id': '1',
      // Computed / unmapped fields the schema deliberately drops.
      'percentage': 22.5,
    },
  };

  PiggyBank parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      PiggyBank.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('PiggyBank.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final piggy = parse();

      expect(piggy.name, 'Vacation fund');
      expect(piggy.accountId, '7');
      expect(piggy.targetAmount, '2000.000000000000');
      expect(piggy.currentAmount, '450.000000000000');
      expect(piggy.fireflyId, '5');
      expect(piggy.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(piggy.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final piggy = parse();

      expect(piggy.id, 'local-uuid-1');
      expect(piggy.updatedAt, localWrite);
      expect(piggy.seq, 7);
      expect(piggy.deletedAt, isNull);
    });

    test('maps the wire `order` attribute onto orderIndex', () {
      expect(parse().orderIndex, 1);
    });

    test('tolerates attributes the model does not store', () {
      final piggy = PiggyBank.fromJsonApi(
        <String, dynamic>{
          'type': 'piggy_banks',
          'id': '1',
          'attributes': <String, dynamic>{
            'name': 'Bare',
            'percentage': 0,
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(piggy.name, 'Bare');
      expect(piggy.accountId, isNull);
      expect(piggy.targetAmount, isNull);
      expect(piggy.currentAmount, isNull);
      expect(piggy.startDate, isNull);
      expect(piggy.targetDate, isNull);
      expect(piggy.orderIndex, isNull);
      expect(piggy.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final piggy = parse();

      expect(piggy.remoteUpdatedAt!.isUtc, isTrue);
      expect(piggy.updatedAt.isUtc, isTrue);
      expect(piggy.startDate!.isUtc, isTrue);
      expect(piggy.targetDate!.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('PiggyBank.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'name',
        'account_id',
        'target_amount',
        'current_amount',
        'start_date',
        'target_date',
        'currency_code',
        'currency_id',
        'notes',
        'order',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('percentage')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '5');
      expect(parse().toJsonApi()['type'], 'piggy_banks');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = PiggyBank.fromJsonApi(
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
      expect(attributes['order'], 1);
      expect(attributes['start_date'], '2026-01-01T00:00:00.000Z');
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = PiggyBank.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(row['order_index'], 1);
      expect(row['start_date'], '2026-01-01T00:00:00.000Z');
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['name'], 'Vacation fund');
    });

    test('an unparseable timestamp never throws', () {
      final piggy = PiggyBank.fromJsonApi(
        <String, dynamic>{
          'type': 'piggy_banks',
          'id': '1',
          'attributes': <String, dynamic>{
            'name': 'Bad date',
            'updated_at': 'not-a-timestamp',
            'start_date': 'also-bad',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(piggy.remoteUpdatedAt, isNull);
      expect(piggy.startDate, isNull);
    });
  });
}
