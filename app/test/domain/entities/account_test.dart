import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Account` entity (DESIGN §5.1, §6.2).
///
/// Mirrors `category_test.dart` plus the account-specific quirks: wire `order`
/// maps to [Account.orderIndex], `include_net_worth` defaults true, and
/// computed balance fields from the API are intentionally dropped.
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
    'type': 'accounts',
    'id': '7',
    'attributes': <String, dynamic>{
      'name': 'Checking',
      'type': 'asset',
      'currency_code': 'EUR',
      'currency_id': '1',
      'account_role': 'defaultAsset',
      'opening_balance': '1000.00',
      'opening_balance_date': '2026-01-01T00:00:00Z',
      'iban': 'DE89370400440532013000',
      'bic': 'COBADEFFXXX',
      'account_number': '1234567890',
      'order': 3,
      'active': true,
      'virtual_balance': '0.00',
      'notes': 'Primary checking',
      'include_net_worth': true,
      'updated_at': '2026-10-11T08:00:00Z',
      // Computed / unmapped fields the schema deliberately drops.
      'current_balance': '2450.55',
      'currency_attributes': <String, dynamic>{'code': 'EUR'},
      'created_at': '2026-01-01T00:00:00Z',
      'user_id': '1',
    },
  };

  Account parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Account.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Account.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final account = parse();

      expect(account.name, 'Checking');
      expect(account.type, 'asset');
      expect(account.fireflyId, '7');
      expect(account.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(account.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final account = parse();

      expect(account.id, 'local-uuid-1');
      expect(account.updatedAt, localWrite);
      expect(account.seq, 7);
      expect(account.deletedAt, isNull);
    });

    test('maps the wire `order` attribute onto orderIndex', () {
      expect(parse().orderIndex, 3);
    });

    test('tolerates attributes the model does not store', () {
      final account = Account.fromJsonApi(
        <String, dynamic>{
          'type': 'accounts',
          'id': '1',
          'attributes': <String, dynamic>{
            'name': 'Bare',
            'type': 'expense',
            'current_balance': '9.99',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(account.name, 'Bare');
      expect(account.type, 'expense');
      expect(account.currencyCode, isNull);
      expect(account.orderIndex, isNull);
      expect(account.active, isTrue);
      expect(account.includeNetWorth, isTrue);
      expect(account.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final account = parse();

      expect(account.remoteUpdatedAt!.isUtc, isTrue);
      expect(account.updatedAt.isUtc, isTrue);
      expect(account.openingBalanceDate!.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Account.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'name',
        'type',
        'currency_code',
        'currency_id',
        'account_role',
        'opening_balance',
        'opening_balance_date',
        'iban',
        'bic',
        'account_number',
        'order',
        'active',
        'virtual_balance',
        'notes',
        'include_net_worth',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('firefly_id')));
      expect(attributes.keys, isNot(contains('deleted_at')));
      expect(attributes.keys, isNot(contains('current_balance')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '7');
      expect(parse().toJsonApi()['type'], 'accounts');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Account.fromJsonApi(
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
      expect(attributes['order'], 3);
      expect(attributes['opening_balance_date'], '2026-01-01T00:00:00.000Z');
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = Account.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(row['order_index'], 3);
      expect(row['opening_balance_date'], '2026-01-01T00:00:00.000Z');
      expect(row['active'], 1);
      expect(row['include_net_worth'], 1);
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['name'], 'Checking');
      expect(row['type'], 'asset');
    });

    test('an unparseable timestamp never throws', () {
      final account = Account.fromJsonApi(
        <String, dynamic>{
          'type': 'accounts',
          'id': '1',
          'attributes': <String, dynamic>{
            'name': 'Bad date',
            'type': 'asset',
            'updated_at': 'not-a-timestamp',
            'opening_balance_date': 'also-bad',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(account.remoteUpdatedAt, isNull);
      expect(account.openingBalanceDate, isNull);
    });
  });
}
