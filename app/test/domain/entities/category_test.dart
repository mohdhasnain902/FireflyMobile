import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for a business entity (DESIGN §5.1, §6.2).
///
/// Every entity model must satisfy four properties, and this suite is the
/// template the other thirteen entity suites are copied from:
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
    'type': 'categories',
    'id': '42',
    'attributes': <String, dynamic>{
      'name': 'Groceries',
      'notes': 'Weekly shop',
      'created_at': '2026-01-02T03:04:05Z',
      'updated_at': '2026-10-11T08:00:00Z',
      'user_id': '1',
    },
  };

  Category parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Category.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Category.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final category = parse();

      expect(category.name, 'Groceries');
      expect(category.notes, 'Weekly shop');
      expect(category.fireflyId, '42');
      expect(category.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(category.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final category = parse();

      expect(category.id, 'local-uuid-1');
      expect(category.updatedAt, localWrite);
      expect(category.seq, 7);
      expect(category.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final category = Category.fromJsonApi(
        <String, dynamic>{
          'type': 'categories',
          'id': '1',
          'attributes': <String, dynamic>{'name': 'Bare', 'user_id': '1'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(category.name, 'Bare');
      expect(category.notes, isNull);
      expect(category.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final category = parse();

      expect(category.remoteUpdatedAt!.isUtc, isTrue);
      expect(category.updatedAt.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Category.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'name',
        'notes',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('user_id')));
      expect(attributes.keys, isNot(contains('created_at')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '42');
      expect(parse().toJsonApi()['type'], 'categories');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Category.fromJsonApi(
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

      final rebuilt = Category.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());
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
      final category = Category.fromJsonApi(
        <String, dynamic>{
          'type': 'categories',
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

      expect(category.remoteUpdatedAt, isNull);
    });
  });

  group('envelope helpers', () {
    test('jsonApiData unwraps a single-resource document', () {
      expect(jsonApiData(<String, dynamic>{'data': member()})['id'], '42');
    });

    test('jsonApiCollection unwraps a collection document', () {
      final items = jsonApiCollection(<String, dynamic>{
        'data': <dynamic>[member()],
      });

      expect(items, hasLength(1));
      expect(jsonApiId(items.single), '42');
    });

    test('malformed documents throw rather than silently dropping data', () {
      expect(
        () => jsonApiData(<String, dynamic>{'errors': <dynamic>[]}),
        throwsFormatException,
      );
      expect(
        () => jsonApiCollection(<String, dynamic>{'data': <dynamic>['nope']}),
        throwsFormatException,
      );
    });
  });
}
