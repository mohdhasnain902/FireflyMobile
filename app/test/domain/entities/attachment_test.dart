import 'package:firefly_mobile/domain/entities/attachment.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:flutter_test/flutter_test.dart';

/// Round-trip contract for the `Attachment` entity (DESIGN §5.1, §6.7).
///
/// Mirrors `category_test.dart` plus the attachment-specific quirk:
/// `local_path` is local-only and is **never** emitted by `toJsonApi`,
/// because an upload is multipart, not a JSON:API document.
///
///  1. JSON:API -> model reads the enveloped `data.id` and `attributes`.
///  2. model -> JSON:API emits only stored fields (minus local_path).
///  3. JSON:API round trip preserves value equality.
///  4. SQLite row round trip preserves value equality (local_path included).
void main() {
  final localWrite = DateTime.utc(2026, 10, 13, 9, 30);

  /// A JSON:API member exactly as Firefly returns one, plus the local-only
  /// values the caller supplies because JSON:API never carries them.
  Map<String, dynamic> member() => <String, dynamic>{
    'type': 'attachments',
    'id': '9',
    'attributes': <String, dynamic>{
      'filename': 'receipt.pdf',
      'notes': 'October rent',
      'md5': 'a' * 32,
      'size': 102400,
      'mime_type': 'application/pdf',
      'download_url': 'https://firefly.example/api/v1/attachments/9/download',
      'updated_at': '2026-10-11T08:00:00Z',
      'created_at': '2026-01-01T00:00:00Z',
      'user_id': '1',
    },
  };

  Attachment parse({
    SyncStatus syncStatus = SyncStatus.synced,
    String? localPath,
  }) => Attachment.fromJsonApi(
    member(),
    id: 'local-uuid-1',
    updatedAt: localWrite,
    seq: 7,
    syncStatus: syncStatus,
  ).copyWith(localPath: localPath);

  group('Attachment.fromJsonApi', () {
    test('reads the enveloped id and attributes', () {
      final attachment = parse();

      expect(attachment.filename, 'receipt.pdf');
      expect(attachment.notes, 'October rent');
      expect(attachment.md5, 'a' * 32);
      expect(attachment.size, 102400);
      expect(attachment.mimeType, 'application/pdf');
      expect(attachment.fireflyId, '9');
      expect(attachment.remoteUpdatedAt, DateTime.utc(2026, 10, 11, 8));
      expect(attachment.syncStatus, SyncStatus.synced);
    });

    test('applies the local-only fields passed by the caller', () {
      final attachment = parse();

      expect(attachment.id, 'local-uuid-1');
      expect(attachment.updatedAt, localWrite);
      expect(attachment.seq, 7);
      expect(attachment.deletedAt, isNull);
      expect(attachment.localPath, isNull);
    });

    test('tolerates attributes the model does not store', () {
      final attachment = Attachment.fromJsonApi(
        <String, dynamic>{
          'type': 'attachments',
          'id': '1',
          'attributes': <String, dynamic>{'filename': 'bare.png'},
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(attachment.filename, 'bare.png');
      expect(attachment.notes, isNull);
      expect(attachment.md5, isNull);
      expect(attachment.size, isNull);
      expect(attachment.mimeType, isNull);
      expect(attachment.downloadUrl, isNull);
      expect(attachment.remoteUpdatedAt, isNull);
    });

    test('returns UTC timestamps so value equality survives a round trip', () {
      final attachment = parse();

      expect(attachment.remoteUpdatedAt!.isUtc, isTrue);
      expect(attachment.updatedAt.isUtc, isTrue);
    });

    test('defaults to synced because the server just acknowledged it', () {
      expect(parse().syncStatus, SyncStatus.synced);
      expect(
        parse(syncStatus: SyncStatus.conflict).syncStatus,
        SyncStatus.conflict,
      );
    });
  });

  group('Attachment.toJsonApi', () {
    test('emits only the fields the schema stores', () {
      final json = parse(localPath: '/tmp/pending/receipt.pdf').toJsonApi();
      final attributes = json['attributes']! as Map<String, dynamic>;

      expect(attributes.keys, unorderedEquals(<String>[
        'filename',
        'notes',
        'md5',
        'size',
        'mime_type',
        'download_url',
        'updated_at',
      ]));
      expect(attributes.keys, isNot(contains('id')));
      expect(attributes.keys, isNot(contains('seq')));
      expect(attributes.keys, isNot(contains('sync_status')));
      expect(attributes.keys, isNot(contains('local_path')));
    });

    test('re-emits the server id so a re-pull matches the same row', () {
      expect(parse().toJsonApi()['id'], '9');
      expect(parse().toJsonApi()['type'], 'attachments');
    });
  });

  group('round trips', () {
    test('JSON:API member -> model -> JSON:API member is stable', () {
      final original = parse();

      final rebuilt = Attachment.fromJsonApi(
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
      final original = parse(localPath: '/tmp/pending/receipt.pdf');

      final rebuilt = Attachment.fromRow(original.toRow());

      expect(rebuilt, original);
      expect(rebuilt.toRow(), original.toRow());
      expect(rebuilt.localPath, '/tmp/pending/receipt.pdf');
    });

    test('the row keeps epochs as integers and status as text', () {
      final row = parse().toRow();

      expect(row['updated_at'], isA<int>());
      expect(row['remote_updated_at'], isA<int>());
      expect(row['seq'], 7);
      expect(row['sync_status'], 'synced');
      expect(row['filename'], 'receipt.pdf');
      expect(row['size'], 102400);
      expect(row['local_path'], isNull);
    });

    test('an unparseable timestamp never throws', () {
      final attachment = Attachment.fromJsonApi(
        <String, dynamic>{
          'type': 'attachments',
          'id': '1',
          'attributes': <String, dynamic>{
            'filename': 'Bad date',
            'updated_at': 'not-a-timestamp',
          },
        },
        id: 'x',
        updatedAt: localWrite,
        seq: 1,
      );

      expect(attachment.remoteUpdatedAt, isNull);
    });
  });
}
