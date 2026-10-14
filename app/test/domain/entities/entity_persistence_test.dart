import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/attachment.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/piggy_bank.dart';
import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/rule.dart';
import 'package:firefly_mobile/domain/entities/rule_group.dart';
import 'package:firefly_mobile/domain/entities/subscription.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
// `sqflite_common` exports its own `Transaction` transaction-controller type,
// which collides with the entity of the same name. The entity is what this
// file means, so the sqflite symbol is hidden rather than the entity prefixed.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

import '../../data/db/app_database_test.dart';

/// Persists every business entity through real SQLite (DESIGN §5.1).
///
/// The per-entity suites prove `toRow`/`fromRow` agree with *each other*; they
/// cannot prove either agrees with the *table*. An entity that emits a column
/// the DDL never created passes an in-memory round trip and then fails at the
/// first real INSERT. This suite closes that gap by driving the actual schema:
/// insert a fully-populated row, read it back, and require the parsed model to
/// equal the original. Every optional field is populated on purpose, so a
/// dropped column shows up as an inequality rather than a silent null.
void main() {
  setUpAll(sqfliteFfiInit);

  // One database for the whole suite, not one per test. The ffi factory reuses
  // a `:memory:` handle across opens, so a fresh `openTestDatabase()` per test
  // would silently see the previous test's rows — which turns a failed
  // round-trip's leftover id into an unrelated UNIQUE violation in the next
  // test. A suite-lifetime handle removes that coupling and keeps the run
  // fast; nothing here needs isolation, because each entity owns its table.
  late final Database db;
  setUpAll(() async => db = await openTestDatabase());
  tearDownAll(() => db.close());

  final writtenAt = DateTime.utc(2026, 10, 13, 9, 30);
  final remoteAt = DateTime.utc(2026, 10, 11, 8);
  final seenAt = DateTime.utc(2026, 10, 2);

  // Samples live in locals so each case can capture both the model and the row
  // it produces. Keeping the row typed as `Map<String, Object?>` here is what
  // lets the loop below stay free of `dynamic` dispatch.
  final currency = Currency(
    id: 'row-1',
    code: 'USD',
    name: 'US Dollar',
    symbol: r'$',
    symbolFirst: true,
    isDefault: true,
    rate: '1.0842',
    fireflyId: '12',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 3,
  );

  final tag = Tag(
    id: 'row-2',
    tag: 'holiday',
    date: seenAt,
    fireflyId: '4',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 4,
  );

  final ruleGroup = RuleGroup(
    id: 'row-3',
    title: 'Recurring',
    description: 'Rules run on import',
    orderIndex: 2,
    fireflyId: '6',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 5,
  );

  final rule = Rule(
    id: 'row-4',
    title: 'Tag groceries',
    description: 'Matches the supermarket',
    ruleGroupId: '6',
    trigger: 'description',
    scope: 'all',
    triggersJson: '[{"value":"TESCO"}]',
    actionsJson: '[{"type":"set_tag","value":"groceries"}]',
    strict: true,
    orderIndex: 1,
    fireflyId: '9',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 6,
  );

  final budget = Budget(
    id: 'row-5',
    name: 'Groceries',
    notes: 'Weekly shop',
    currencyCode: 'USD',
    currencyId: '1',
    autoBudgetType: 'rollover',
    orderIndex: 3,
    fireflyId: '2',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 7,
  );

  final account = Account(
    id: 'row-6',
    name: 'Checking',
    type: 'asset',
    currencyCode: 'USD',
    currencyId: '1',
    accountRole: 'defaultAsset',
    openingBalance: '1500',
    openingBalanceDate: seenAt,
    iban: 'GB33BUKB20201555555555',
    bic: 'BUKBGB22',
    accountNumber: '55555555',
    virtualBalance: '0',
    notes: 'Main account',
    orderIndex: 0,
    fireflyId: '21',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 8,
  );

  // `start` omits the day because the 1st is `DateTime.utc`'s default.
  final budgetLimit = BudgetLimit(
    id: 'row-7',
    budgetId: '2',
    start: DateTime.utc(2026, 10),
    end: DateTime.utc(2026, 10, 31),
    amount: '400',
    currencyCode: 'USD',
    currencyId: '1',
    notes: 'October',
    fireflyId: '31',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 9,
  );

  final piggyBank = PiggyBank(
    id: 'row-8',
    name: 'Holiday fund',
    accountId: '21',
    targetAmount: '2000',
    currentAmount: '340',
    startDate: seenAt,
    // Plain `DateTime.utc(2027)` is 1 January 2027 — both month and day are
    // the constructor defaults.
    targetDate: DateTime.utc(2027),
    currencyCode: 'USD',
    currencyId: '1',
    notes: 'Summer',
    orderIndex: 4,
    fireflyId: '15',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 10,
  );

  final bill = Bill(
    id: 'row-9',
    name: 'Rent',
    amount: '1200',
    currencyCode: 'USD',
    currencyId: '1',
    billDirection: 'withdrawal',
    skip: 1,
    payDates: '["2026-11-01T00:00:00Z","2026-12-01T00:00:00Z"]',
    remainingAmount: '600',
    // Day defaults to the 1st, so this is 1 November 2026.
    nextExpectedMatch: DateTime.utc(2026, 11),
    notes: 'Standing order',
    autoBudgetType: 'none',
    fireflyId: '3',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 11,
  );

  final subscription = Subscription(
    id: 'row-10',
    title: 'Broadband',
    amount: '45',
    currencyCode: 'USD',
    currencyId: '1',
    transactionJournalId: '77',
    nextDate: DateTime.utc(2026, 11, 5),
    endDate: DateTime.utc(2027, 11, 5),
    periods: '[{"period":"2026-11","amount":"45"}]',
    method: 'cc',
    notes: '12 month term',
    fireflyId: '18',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 12,
  );

  final recurrence = Recurrence(
    id: 'row-11',
    title: 'Salary',
    description: 'Monthly pay',
    recurUntil: DateTime.utc(2027, 12, 31),
    nrOfRepetitions: 12,
    transactionsJson: '[{"transaction_journal_id":"9","amount":"3000"}]',
    fireflyId: '22',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 13,
  );

  final attachment = Attachment(
    id: 'row-12',
    filename: 'receipt.jpg',
    notes: 'October shop',
    md5: 'd41d8cd98f00b204e9800998ecf8427e',
    size: 204812,
    mimeType: 'image/jpeg',
    downloadUrl: 'https://demo.firefly.org/api/v1/attachments/5/download',
    localPath: '/data/user/0/app/staged/receipt.jpg',
    fireflyId: '5',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 14,
  );

  final transaction = Transaction(
    id: 'row-13',
    journalId: '71',
    type: 'withdrawal',
    description: 'Tesco',
    date: seenAt,
    amount: '54.20',
    currencyCode: 'USD',
    currencyId: '1',
    sourceAccountId: '21',
    sourceName: 'Checking',
    destName: 'Tesco',
    categoryId: '1',
    categoryName: 'Groceries',
    budgetId: '2',
    budgetName: 'Groceries',
    billId: '3',
    billName: 'Rent',
    tagsJson: '["groceries","weekly"]',
    notes: 'Big shop',
    reconciled: true,
    foreignAmount: '49.80',
    foreignCurrencyCode: 'EUR',
    fireflyId: '71',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 15,
  );

  final category = Category(
    id: 'row-14',
    name: 'Groceries',
    notes: 'Food and household',
    fireflyId: '1',
    updatedAt: writtenAt,
    remoteUpdatedAt: remoteAt,
    seq: 16,
  );

  // A record rather than a wrapper class. The case is a flat data bag with no
  // behaviour, and a record keeps it free of a constructor — which this
  // project's lint configuration flags for carrying a redundant type name.
  final cases = <_Case>[
    (
      label: 'Currency',
      table: 'currencies',
      sample: currency,
      row: currency.toRow(),
      parse: Currency.fromRow,
    ),
    (
      label: 'Tag',
      table: 'tags',
      sample: tag,
      row: tag.toRow(),
      parse: Tag.fromRow,
    ),
    (
      label: 'RuleGroup',
      table: 'rule_groups',
      sample: ruleGroup,
      row: ruleGroup.toRow(),
      parse: RuleGroup.fromRow,
    ),
    (
      label: 'Rule',
      table: 'rules',
      sample: rule,
      row: rule.toRow(),
      parse: Rule.fromRow,
    ),
    (
      label: 'Budget',
      table: 'budgets',
      sample: budget,
      row: budget.toRow(),
      parse: Budget.fromRow,
    ),
    (
      label: 'Account',
      table: 'accounts',
      sample: account,
      row: account.toRow(),
      parse: Account.fromRow,
    ),
    (
      label: 'BudgetLimit',
      table: 'budget_limits',
      sample: budgetLimit,
      row: budgetLimit.toRow(),
      parse: BudgetLimit.fromRow,
    ),
    (
      label: 'PiggyBank',
      table: 'piggy_banks',
      sample: piggyBank,
      row: piggyBank.toRow(),
      parse: PiggyBank.fromRow,
    ),
    (
      label: 'Bill',
      table: 'bills',
      sample: bill,
      row: bill.toRow(),
      parse: Bill.fromRow,
    ),
    (
      label: 'Subscription',
      table: 'subscriptions',
      sample: subscription,
      row: subscription.toRow(),
      parse: Subscription.fromRow,
    ),
    (
      label: 'Recurrence',
      table: 'recurrences',
      sample: recurrence,
      row: recurrence.toRow(),
      parse: Recurrence.fromRow,
    ),
    (
      label: 'Attachment',
      table: 'attachments',
      sample: attachment,
      row: attachment.toRow(),
      parse: Attachment.fromRow,
    ),
    (
      label: 'Transaction',
      table: 'transactions',
      sample: transaction,
      row: transaction.toRow(),
      parse: Transaction.fromRow,
    ),
    (
      label: 'Category',
      table: 'categories',
      sample: category,
      row: category.toRow(),
      parse: Category.fromRow,
    ),
  ];

  for (final testCase in cases) {
    // One test per entity covers both halves of the contract: the INSERT
    // succeeding proves `toRow` emits only columns the table declares (SQLite
    // rejects anything else outright), and the parsed model equaling the
    // original proves the read side agrees. A second, insert-only test would
    // only re-state the first assertion while fighting for the same primary
    // key on the shared database.
    test('${testCase.label} row survives a real SQLite round trip', () async {
      await db.insert(testCase.table, testCase.row);
      final rows = await db.query(
        testCase.table,
        where: 'id = ?',
        whereArgs: <Object?>[testCase.row['id']! as String],
      );

      expect(rows, hasLength(1));
      expect(testCase.parse(rows.single), testCase.sample);
    });
  }

  test(
    'every business table accepts a row with only required fields',
    () async {
      // A minimal row proves the NOT NULL columns match the model's required
      // parameters; a mismatch here is what a pull of a sparse resource hits.
      await db.insert('transactions', <String, Object?>{
        'id': 'minimal',
        'type': 'withdrawal',
        'description': 'Coffee',
        'date': '2026-10-13T09:30:00.000Z',
        'amount': '3.50',
        'updated_at': writtenAt.millisecondsSinceEpoch,
        'sync_status': 'pending',
        'seq': 1,
      });
      final rows = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: <Object?>['minimal'],
      );

      expect(Transaction.fromRow(rows.single).description, 'Coffee');
    },
  );
}

/// One entity's persistence contract: the table it maps to, the sample that is
/// persisted, that sample's row, and the parser that must rebuild it.
///
/// The row is captured alongside the model rather than derived from it inside
/// the loop, because the entity types share no interface offering `toRow` —
/// deriving it would force a `dynamic` dispatch that the project lints ban.
///
/// * `label` is the human-readable entity name used in the test titles.
/// * `table` is the SQLite table the row must be insertable into.
/// * `sample` is the instance persisted and then re-parsed.
/// * `row` is the row produced by that sample's `toRow`.
/// * `parse` is the entity's `fromRow` factory.
typedef _Case = ({
  String label,
  String table,
  Object sample,
  Map<String, Object?> row,
  Object Function(Map<String, Object?>) parse,
});
