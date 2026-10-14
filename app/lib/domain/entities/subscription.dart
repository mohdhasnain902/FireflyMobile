import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'subscription.freezed.dart';

/// A Firefly III subscription — a recurring amount the app expects to receive
/// (DESIGN §3.1).
///
/// [periods] stores Firefly's computed period breakdown as the JSON array it
/// sends. [transactionJournalId] links a subscription back to the journal that
/// created it, matching the schema column of the same name.
@freezed
abstract class Subscription with _$Subscription, SyncBookkeeping {
  /// Builds a subscription from its local and remote fields.
  const factory({
    required String id,
    required String title,
    required String amount,
    required DateTime updatedAt,
    required int seq,
    String? currencyCode,
    String? currencyId,
    String? transactionJournalId,
    @Default('monthly') String repeatFreq,
    DateTime? nextDate,
    DateTime? endDate,
    String? periods,
    String? method,
    String? notes,
    String? fireflyId,
    @Default(true) bool active,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Subscription;

  const new _();

  /// Rebuilds a subscription from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Subscription(
      id: id,
      title: jsonString(attributes, 'title') ?? '',
      amount: jsonDecimal(attributes, 'amount') ?? '0',
      currencyCode: jsonString(attributes, 'currency_code'),
      currencyId: jsonString(attributes, 'currency_id'),
      transactionJournalId: jsonString(
        attributes,
        'transaction_journal_id',
      ),
      repeatFreq: jsonString(attributes, 'repeat_freq') ?? 'monthly',
      active: jsonBool(attributes, 'active', orElse: true),
      nextDate: isoJsonToDateTime(attributes['next_date']),
      endDate: isoJsonToDateTime(attributes['end_date']),
      periods: jsonListToColumn(attributes['periods']),
      method: jsonString(attributes, 'method'),
      notes: jsonString(attributes, 'notes'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a subscription from a row of the `subscriptions` table.
  factory fromRow(Map<String, Object?> row) => Subscription(
    id: row['id']! as String,
    title: row['title']! as String,
    amount: row['amount']! as String,
    currencyCode: row['currency_code'] as String?,
    currencyId: row['currency_id'] as String?,
    transactionJournalId: row['transaction_journal_id'] as String?,
    repeatFreq: (row['repeat_freq'] as String?) ?? 'monthly',
    active: sqliteBool(row['active'] as int?),
    nextDate: isoToDateTime(row['next_date'] as String?),
    endDate: isoToDateTime(row['end_date'] as String?),
    periods: row['periods'] as String?,
    method: row['method'] as String?,
    notes: row['notes'] as String?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this subscription.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'subscriptions',
    id: fireflyId,
    attributes: <String, dynamic>{
      'title': title,
      'amount': amount,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (currencyId != null) 'currency_id': currencyId,
      if (transactionJournalId != null)
        'transaction_journal_id': transactionJournalId,
      'repeat_freq': repeatFreq,
      'active': active,
      if (nextDate != null) 'next_date': dateTimeToJson(nextDate),
      if (endDate != null) 'end_date': dateTimeToJson(endDate),
      if (periods != null) 'periods': jsonListFromColumn(periods),
      if (method != null) 'method': method,
      if (notes != null) 'notes': notes,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `subscriptions` row for this subscription.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'title': title,
    'amount': amount,
    'currency_code': currencyCode,
    'currency_id': currencyId,
    'transaction_journal_id': transactionJournalId,
    'repeat_freq': repeatFreq,
    'active': sqliteInt(value: active),
    'next_date': dateTimeToIso(nextDate),
    'end_date': dateTimeToIso(endDate),
    'periods': periods,
    'method': method,
    'notes': notes,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
