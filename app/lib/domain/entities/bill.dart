import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'bill.freezed.dart';

/// A Firefly III bill — a recurring amount the app expects to leave
/// (DESIGN §3.1).
///
/// [payDates] holds the upcoming expected dates as the JSON array Firefly
/// sends, so the column round-trips without the app re-deriving a schedule it
/// does not own. [skip] is "every N periods", which is why it is an integer
/// and not a bool.
///
/// Two wire shapes matter for parity:
///
///  * Firefly never sends a single `amount`. A bill carries `amount_min`,
///    `amount_max` and the `amount_avg` it computed, and its API *requires*
///    the two bounds on write. [amount] mirrors `amount_min` (the value the
///    website shows for an exact-amount bill) and is sent back as both bounds.
///  * The next due date is `date` on the wire. It is a real field the website
///    form shows, so it is stored ([date]) instead of being dropped.
@freezed
abstract class Bill with _$Bill, SyncBookkeeping {
  /// Builds a bill from its local and remote fields.
  const factory({
    required String id,
    required String name,
    required String amount,
    required DateTime updatedAt,
    required int seq,
    String? currencyCode,
    String? currencyId,
    String? billDirection,
    @Default('monthly') String repeatFreq,
    String? payDates,
    String? remainingAmount,
    DateTime? nextExpectedMatch,
    String? notes,
    String? autoBudgetType,
    DateTime? date,
    String? fireflyId,
    @Default(0) int skip,
    @Default(true) bool active,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Bill;

  const new _();

  /// Rebuilds a bill from one JSON:API member object.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    return Bill(
      id: id,
      name: jsonString(attributes, 'name') ?? '',
      amount: jsonDecimal(attributes, 'amount_min') ??
          jsonDecimal(attributes, 'amount') ??
          jsonDecimal(attributes, 'amount_avg') ??
          '0',
      currencyCode: jsonString(attributes, 'currency_code'),
      // Mirrors `transaction_currency_id` too: that is the key the bill
      // endpoint accepts back, and the round trip must not lose it.
      currencyId: jsonString(attributes, 'currency_id') ??
          jsonString(attributes, 'transaction_currency_id'),
      billDirection: jsonString(attributes, 'bill_direction'),
      date: isoJsonToDateTime(attributes['date']),
      repeatFreq: jsonString(attributes, 'repeat_freq') ?? 'monthly',
      skip: jsonInt(attributes, 'skip') ?? 0,
      active: jsonBool(attributes, 'active', orElse: true),
      payDates: jsonListToColumn(attributes['pay_dates']),
      remainingAmount: jsonDecimal(attributes, 'remaining_amount'),
      nextExpectedMatch: isoJsonToDateTime(
        attributes['next_expected_match'],
      ),
      notes: jsonString(attributes, 'notes'),
      autoBudgetType: jsonString(attributes, 'auto_budget_type'),
      fireflyId: jsonApiId(member),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a bill from a row of the `bills` table.
  factory fromRow(Map<String, Object?> row) => Bill(
    id: row['id']! as String,
    name: row['name']! as String,
    amount: row['amount']! as String,
    currencyCode: row['currency_code'] as String?,
    currencyId: row['currency_id'] as String?,
    billDirection: row['bill_direction'] as String?,
    repeatFreq: (row['repeat_freq'] as String?) ?? 'monthly',
    skip: (row['skip'] as int?) ?? 0,
    active: sqliteBool(row['active'] as int?),
    payDates: row['pay_dates'] as String?,
    date: isoToDateTime(row['date'] as String?),
    remainingAmount: row['remaining_amount'] as String?,
    // ISO text, not epoch millis: `next_expected_match` is a business date
    // and its column is TEXT (DESIGN §5.1). Storing millis would be coerced by
    // TEXT affinity into the string '1793491200000', which then fails the
    // `as int?` read. Every other business date uses the same pair.
    nextExpectedMatch: isoToDateTime(row['next_expected_match'] as String?),
    notes: row['notes'] as String?,
    autoBudgetType: row['auto_budget_type'] as String?,
    fireflyId: row['firefly_id'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The JSON:API member object for this bill.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'bills',
    id: fireflyId,
    attributes: <String, dynamic>{
      'name': name,
      // The API rejects a bill without both bounds (422) — an exact-amount
      // bill is stored by sending the same figure twice.
      'amount_min': amount,
      'amount_max': amount,
      // Bills read the currency from `transaction_currency_id`; `currency_id`
      // and `currency_code` are ignored by the endpoint.
      if (currencyId != null) 'transaction_currency_id': currencyId,
      if (date != null) 'date': dateTimeToJson(date),
      if (billDirection != null) 'bill_direction': billDirection,
      'repeat_freq': repeatFreq,
      'skip': skip,
      'active': active,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (payDates != null) 'pay_dates': jsonListFromColumn(payDates),
      if (remainingAmount != null) 'remaining_amount': remainingAmount,
      if (nextExpectedMatch != null)
        'next_expected_match': dateTimeToJson(nextExpectedMatch),
      if (notes != null) 'notes': notes,
      if (autoBudgetType != null) 'auto_budget_type': autoBudgetType,
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `bills` row for this bill, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'name': name,
    'amount': amount,
    'currency_code': currencyCode,
    'currency_id': currencyId,
    'bill_direction': billDirection,
    'repeat_freq': repeatFreq,
    'skip': skip,
    'active': sqliteInt(value: active),
    'pay_dates': payDates,
    'date': dateTimeToIso(date),
    'remaining_amount': remainingAmount,
    // Business date, so ISO text to match the TEXT column and the other
    // entities; only bookkeeping stamps use epoch millis.
    'next_expected_match': dateTimeToIso(nextExpectedMatch),
    'notes': notes,
    'auto_budget_type': autoBudgetType,
    'firefly_id': fireflyId,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
