import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'budget_limit.freezed.dart';

/// A budgeted period under a budget (DESIGN §3.1, §6.4).
///
/// A budget itself is the container; [budgetId] links a limit to it and
/// [start]/[end] bracket the period the amount applies to. `start` and `end`
/// are reserved words in Dart only as keywords, so they stay as field names.
@freezed
abstract class BudgetLimit with _$BudgetLimit, SyncBookkeeping {
  /// Builds a budget limit from its local and remote fields.
  const factory({
    required String id,
    required String budgetId,
    required DateTime start,
    required DateTime end,
    required String amount,
    required DateTime updatedAt,
    required int seq,
    String? currencyCode,
    String? currencyId,
    String? notes,
    String? fireflyId,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _BudgetLimit;

  const new _();

  /// Rebuilds a budget limit from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return BudgetLimit(
      id: id,
      budgetId: jsonString(attributes, 'budget_id') ?? '',
      start: isoJsonToDateTime(attributes['start']) ?? DateTime.utc(1970),
      end: isoJsonToDateTime(attributes['end']) ?? DateTime.utc(1970),
      amount: jsonDecimal(attributes, 'amount') ?? '0',
      currencyCode: jsonString(attributes, 'currency_code'),
      currencyId: jsonString(attributes, 'currency_id'),
      notes: jsonString(attributes, 'notes'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a budget limit from a row of the `budget_limits` table.
  ///
  /// A malformed date falls back to the Unix epoch rather than throwing so one
  /// corrupt row cannot abort a pull.
  factory fromRow(Map<String, Object?> row) => BudgetLimit(
    id: row['id']! as String,
    budgetId: row['budget_id']! as String,
    start: isoToDateTime(row['start'] as String?) ?? DateTime.utc(1970),
    end: isoToDateTime(row['end'] as String?) ?? DateTime.utc(1970),
    amount: row['amount']! as String,
    currencyCode: row['currency_code'] as String?,
    currencyId: row['currency_id'] as String?,
    notes: row['notes'] as String?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this budget limit.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'budget_limits',
    id: fireflyId,
    attributes: <String, dynamic>{
      'budget_id': budgetId,
      'start': dateTimeToJson(start),
      'end': dateTimeToJson(end),
      'amount': amount,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (currencyId != null) 'currency_id': currencyId,
      if (notes != null) 'notes': notes,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `budget_limits` row for this budget limit.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'budget_id': budgetId,
    'start': dateTimeToIso(start),
    'end': dateTimeToIso(end),
    'amount': amount,
    'currency_code': currencyCode,
    'currency_id': currencyId,
    'notes': notes,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
