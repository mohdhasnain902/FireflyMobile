import 'package:firefly_mobile/domain/entities/json_api.dart';
import 'package:firefly_mobile/domain/entities/row_codec.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transaction.freezed.dart';

/// One journal line of a Firefly III transaction (DESIGN §5.1).
///
/// A Firefly "transaction" resource is a *group* whose
/// `attributes.transactions` is an array of journal legs; the captured
/// fixture is a single-leg group where the group id and the journal id happen
/// to coincide. This model is one leg, which is what the `transactions` table
/// stores, so `fromJsonApi` takes the group member plus a `journalIndex` and
/// reads the leg at that position.
///
/// [journalId] is the leg's `transaction_journal_id`, the key DESIGN.md §391
/// names for `PUT /api/v1/transaction-journals/{journal_id}`. [fireflyId] is
/// the *group* id the member carries, which is what DESIGN §7 pull matching
/// (`WHERE firefly_id = resource_id`) and a whole-group write
/// (`PUT /api/v1/transactions/{group_id}`) need — the schema stores it via
/// the shared bookkeeping columns (DESIGN §5.1 uses transactions as its
/// example table).
@freezed
abstract class Transaction with _$Transaction, SyncBookkeeping {
  /// Builds a transaction journal from its local and remote fields.
  const factory({
    required String id,
    required String type,
    required String description,
    required DateTime date,
    required String amount,
    required DateTime updatedAt,
    required int seq,
    String? fireflyId,
    String? journalId,
    String? currencyCode,
    String? currencyId,
    String? sourceAccountId,
    String? destAccountId,
    String? sourceName,
    String? destName,
    String? categoryId,
    String? categoryName,
    String? budgetId,
    String? budgetName,
    String? billId,
    String? billName,
    String? tagsJson,
    String? notes,
    String? foreignAmount,
    String? foreignCurrencyCode,
    @Default(false) bool reconciled,
    DateTime? remoteUpdatedAt,
    @Default(SyncStatus.pending) SyncStatus syncStatus,
    DateTime? deletedAt,
  }) = _Transaction;

  const new _();

  /// Rebuilds one journal leg from a transaction-group member.
  ///
  /// [member] is the unwrapped group object. [journalIndex] selects the leg to
  /// materialise and defaults to the first, which is the whole transaction for
  /// every non-split case. A missing, empty or out-of-range `transactions`
  /// array yields empty optional fields rather than a throw, because a pull
  /// must survive a group whose legs are not yet readable.
  factory fromJsonApi(
    Map<String, dynamic> member, {
    required String id,
    required DateTime updatedAt,
    required int seq,
    int journalIndex = 0,
    SyncStatus syncStatus = SyncStatus.synced,
    DateTime? deletedAt,
  }) {
    final attributes = jsonApiAttributes(member);
    final journals = jsonList(attributes['transactions']);
    final hasJournal =
        journalIndex >= 0 && journalIndex < journals.length;
    final journal = jsonObject(hasJournal ? journals[journalIndex] : null);

    return Transaction(
      id: id,
      fireflyId: jsonApiId(member),
      type: jsonString(journal, 'type') ?? '',
      description: jsonString(journal, 'description') ?? '',
      date: isoJsonToDateTime(journal['date']) ?? DateTime.utc(1970),
      amount: jsonDecimal(journal, 'amount') ?? '0',
      journalId: jsonString(journal, 'transaction_journal_id'),
      currencyCode: jsonString(journal, 'currency_code'),
      currencyId: jsonString(journal, 'currency_id'),
      sourceAccountId: jsonString(journal, 'source_id'),
      destAccountId: jsonString(journal, 'destination_id'),
      sourceName: jsonString(journal, 'source_name'),
      destName: jsonString(journal, 'destination_name'),
      categoryId: jsonString(journal, 'category_id'),
      categoryName: jsonString(journal, 'category_name'),
      budgetId: jsonString(journal, 'budget_id'),
      budgetName: jsonString(journal, 'budget_name'),
      billId: jsonString(journal, 'bill_id'),
      billName: jsonString(journal, 'bill_name'),
      tagsJson: jsonListToColumn(journal['tags']),
      notes: jsonString(journal, 'notes'),
      foreignAmount: jsonDecimal(journal, 'foreign_amount'),
      foreignCurrencyCode: jsonString(journal, 'foreign_currency_code'),
      reconciled: jsonBool(journal, 'reconciled'),
      updatedAt: updatedAt,
      remoteUpdatedAt: jsonApiUpdatedAt(attributes),
      syncStatus: syncStatus,
      deletedAt: deletedAt,
      seq: seq,
    );
  }

