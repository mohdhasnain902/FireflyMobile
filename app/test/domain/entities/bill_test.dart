import 'dart:convert';

import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Bill` entity (DESIGN §5.1, §6.2).
///
/// Mirrors `category_test.dart` plus the bill-specific quirks: `pay_dates`
/// arrives as a JSON array and lives in a TEXT column, `skip` is
/// "every N periods" (an int, never a bool) and `active` is a real bool.
///
///  1. JSON:API -> model reads the enveloped `data.id` and `attributes`.
///  2. model -> JSON:API emits only fields the schema stores.
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality.
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);
  final payDates = <String>['2026-11-01T00:00:00Z', '2026-12-01T00:00:00Z'];

  /// A JSON:API member exactly as Firefly returns one, plus the local-only
  /// values the caller supplies because JSON:API never carries them.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'bills',
    'id': '42',
    'attributes': <String, dynamic>{
      'name': 'Rent',
      'amount': '1200.000000000000',
      'currency_code': 'EUR',
      'currency_id': '1',
      'bill_direction': 'out',
      'repeat_freq': 'monthly',
      'skip': 3,
      'active': false,
      'pay_dates': payDates,
      'remaining_amount': '4800.000000000000',
      'next_expected_match': '2026-11-01T00:00:00Z',
      'notes': 'Yearly rent, four payments',
      'auto_budget_type': 'none',
      'updated_at': '2026-10-11T08:00:00Z',
    },
  };

  /// Parses [member] with the local-only values every pull supplies.
  Bill parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Bill.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Bill.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final bill = parse();

      expect(bill.name, 'Rent');
      expect(bill.amount, '1200.000000000000');
      expect(bill.fireflyId, '42');
      expect(bill.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(bill.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final bill = parse();

      expect(bill.id, 'local-uuid-1');
      expect(bill.updatedAt, localWrite);
      expect(bill.seq, 7);
      expect(bill.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final bill = Bill.fromJsonApi(
        <String, dynamic>{
          'type': 'bills',
          'id': '1',
          'attributes': <String, dynamic>{'name': 'Bare', 'amount': '5.00'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(bill.name, 'Bare');
      expect(bill.payDates, isNull);
      expect(bill.skip, 0);
      expect(bill.active, isTrue);
      expect(bill.repeatFreq, 'monthly');
      expect(bill.currencyCode, isNull);
      expect(bill.remoteUpdatedAt, isNull);
    });

    test('stores pay_dates as text, skip as int, active as bool', () {
      final bill = parse();

      expect(bill.payDates, isA<String>());
      expect(jsonDecode(bill.payDates!), payDates);
      expect(bill.skip, 3);
      expect(bill.active, isFalse);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final bill = parse();

      expect(bill.remoteUpdatedAt!.isUtc, isTrue);
      expect(bill.updatedAt.isUtc, isTrue);
      expect(bill.nextExpectedMatch!.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Bill.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'name',
        'amount',
        'currency_code',
        'currency_id',
        'bill_direction',
        'repeat_freq',
        'skip',
        'active',
        'pay_dates',
        'remaining_amount',
        'next_expected_match',
        'notes',
        'auto_budget_type',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('firefly_id')));
      expect(attributes.keys, isNot(contains('deleted_at')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '42');
      expect(parse().toJsonApi()['type'], 'bills');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Bill.fromJsonApi(
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
      expect(attributes['pay_dates'], payDates);
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = Bill.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(jsonDecode(row['pay_dates']! as String), payDates);
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['name'], 'Rent');
      expect(row['skip'], 3);
      expect(row['active'], 0);
      expect(row['pay_dates'], isA<String>());
      expect(jsonDecode(row['pay_dates']! as String), payDates);
    });

    test('an unparseable timestamp never throws', () {
      final bill = Bill.fromJsonApi(
        <String, dynamic>{
          'type': 'bills',
          'id': '1',
          'attributes': <String, dynamic>{
            'name': 'Bad date',
            'amount': '1.00',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(bill.remoteUpdatedAt, isNull);
    });
  });
}
