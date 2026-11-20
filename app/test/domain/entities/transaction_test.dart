import 'dart:convert';

import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Transaction` (journal) entity
/// (DESIGN §5.1, §6.2).
///
/// A Firefly "transaction" resource is a *group*: `attributes.transactions` is
/// an array of journal legs. This model stores one leg, so the JSON:API tests
/// exercise [Transaction.journalCount] and the `journalIndex` parameter.
///
/// Known gap handled deliberately: [Transaction.toJsonApi] emits the group id
/// via [Transaction.fireflyId] (DESIGN §5.1/§7 pull matching) while
/// [Transaction.journalId] carries the per-leg journal id.
///
///  1. JSON:API -> model reads the enveloped `data.id` and one journal leg.
///  2. model -> JSON:API wraps the leg back into a single-leg group.
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality.
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);
  final tags = <String>['groceries', 'weekly'];

  /// A single-leg transaction-group member exactly as Firefly returns one.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'transactions',
    'id': '100',
    'attributes': <String, dynamic>{
      'transactions': <dynamic>[
        <String, dynamic>{
          'user': '1',
          'type': 'withdrawal',
          'description': 'Weekly shop',
          'date': '2026-10-12T18:30:00Z',
          'amount': '42.500000000000',
          'currency_code': 'EUR',
          'currency_id': '1',
          'source_id': '7',
          'destination_id': null,
          'source_name': 'Checking',
          'destination_name': 'Groceries store',
          'category_id': '3',
          'category_name': 'Groceries',
          'budget_id': '3',
          'budget_name': 'Groceries',
          'bill_id': null,
          'bill_name': null,
          'transaction_journal_id': '100',
          'tags': tags,
          'notes': 'Milk and eggs',
          'reconciled': false,
          'foreign_amount': '45.00',
          'foreign_currency_code': 'USD',
          'external_id': 'BANK-7788',
          'interest_date': '2026-10-12T00:00:00Z',
          'book_date': '2026-10-13T00:00:00Z',
          'process_date': '2026-10-14T00:00:00Z',
          'due_date': '2026-10-15T00:00:00Z',
          'payment_date': '2026-10-16T00:00:00Z',
          'external_url': 'https://example.com/receipt/7788',
          'internal_reference': 'REF-42',
          'order': 3,
        },
      ],
      'updated_at': '2026-10-11T08:00:00Z',
      'created_at': '2026-10-12T18:30:00Z',
      'user_id': '1',
    },
  };

  Transaction parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Transaction.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Transaction.fromJsonApi', () {
    test('reads the enveloped id and the first journal leg', () {
      final transaction = parse();

      expect(transaction.type, 'withdrawal');
      expect(transaction.description, 'Weekly shop');
      expect(transaction.date, DateTime.utc(2026, 10, 12, 18, 30));
      expect(transaction.amount, '42.500000000000');
      expect(transaction.journalId, '100');
      expect(transaction.sourceAccountId, '7');
      expect(transaction.categoryName, 'Groceries');
      expect(transaction.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(transaction.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final transaction = parse();

      expect(transaction.id, 'local-uuid-1');
      expect(transaction.updatedAt, localWrite);
      expect(transaction.seq, 7);
      expect(transaction.deletedAt, isNull);
    });

    test('stores the leg tags as JSON text', () {
      final transaction = parse();

      expect(transaction.tagsJson, isA<String>());
      expect(jsonDecode(transaction.tagsJson!), tags);
    });

    test('journalCount reports how many legs the group carries', () {
      expect(Transaction.journalCount(member()), 1);

      final split = member()
        ..['attributes'] = <String, dynamic>{
          ...member()['attributes']! as Map<String, dynamic>,
          'transactions': <dynamic>[
            <String, dynamic>{'type': 'withdrawal', 'amount': '1.00'},
            <String, dynamic>{'type': 'withdrawal', 'amount': '2.00'},
          ],
        };
      expect(Transaction.journalCount(split), 2);
    });

    test('journalIndex selects a non-default leg of a split group', () {
      final split = member()
        ..['attributes'] = <String, dynamic>{
          ...member()['attributes']! as Map<String, dynamic>,
          'transactions': <dynamic>[
            <String, dynamic>{
              'type': 'withdrawal',
              'description': 'Leg 0',
              'amount': '1.00',
              'date': '2026-10-12T18:30:00Z',
            },
            <String, dynamic>{
              'type': 'withdrawal',
              'description': 'Leg 1',
              'amount': '2.00',
              'date': '2026-10-12T18:30:00Z',
            },
          ],
        };

      final leg1 = Transaction.fromJsonApi(
        split,
        id: 'local-uuid-2',
        updatedAt: localWrite,
        seq: 8,
        journalIndex: 1,
      );

      expect(leg1.description, 'Leg 1');
      expect(leg1.amount, '2.00');
    });

    test('an empty or out-of-range leg never throws', () {
      final empty = Transaction.fromJsonApi(
        <String, dynamic>{
          'type': 'transactions',
          'id': '1',
          'attributes': <String, dynamic>{'transactions': <dynamic>[]},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(empty.type, '');
      expect(empty.amount, '0');
      expect(empty.date, DateTime.utc(1970));

      final outOfRange = Transaction.fromJsonApi(
        member(),
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
        journalIndex: 5,
      );

      expect(outOfRange.type, '');
      expect(outOfRange.amount, '0');
    });

    test('tolerates attributes the model does not store', () {
      final transaction = Transaction.fromJsonApi(
        <String, dynamic>{
          'type': 'transactions',
          'id': '1',
          'attributes': <String, dynamic>{
            'transactions': <dynamic>[
              <String, dynamic>{
                'type': 'deposit',
                'description': 'Bare',
                'date': '2026-01-01T00:00:00Z',
                'amount': '1.00',
              },
            ],
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(transaction.currencyCode, isNull);
      expect(transaction.tagsJson, isNull);
      expect(transaction.notes, isNull);
      expect(transaction.reconciled, isFalse);
      expect(transaction.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final transaction = parse();

      expect(transaction.remoteUpdatedAt!.isUtc, isTrue);
      expect(transaction.updatedAt.isUtc, isTrue);
      expect(transaction.date.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Transaction.toJsonApi', () {
    test('wraps the leg back into a single-leg group', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;
      final legs = attributes['transactions']! as List<dynamic>;
      final leg = legs.single! as Map<String, dynamic>;

      expect(leg.keys, unorderedEquals(<String>[
        'type',
        'description',
        'date',
        'amount',
        'transaction_journal_id',
        'currency_code',
        'currency_id',
        'source_id',
        'source_name',
        'destination_name',
        'category_id',
        'category_name',
        'budget_id',
        'budget_name',
        'tags',
        'notes',
        'reconciled',
        'foreign_amount',
        'foreign_currency_code',
        'external_id',
        'interest_date',
        'book_date',
        'process_date',
        'due_date',
        'payment_date',
        'external_url',
        'internal_reference',
        'order',
        // destination_id is null in the fixture, so it is omitted
        // (optional legs follow the same omit-if-null rule as every entity).
      ]));
      expect(leg['tags'], tags);
      expect(leg['reconciled'], isFalse);
    });

    test('re-emits the group id so a re-pull matches the same row', () {
      final json = parse().toJsonApi();

      expect(json['id'], '100');
      expect(json['type'], 'transactions');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Transaction.fromJsonApi(
        original.toJsonApi(),
        id: original.id,
        updatedAt: original.updatedAt,
        seq: original.seq,
        syncStatus: original.syncStatus,
      );

      // Group id (fireflyId) and journal id (journalId) both round-trip.
      expect(rebuilt, original);
      expect(rebuilt.toJsonApi(), original.toJsonApi());

      final attributes =
          rebuilt.toJsonApi()['attributes']! as Map<String, dynamic>;
      expect(attributes['updated_at'], '2026-10-11T08:00:00.000Z');
      final legs = attributes['transactions']! as List<dynamic>;
      expect((legs.single! as Map<String, dynamic>)['date'],
          '2026-10-12T18:30:00.000Z');
    });

    test('SQLite row -> model -> SQLite row is stable', () {
      final original = parse();

      final rebuilt = Transaction.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());

      final row = rebuilt.toRow();
      expect(jsonDecode(row['tags_json']! as String), tags);
      expect(row['firefly_id'], '100');
      expect(row['date'], '2026-10-12T18:30:00.000Z');
      expect(row['journal_id'], '100');
      expect(row['reconciled'], 0);
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['description'], 'Weekly shop');
      expect(row['amount'], '42.500000000000');
    });

    test('the Options block survives both round trips', () {
      // Firefly's transaction form carries these eight per-journal fields; both
      // directions must keep them so a phone write cannot clear them.
      final original = parse();

      expect(original.externalId, 'BANK-7788');
      expect(original.interestDate, DateTime.utc(2026, 10, 12));
      expect(original.bookDate, DateTime.utc(2026, 10, 13));
      expect(original.processDate, DateTime.utc(2026, 10, 14));
      expect(original.dueDate, DateTime.utc(2026, 10, 15));
      expect(original.paymentDate, DateTime.utc(2026, 10, 16));
      expect(original.externalUrl, 'https://example.com/receipt/7788');
      expect(original.internalReference, 'REF-42');
      expect(original.order, 3);

      final leg = ((original.toJsonApi()['attributes']!
              as Map<String, dynamic>)['transactions']!
          as List<dynamic>).single! as Map<String, dynamic>;
      expect(leg['interest_date'], '2026-10-12T00:00:00.000Z');
      expect(leg['external_url'], 'https://example.com/receipt/7788');
      expect(leg['internal_reference'], 'REF-42');
      expect(leg['order'], 3);

      final row = Transaction.fromRow(original.toRow());
      expect(row, original);
      expect(original.toRow()['order_index'], 3);
      expect(original.toRow()['book_date'], '2026-10-13T00:00:00.000Z');
    });

    test('an unparseable timestamp never throws', () {
      final transaction = Transaction.fromJsonApi(
        <String, dynamic>{
          'type': 'transactions',
          'id': '1',
          'attributes': <String, dynamic>{
            'transactions': <dynamic>[
              <String, dynamic>{
                'type': 'withdrawal',
                'description': 'Bad date',
                'date': 'not-a-timestamp',
                'amount': '1.00',
              },
            ],
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(transaction.remoteUpdatedAt, isNull);
      expect(transaction.date, DateTime.utc(1970));
    });
  });
}