  /// Rebuilds a transaction journal from a row of the `transactions` table.
  factory fromRow(Map<String, Object?> row) => Transaction(
    id: row['id']! as String,
    fireflyId: row['firefly_id'] as String?,
    journalId: row['journal_id'] as String?,
    type: row['type']! as String,
    description: row['description']! as String,
    date: isoToDateTime(row['date'] as String?) ?? DateTime.utc(1970),
    amount: row['amount']! as String,
    currencyCode: row['currency_code'] as String?,
    currencyId: row['currency_id'] as String?,
    sourceAccountId: row['source_account_id'] as String?,
    destAccountId: row['dest_account_id'] as String?,
    sourceName: row['source_name'] as String?,
    destName: row['dest_name'] as String?,
    categoryId: row['category_id'] as String?,
    categoryName: row['category_name'] as String?,
    budgetId: row['budget_id'] as String?,
    budgetName: row['budget_name'] as String?,
    billId: row['bill_id'] as String?,
    billName: row['bill_name'] as String?,
    tagsJson: row['tags_json'] as String?,
    notes: row['notes'] as String?,
    reconciled: sqliteBool(row['reconciled'] as int?),
    foreignAmount: row['foreign_amount'] as String?,
    foreignCurrencyCode: row['foreign_currency_code'] as String?,
    updatedAt: millisToDateTime(row['updated_at']! as int)!,
    remoteUpdatedAt: millisToDateTime(row['remote_updated_at'] as int?),
    syncStatus: syncStatusFromRow(row['sync_status'] as String?),
    deletedAt: millisToDateTime(row['deleted_at'] as int?),
    seq: row['seq']! as int,
  );

  /// The number of journal legs a transaction-group member carries.
  ///
  /// Split transactions are common (a supermarket shop is one group with one
  /// leg per category), and a list screen that only stores one leg still needs
  /// to know how many it is dropping.
  static int journalCount(Map<String, dynamic> member) =>
      jsonList(jsonApiAttributes(member)['transactions']).length;

  /// A single-leg transaction-group member carrying this journal.
  ///
  /// The member `id` re-emits [fireflyId] (the group id) so a re-pull maps
  /// back onto the same row (DESIGN §7). A multi-leg group is rebuilt by the
  /// caller, not here.
  Map<String, dynamic> toJsonApi() => jsonApiMember(
    type: 'transactions',
    id: fireflyId,
    attributes: <String, dynamic>{
      'transactions': <dynamic>[
        <String, dynamic>{
          'type': type,
          'description': description,
          'date': dateTimeToJson(date),
          'amount': amount,
          if (journalId != null) 'transaction_journal_id': journalId,
          if (currencyCode != null) 'currency_code': currencyCode,
          if (currencyId != null) 'currency_id': currencyId,
          if (sourceAccountId != null) 'source_id': sourceAccountId,
          if (destAccountId != null) 'destination_id': destAccountId,
          if (sourceName != null) 'source_name': sourceName,
          if (destName != null) 'destination_name': destName,
          if (categoryId != null) 'category_id': categoryId,
          if (categoryName != null) 'category_name': categoryName,
          if (budgetId != null) 'budget_id': budgetId,
          if (budgetName != null) 'budget_name': budgetName,
          if (billId != null) 'bill_id': billId,
          if (billName != null) 'bill_name': billName,
          if (tagsJson != null) 'tags': jsonListFromColumn(tagsJson),
          if (notes != null) 'notes': notes,
          'reconciled': reconciled,
          if (foreignAmount != null) 'foreign_amount': foreignAmount,
          if (foreignCurrencyCode != null)
            'foreign_currency_code': foreignCurrencyCode,
        },
      ],
      if (remoteUpdatedAt != null)
        'updated_at': dateTimeToJson(remoteUpdatedAt),
    },
  );

  /// The `transactions` row for this journal, columns keyed by column name.
  Map<String, Object?> toRow() => <String, Object?>{
    'id': id,
    'firefly_id': fireflyId,
    'journal_id': journalId,
    'type': type,
    'description': description,
    'date': dateTimeToIso(date),
    'amount': amount,
    'currency_code': currencyCode,
    'currency_id': currencyId,
    'source_account_id': sourceAccountId,
    'dest_account_id': destAccountId,
    'source_name': sourceName,
    'dest_name': destName,
    'category_id': categoryId,
    'category_name': categoryName,
    'budget_id': budgetId,
    'budget_name': budgetName,
    'bill_id': billId,
    'bill_name': billName,
    'tags_json': tagsJson,
    'notes': notes,
    'reconciled': sqliteInt(value: reconciled),
    'foreign_amount': foreignAmount,
    'foreign_currency_code': foreignCurrencyCode,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'remote_updated_at': dateTimeToMillis(remoteUpdatedAt),
    'sync_status': syncStatusToRow(syncStatus),
    'deleted_at': dateTimeToMillis(deletedAt),
    'seq': seq,
  };
}
