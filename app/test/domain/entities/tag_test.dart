import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the Tag entity (DESIGN §5.1, §6.2).
///
/// Every entity model must satisfy four properties:
///
///  1. JSON:API -> model reads the enveloped `data.id` and `attributes`.
///  2. model -> JSON:API emits only fields the schema stores.
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality.
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);

  /// A JSON:API member exactly as Firefly returns one (the capture in
  /// `test/fixtures/api/tags.json` is empty, so this mirrors the category
  /// template: one representative tag plus the local-only caller values).
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'tags',
    'id': '9',
    'attributes': <String, dynamic>{
      'tag': 'groceries',
      'date': '2026-01-15T00:00:00Z',
      'created_at': '2025-03-04T05:06:07Z',
      'updated_at': '2026-10-11T08:00:00Z',
      'user_id': '1',
    },
  };

  Tag parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Tag.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Tag.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final tag = parse();

      expect(tag.tag, 'groceries');
      expect(tag.date, DateTime.utc(2026, 1, 15));
      expect(tag.fireflyId, '9');
      expect(tag.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(tag.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final tag = parse();

      expect(tag.id, 'local-uuid-1');
      expect(tag.updatedAt, localWrite);
      expect(tag.seq, 7);
      expect(tag.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final tag = Tag.fromJsonApi(
        <String, dynamic>{
          'type': 'tags',
          'id': '1',
          'attributes': <String, dynamic>{'tag': 'Bare'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(tag.tag, 'Bare');
      expect(tag.date, isNull);
      expect(tag.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final tag = parse();

      expect(tag.date!.isUtc, isTrue);
      expect(tag.remoteUpdatedAt!.isUtc, isTrue);
      expect(tag.updatedAt.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Tag.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'tag',
        'date',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('created_at')));
      expect(attributes.keys, isNot(contains('user_id')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '9');
      expect(parse().toJsonApi()['type'], 'tags');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Tag.fromJsonApi(
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

      final rebuilt = Tag.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['tag'], 'groceries');
      expect(row['date'], isA<String>());
    });

    test('an unparseable timestamp never throws', () {
      final tag = Tag.fromJsonApi(
        <String, dynamic>{
          'type': 'tags',
          'id': '1',
          'attributes': <String, dynamic>{
            'tag': 'Bad date',
            'date': 'not-a-timestamp',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(tag.date, isNull);
      expect(tag.remoteUpdatedAt, isNull);
    });
  });
}
