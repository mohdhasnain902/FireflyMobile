import 'dart:convert';

import 'package:firefly_mobile/domain/entities/subscription.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Subscription` entity (DESIGN §5.1, §6.2).
///
/// Mirrors `category_test.dart` plus the subscription-specific quirks:
/// `periods` arrives as a JSON array stored in a TEXT column, and
/// `next_date` / `end_date` are wire timestamps that must come back UTC.
///
///  1. JSON:API -> model reads the enveloped `data.id` and `attributes`.
///  2. model -> JSON:API emits only fields the schema stores.
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality.
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);
  final periods = <Map<String, dynamic>>[
    <String, dynamic>{
      'start': '2026-10-01',
      'end': '2026-10-31',
      'order': 1,
      'paid': false,
      'amount': '15.990000000000',
    },
    <String, dynamic>{
      'start': '2026-11-01',
      'end': '2026-11-30',
      'order': 2,
      'paid': false,
      'amount': '15.990000000000',
    },
  ];

  /// A JSON:API member exactly as Firefly returns one, plus the local-only
  /// values the caller supplies because JSON:API never carries them.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'subscriptions',
    'id': '42',
    'attributes': <String, dynamic>{
      'title': 'Netflix',
      'amount': '15.990000000000',
      'currency_code': 'EUR',
      'currency_id': '2',
      'transaction_journal_id': '99',
      'repeat_freq': 'monthly',
      'active': true,
      'next_date': '2026-11-01T00:00:00Z',
      'end_date': '2027-10-01T00:00:00Z',
      'periods': periods,
      'method': 'cc',
      'notes': 'Family plan',
      'updated_at': '2026-10-11T08:00:00Z',
    },
  };

  /// Parses [member] with the local-only values every pull supplies.
  Subscription parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Subscription.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Subscription.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final subscription = parse();

      expect(subscription.title, 'Netflix');
      expect(subscription.amount, '15.990000000000');
      expect(subscription.fireflyId, '42');
      expect(
        subscription.remoteUpdatedAt,
        DateTime.utc(2026, 10, 11, 8),
      );
      expect(subscription.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final subscription = parse();

      expect(subscription.id, 'local-uuid-1');
      expect(subscription.updatedAt, localWrite);
      expect(subscription.seq, 7);
      expect(subscription.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final subscription = Subscription.fromJsonApi(
        <String, dynamic>{
          'type': 'subscriptions',
          'id': '1',
          'attributes': <String, dynamic>{
            'title': 'Bare',
            'amount': '9.99',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(subscription.title, 'Bare');
      expect(subscription.currencyCode, isNull);
      expect(subscription.transactionJournalId, isNull);
      expect(subscription.nextDate, isNull);
      expect(subscription.endDate, isNull);
      expect(subscription.periods, isNull);
      expect(subscription.method, isNull);
      expect(subscription.repeatFreq, 'monthly');
      expect(subscription.active, isTrue);
      expect(subscription.remoteUpdatedAt, isNull);
    });

    test('stores periods as text and the dates as UTC timestamps', () {
      final subscription = parse();

      expect(subscription.periods, isA<String>());
      expect(jsonDecode(subscription.periods!), periods);
      expect(subscription.nextDate, DateTime.utc(2026, 11));
      expect(subscription.endDate, DateTime.utc(2027, 10));
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final subscription = parse();

      expect(subscription.remoteUpdatedAt!.isUtc, isTrue);
      expect(subscription.updatedAt.isUtc, isTrue);
      expect(subscription.nextDate!.isUtc, isTrue);
      expect(subscription.endDate!.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Subscription.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'title',
        'amount',
        'currency_code',
        'currency_id',
        'transaction_journal_id',
        'repeat_freq',
        'active',
        'next_date',
        'end_date',
        'periods',
        'method',
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
      expect(parse().toJsonApi()['id'], '42');
      expect(parse().toJsonApi()['type'], 'subscriptions');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Subscription.fromJsonApi(
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
      expect(attributes['periods'], periods);
      expect(attributes['next_date'], '2026-11-01T00:00:00.000Z');
      expect(attributes['end_date'], '2027-10-01T00:00:00.000Z');
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = Subscription.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(jsonDecode(row['periods']! as String), periods);
      expect(row['next_date'], '2026-11-01T00:00:00.000Z');
      expect(row['end_date'], '2027-10-01T00:00:00.000Z');
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['title'], 'Netflix');
      expect(row['active'], 1);
      expect(row['periods'], isA<String>());
      expect(row['next_date'], isA<String>());
      expect(row['end_date'], isA<String>());
    });

    test('an unparseable timestamp never throws', () {
      final subscription = Subscription.fromJsonApi(
        <String, dynamic>{
          'type': 'subscriptions',
          'id': '1',
          'attributes': <String, dynamic>{
            'title': 'Bad date',
            'amount': '1.00',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(subscription.remoteUpdatedAt, isNull);
    });
  });
}
