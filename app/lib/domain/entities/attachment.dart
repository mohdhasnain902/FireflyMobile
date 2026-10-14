import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'attachment.freezed.dart';

/// An attachment on a transaction (DESIGN §3.1, §6.7).
///
/// The bytes live on disk; the row holds only metadata plus [localPath], the
/// app-private path of a file staged for multipart upload. [localPath] has no
/// wire counterpart — a create payload is a `multipart/form-data` body, not a
/// JSON:API document, so [toJsonApi] deliberately never emits it.
@freezed
abstract class Attachment with _$Attachment, SyncBookkeeping {
  /// Builds an attachment from its local and remote fields.
  const factory({
    required String id,
    required String filename,
    required DateTime updatedAt,
    required int seq,
    String? notes,
    String? md5,
    String? mimeType,
    String? downloadUrl,
    String? localPath,
    String? fireflyId,
    int? size,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Attachment;

  const new _();

  /// Rebuilds an attachment from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Attachment(
      id: id,
      filename: jsonString(attributes, 'filename') ?? '',
      notes: jsonString(attributes, 'notes'),
      md5: jsonString(attributes, 'md5'),
      size: jsonInt(attributes, 'size'),
      mimeType: jsonString(attributes, 'mime_type'),
      downloadUrl: jsonString(attributes, 'download_url'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds an attachment from a row of the `attachments` table.
  factory fromRow(Map<String, Object?> row) => Attachment(
    id: row['id']! as String,
    filename: row['filename']! as String,
    notes: row['notes'] as String?,
    md5: row['md5'] as String?,
    size: row['size'] as int?,
    mimeType: row['mime_type'] as String?,
    downloadUrl: row['download_url'] as String?,
    localPath: row['local_path'] as String?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this attachment's metadata.
  ///
  /// [localPath] is intentionally absent: uploading the bytes is a multipart
  /// POST, which the repository layer issues outside this model.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'attachments',
    id: fireflyId,
    attributes: <String, dynamic>{
      'filename': filename,
      if (notes != null) 'notes': notes,
      if (md5 != null) 'md5': md5,
      if (size != null) 'size': size,
      if (mimeType != null) 'mime_type': mimeType,
      if (downloadUrl != null) 'download_url': downloadUrl,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `attachments` row for this attachment.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'filename': filename,
    'notes': notes,
    'md5': md5,
    'size': size,
    'mime_type': mimeType,
    'download_url': downloadUrl,
    'local_path': localPath,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
