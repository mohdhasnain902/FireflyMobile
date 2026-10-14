import 'dart:convert';

import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Recurrence` entity (DESIGN §5.1, §6.2).
///
/// Mirrors `category_test.dart` plus the recurrence-specific quirks: the wire
/// attribute is `transactions` but the column is `transactions_json`, and
/// `repeat_freq` defaults to `'monthly'`.
///
///  1. JSON:API -> model reads the enveloped `data.id` and `attributes`.
///  2. model -> JSON:API emits only fields the schema stores.
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality.
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);
  final templates = <Map<String, dynamic>>[
    <String, dynamic>{
      'description': 'Rent',
      'amount': '950.00',
      'currency_code': 'EUR',
      'source_name': 'Checking',
      'destination_name': 'Landlord',
      'type': 'withdrawal',
    },
  ];

  /// A JSON:API member exactly as Firefly returns one, plus the local-only
  /// values the caller supplies because JSON:API never carries them.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'recurrences',
    'id': '21',
    'attributes': <String, dynamic>{
      'title': 'Monthly rent',
      'description': 'Pay the landlord',
      'repeat_freq': 'monthly',
      'recur_until': '2027-12-31T00:00:00Z',
      'nr_of_repetitions': 24,
      'active': true,
      'transactions': templates,
      'updated_at': '2026-10-11T08:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
      'user_id': '1',
    },
  };

  Recurrence parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Recurrence.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Recurrence.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final recurrence = parse();

      expect(recurrence.title, 'Monthly rent');
      expect(recurrence.description, 'Pay the landlord');
      expect(recurrence.repeatFreq, 'monthly');
      expect(recurrence.recurUntil, DateTime.utc(2027, 12, 31));
      expect(recurrence.nrOfRepetitions, 24);
      expect(recurrence.fireflyId, '21');
      expect(recurrence.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(recurrence.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final recurrence = parse();

      expect(recurrence.id, 'local-uuid-1');
      expect(recurrence.updatedAt, localWrite);
      expect(recurrence.seq, 7);
      expect(recurrence.deletedAt, isNull);
    });

    test('stores the wire `transactions` list as JSON text', () {
      final recurrence = parse();

      expect(recurrence.transactionsJson, isA<String>());
      expect(jsonDecode(recurrence.transactionsJson!), templates);
    });

    test('tolerates attributes the model does not store', () {
      final recurrence = Recurrence.fromJsonApi(
        <String, dynamic>{
          'type': 'recurrences',
          'id': '1',
          'attributes': <String, dynamic>{'title': 'Bare'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(recurrence.title, 'Bare');
      expect(recurrence.description, isNull);
      expect(recurrence.repeatFreq, 'monthly');
      expect(recurrence.recurUntil, isNull);
      expect(recurrence.nrOfRepetitions, isNull);
      expect(recurrence.transactionsJson, isNull);
      expect(recurrence.active, isTrue);
      expect(recurrence.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final recurrence = parse();

      expect(recurrence.remoteUpdatedAt!.isUtc, isTrue);
      expect(recurrence.updatedAt.isUtc, isTrue);
      expect(recurrence.recurUntil!.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Recurrence.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'title',
        'description',
        'repeat_freq',
        'recur_until',
        'nr_of_repetitions',
        'active',
        'transactions',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('transactions_json')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '21');
      expect(parse().toJsonApi()['type'], 'recurrences');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Recurrence.fromJsonApi(
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
      expect(attributes['transactions'], templates);
      expect(attributes['recur_until'], '2027-12-31T00:00:00.000Z');
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = Recurrence.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(jsonDecode(row['transactions_json']! as String), templates);
      expect(row['recur_until'], '2027-12-31T00:00:00.000Z');
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['title'], 'Monthly rent');
      expect(row['transactions_json'], isA<String>());
    });

    test('an unparseable timestamp never throws', () {
      final recurrence = Recurrence.fromJsonApi(
        <String, dynamic>{
          'type': 'recurrences',
          'id': '1',
          'attributes': <String, dynamic>{
            'title': 'Bad date',
            'updated_at': 'not-a-timestamp',
            'recur_until': 'also-bad',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(recurrence.remoteUpdatedAt, isNull);
      expect(recurrence.recurUntil, isNull);
    });
  });
}
