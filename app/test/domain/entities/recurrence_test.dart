import 'dart:convert';

import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/recurrence_repetition.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Recurrence` entity (DESIGN §5.1, §6.2).
///
/// Mirrors `category_test.dart` plus the recurrence-specific quirks: the wire
/// attribute is `transactions` but the column is `transactions_json`, the wire
/// schedule cap is `repeat_until` (not the older `recur_until`), and the
/// frequency is the 1:N `repetitions[]` child array rather than a flat
/// `repeat_freq`.
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
  final wireRepetitions = <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'monthly',
      'moment': '17',
      'skip': 0,
      'weekend': 1,
    },
    <String, dynamic>{
      'type': 'yearly',
      'moment': '2026-03-01',
      'skip': 1,
      'weekend': 3,
    },
  ];

  /// A JSON:API member exactly as Firefly returns one, plus the local-only
  /// values the caller supplies because JSON:API never carries them.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'recurrences',
    'id': '21',
    'attributes': <String, dynamic>{
      'title': 'Monthly rent',
      'type': 'withdrawal',
      'description': 'Pay the landlord',
      'first_date': '2026-01-01T00:00:00Z',
      'repeat_until': '2027-12-31T00:00:00Z',
      'nr_of_repetitions': 24,
      'active': true,
      'apply_rules': true,
      'transactions': templates,
      'repetitions': wireRepetitions,
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
      expect(recurrence.type, 'withdrawal');
      expect(recurrence.description, 'Pay the landlord');
      expect(recurrence.firstDate, DateTime.utc(2026));
      expect(recurrence.repeatUntil, DateTime.utc(2027, 12, 31));
      expect(recurrence.nrOfRepetitions, 24);
      expect(recurrence.applyRules, isTrue);
      expect(recurrence.fireflyId, '21');
      expect(recurrence.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(recurrence.syncStatus, SyncStatus.synced);
    });

    test('parses the wire repetitions[] array into child entities', () {
      final recurrence = parse();

      expect(recurrence.repetitions, hasLength(2));

      final monthly = recurrence.repetitions[0];
      expect(monthly.recurrenceId, 'local-uuid-1');
      expect(monthly.ord, 0);
      expect(monthly.repetitionType, 'monthly');
      expect(monthly.repetitionMoment, '17');
      expect(monthly.repetitionSkip, 0);
      expect(monthly.weekend, RecurrenceWeekend.doNothing);

      final yearly = recurrence.repetitions[1];
      expect(yearly.ord, 1);
      expect(yearly.repetitionType, 'yearly');
      expect(yearly.repetitionMoment, '2026-03-01');
      expect(yearly.repetitionSkip, 1);
      expect(yearly.weekend, RecurrenceWeekend.toFriday);
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
      expect(recurrence.type, isNull);
      expect(recurrence.description, isNull);
      expect(recurrence.firstDate, isNull);
      expect(recurrence.repeatUntil, isNull);
      expect(recurrence.nrOfRepetitions, isNull);
      expect(recurrence.transactionsJson, isNull);
      expect(recurrence.repetitions, isEmpty);
      expect(recurrence.active, isTrue);
      expect(recurrence.applyRules, isTrue);
      expect(recurrence.remoteUpdatedAt, isNull);
    });

    test('skips a malformed repetitions[] element without throwing', () {
      final recurrence = Recurrence.fromJsonApi(
        <String, dynamic>{
          'type': 'recurrences',
          'id': '2',
          'attributes': <String, dynamic>{
            'title': 'Partial',
            'repetitions': <dynamic>[
              'not-a-map',
              <String, dynamic>{'type': 'daily', 'moment': ''},
            ],
          },
        },
        id: 'y',
        updatedAt: localWrite,
        seq: 2,
      );

      expect(recurrence.repetitions, hasLength(1));
      expect(recurrence.repetitions.single.repetitionType, 'daily');
      expect(recurrence.repetitions.single.repetitionSkip, 0);
      expect(
        recurrence.repetitions.single.weekend,
        RecurrenceWeekend.doNothing,
      );
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final recurrence = parse();

      expect(recurrence.remoteUpdatedAt!.isUtc, isTrue);
      expect(recurrence.updatedAt.isUtc, isTrue);
      expect(recurrence.firstDate!.isUtc, isTrue);
      expect(recurrence.repeatUntil!.isUtc, isTrue);
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
        'type',
        'description',
        'first_date',
        'repeat_until',
        'nr_of_repetitions',
        'active',
        'apply_rules',
        'transactions',
        'repetitions',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('transactions_json')));
      expect(attributes.keys, isNot(contains('latest_date')));
      expect(attributes.keys, isNot(contains('repeat_freq')));
      expect(attributes.keys, isNot(contains('recur_until')));
    });

    test('emits repetitions[] as the four wire keys only', () {
      final attributes =
          parse().toJsonApi()['attributes']! as Map<String, dynamic>;
      final repetitions = attributes['repetitions']! as List<dynamic>;

      expect(repetitions, hasLength(2));
      expect(
        (repetitions[0] as Map<String, dynamic>).keys,
        unorderedEquals(<String>['type', 'moment', 'skip', 'weekend']),
      );
      expect((repetitions[0] as Map<String, dynamic>)['type'], 'monthly');
      expect((repetitions[1] as Map<String, dynamic>)['weekend'], 3);
    });

    test('omits repetitions[] when the schedule is empty', () {
      final bare = Recurrence.fromJsonApi(
        <String, dynamic>{
          'type': 'recurrences',
          'id': '3',
          'attributes': <String, dynamic>{'title': 'No schedule'},
        },
        id: 'z',
        updatedAt: localWrite,
        seq: 3,
      );

      final attributes =
          bare.toJsonApi()['attributes']! as Map<String, dynamic>;
      expect(attributes.containsKey('repetitions'), isFalse);
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
      expect(attributes['repeat_until'], '2027-12-31T00:00:00.000Z');
      expect(attributes['repetitions'], wireRepetitions);
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      // The parent row cannot know its children, so the child table is read
      // back separately — exactly what `RecurrenceDao` does after every read.
      final rebuilt = Recurrence.fromRow(original.toRow())
          .loadRepetitions(original.repetitionRows());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());
      expect(rebuilt.repetitionRows(), original.repetitionRows());

      final row = rebuilt.toRow();
      expect(jsonDecode(row['transactions_json']! as String), templates);
      expect(row['repeat_until'], '2027-12-31T00:00:00.000Z');
      expect(row['first_date'], '2026-01-01T00:00:00.000Z');
      expect(row['type'], 'withdrawal');
    });

    test('repetitionRows map back to the same child entities', () {
      final original = parse();
      final rows = original.repetitionRows();

      expect(rows, hasLength(2));
      expect(rows[0], <String, Object?>{
        'recurrence_id': 'local-uuid-1',
        'ord': 0,
        'repetition_type': 'monthly',
        'repetition_moment': '17',
        'repetition_skip': 0,
        'weekend': 1,
      });

      final rebuilt = rows.map(RecurrenceRepetition.fromRow).toList();
      expect(rebuilt, original.repetitions);
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['title'], 'Monthly rent');
      expect(row['type'], 'withdrawal');
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
            'first_date': 'also-bad',
            'repeat_until': 'also-bad',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(recurrence.remoteUpdatedAt, isNull);
      expect(recurrence.firstDate, isNull);
      expect(recurrence.repeatUntil, isNull);
    });
  });
}
