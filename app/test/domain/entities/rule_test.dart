import 'package:firefly_mobile/domain/entities/rule.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the Rule entity (DESIGN §5.1, §6.2).
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
  /// `test/fixtures/api/rules.json` is empty, so this mirrors the category
  /// template: one representative rule plus the caller-only values).
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'rules',
    'id': '7',
    'attributes': <String, dynamic>{
      'title': 'Category by description',
      'description': 'Tags the weekly supermarket shop',
      'rule_group_id': '3',
      'trigger': 'transactions',
      'scope': 'all',
      'active': true,
      'strict': false,
      'stop': true,
      'order': 4,
      'triggers': <dynamic>[
        <String, dynamic>{
          'type': 'description_contains',
          'value': 'supermarket',
          'inverse': false,
        },
      ],
      'actions': <dynamic>[
        <String, dynamic>{
          'type': 'set_category',
          'value': 'Groceries',
          'active': true,
        },
      ],
      'created_at': '2025-09-01T14:30:00Z',
      'updated_at': '2026-10-11T08:00:00Z',
      'user_id': '1',
    },
  };

  Rule parse({SyncStatus syncStatus = SyncStatus.synced}) =>
      Rule.fromJsonApi(
        member(),
        id: 'local-uuid-1',
        updatedAt: localWrite,
        seq: 7,
        syncStatus: syncStatus,
      );

  group('Rule.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final rule = parse();

      expect(rule.title, 'Category by description');
      expect(rule.description, 'Tags the weekly supermarket shop');
      expect(rule.ruleGroupId, '3');
      expect(rule.trigger, 'transactions');
      expect(rule.scope, 'all');
      expect(rule.active, isTrue);
      expect(rule.strict, isFalse);
      expect(rule.stop, isTrue);
      expect(rule.orderIndex, 4);
      expect(rule.triggersJson, contains('description_contains'));
      expect(rule.actionsJson, contains('set_category'));
      expect(rule.fireflyId, '7');
      expect(rule.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(rule.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final rule = parse();

      expect(rule.id, 'local-uuid-1');
      expect(rule.updatedAt, localWrite);
      expect(rule.seq, 7);
      expect(rule.deletedAt, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final rule = Rule.fromJsonApi(
        <String, dynamic>{
          'type': 'rules',
          'id': '1',
          'attributes': <String, dynamic>{'title': 'Bare'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(rule.title, 'Bare');
      expect(rule.description, isNull);
      expect(rule.ruleGroupId, isNull);
      expect(rule.trigger, isNull);
      expect(rule.scope, isNull);
      expect(rule.triggersJson, isNull);
      expect(rule.actionsJson, isNull);
      expect(rule.active, isTrue);
      expect(rule.strict, isFalse);
      expect(rule.stop, isFalse);
      expect(rule.orderIndex, isNull);
      expect(rule.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final rule = parse();

      expect(rule.remoteUpdatedAt!.isUtc, isTrue);
      expect(rule.updatedAt.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Rule.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse().toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'title',
        'description',
        'rule_group_id',
        'trigger',
        'scope',
        'active',
        'strict',
        'stop',
        'order',
        'triggers',
        'actions',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('created_at')));
      expect(attributes.keys, isNot(contains('user_id')));
      expect(attributes.keys, isNot(contains('order_index')));
      expect(attributes.keys, isNot(contains('triggers_json')));
      expect(attributes.keys, isNot(contains('actions_json')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '7');
      expect(parse().toJsonApi()['type'], 'rules');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Rule.fromJsonApi(
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

      final rebuilt = Rule.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['title'], 'Category by description');
      expect(row['rule_group_id'], '3');
      expect(row['order_index'], 4);
      expect(row['triggers_json'], isA<String>());
      expect(row['actions_json'], isA<String>());
    });

    test('an unparseable timestamp never throws', () {
      final rule = Rule.fromJsonApi(
        <String, dynamic>{
          'type': 'rules',
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

      expect(rule.remoteUpdatedAt, isNull);
    });
  });
}
