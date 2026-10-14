import 'package:firefly_mobile/domain/entities/rule_group.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the RuleGroup entity (DESIGN §5.1, §6.2).
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
  /// `test/fixtures/api/rule_groups.json` is empty, so this mirrors the
  /// category template: one representative group plus caller-only values).
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'rule_groups',
    'id': '11',
    'attributes': <String, dynamic>{
      'title': 'Imported rows',
      'description': 'Normalises the bank import feed',
      'active': false,
      'order': 5,
      'created_at': '2025-08-19T07:15:00Z',
      'updated_at': '2026-10-11T08:00:00Z',
      'user_id': '1',
    },
  };

  RuleGroup parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      RuleGroup.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('RuleGroup.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final group = parse();

      expect(group.title, 'Imported rows');
      expect(group.description, 'Normalises the bank import feed');
      expect(group.active, isFalse);
      expect(group.orderIndex, 5);
      expect(group.fireflyId, '11');
      expect(group.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(group.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final group = parse();

      expect(group.id, 'local-uuid-1');
      expect(group.updatedAt, localWrite);
      expect(group.seq, 7);
      expect(group.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final group = RuleGroup.fromJsonApi(
        <String, dynamic>{
          'type': 'rule_groups',
          'id': '1',
          'attributes': <String, dynamic>{'title': 'Bare'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(group.title, 'Bare');
      expect(group.description, isNull);
      expect(group.active, isTrue);
      expect(group.orderIndex, isNull);
      expect(group.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final group = parse();

      expect(group.remoteUpdatedAt!.isUtc, isTrue);
      expect(group.updatedAt.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('RuleGroup.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'title',
        'description',
        'active',
        'order',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('created_at')));
      expect(attributes.keys, isNot(contains('user_id')));
      expect(attributes.keys, isNot(contains('order_index')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '11');
      expect(parse().toJsonApi()['type'], 'rule_groups');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = RuleGroup.fromJsonApi(
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

      final rebuilt = RuleGroup.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['title'], 'Imported rows');
      expect(row['order_index'], 5);
      expect(row['active'], 0);
    });

    test('an unparseable timestamp never throws', () {
      final group = RuleGroup.fromJsonApi(
        <String, dynamic>{
          'type': 'rule_groups',
          'id': '1',
          'attributes': <String, dynamic>{
            'title': 'Bad date',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(group.remoteUpdatedAt, isNull);
    });
  });
}
