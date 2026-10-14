import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the Currency entity (DESIGN §5.1, §6.2).
///
/// Every entity model must satisfy four properties:
///
///  1. JSON:API -> model reads the enveloped `data.id` and `attributes`.
///  2. model -> JSON:API emits only fields the schema stores.
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality.
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);

  /// A JSON:API member exactly as Firefly returns one (the captured USD row
  /// in `test/fixtures/api/currencies.json`), plus the local-only values
  /// the caller supplies because JSON:API never carries them.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'currencies',
    'id': '12',
    'attributes': <String, dynamic>{
      'code': 'USD',
      'name': 'US Dollar',
      'symbol': r'$',
      'decimal_places': 2,
      'default': false,
      'enabled': false,
      'native': false,
      'primary': false,
      'created_at': '2025-06-01T10:00:00Z',
      'updated_at': '2026-10-11T08:00:00Z',
    },
  };

  Currency parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Currency.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Currency.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final currency = parse();

      expect(currency.code, 'USD');
      expect(currency.name, 'US Dollar');
      expect(currency.symbol, r'$');
      expect(currency.decimalPlaces, 2);
      expect(currency.enabled, isFalse);
      expect(currency.isDefault, isFalse);
      expect(currency.fireflyId, '12');
      expect(currency.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(currency.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final currency = parse();

      expect(currency.id, 'local-uuid-1');
      expect(currency.updatedAt, localWrite);
      expect(currency.seq, 7);
      expect(currency.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final currency = Currency.fromJsonApi(
        <String, dynamic>{
          'type': 'currencies',
          'id': '1',
          'attributes': <String, dynamic>{
            'code': 'JPY',
            'name': 'Japanese Yen',
            'native': true,
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(currency.code, 'JPY');
      expect(currency.symbol, isNull);
      expect(currency.rate, isNull);
      expect(currency.symbolFirst, isFalse);
      expect(currency.decimalPlaces, 2);
      expect(currency.enabled, isTrue);
      expect(currency.isDefault, isFalse);
      expect(currency.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final currency = parse();

      expect(currency.remoteUpdatedAt!.isUtc, isTrue);
      expect(currency.updatedAt.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Currency.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'code',
        'name',
        'symbol',
        'symbol_first',
        'decimal_places',
        'enabled',
        'default',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('created_at')));
      expect(attributes.keys, isNot(contains('native')));
      expect(attributes.keys, isNot(contains('primary')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '12');
      expect(parse().toJsonApi()['type'], 'currencies');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Currency.fromJsonApi(
        original.toJsonApi(),
        id: original.id,
        updatedAt: original.updatedAt,
        seq: original.seq,
        syncStatus: original.syncStatus,
      );

      expect(rebuilt, original);
      expect(rebuilt.toJsonApi(), original.toJsonApi());
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = Currency.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['code'], 'USD');
      expect(row['is_default'], 0);
      expect(row['enabled'], 0);
    });

    test('an unparseable timestamp never throws', () {
      final currency = Currency.fromJsonApi(
        <String, dynamic>{
          'type': 'currencies',
          'id': '1',
          'attributes': <String, dynamic>{
            'code': 'BAD',
            'name': 'Bad date',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(currency.remoteUpdatedAt, isNull);
    });
  });
}
