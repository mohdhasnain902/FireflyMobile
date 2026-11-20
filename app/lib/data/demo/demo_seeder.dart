import 'package:firefly_mobile/data/dao/business_daos.dart';
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:firefly_mobile/data/dao/entity_dao.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/attachment.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/currency.dart';
import 'package:firefly_mobile/domain/entities/piggy_bank.dart';
import 'package:firefly_mobile/domain/entities/recurrence.dart';
import 'package:firefly_mobile/domain/entities/recurrence_repetition.dart';
import 'package:firefly_mobile/domain/entities/rule.dart';
import 'package:firefly_mobile/domain/entities/rule_group.dart';
import 'package:firefly_mobile/domain/entities/subscription.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/domain/entities/tag.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart'
    as app_transaction;
import 'package:sqflite_common/sqlite_api.dart';

/// Demo-data seed/erase for the offline UI (P2 demo polish).
///
/// Every row uses a `demo-` primary-key prefix, `SyncStatus.synced`, `seq: 0`
/// and a null `fireflyId`. That combination is what keeps demo data out of
/// the push queue: the sync engine only replays rows with
/// `sync_status != 'synced'` and never pushes a null `fireflyId`.
///
/// [seedDemoData] writes every business table in one transaction so a crash
/// mid-seed cannot leave a half-populated DB. [eraseDemoData] deletes only
/// rows whose `id` starts with `demo-` (and the `recurrence_repetitions`
/// children of demo recurrences via [RecurrenceDao.hardDelete]). Both
/// operations run inside a single transaction on the caller's connection.
///
/// The seed/erase flag lives under [demoSeededMetaKey] in `device_meta`.
/// [ensureDemoSeeded] skips when the flag is set or any business table is
/// non-empty — a real synced DB must never be overwritten.
const String demoSeededMetaKey = 'demo_seeded';

/// Fixed epoch-ms stamped on every demo row so `updated_at` is stable in tests.
final DateTime _demoNow = DateTime.utc(2026, 1, 15, 12);

/// Inserts a full demo dataset into every business table.
///
/// All writes go through [EntityDao.upsert] (or [RecurrenceDao.upsert]) with
/// an explicit executor so the whole seed is one transaction. No op-log
/// entries are created — demo rows are born synced.
Future<void> seedDemoData(Database db) async {
  await db.transaction<void>((txn) async {
    final meta = DeviceMetaDao(db);
    // Idempotent: re-seeding overwrites demo rows (same primary keys) and
    // does not touch non-demo data.
    final currencies = _currencies();
    for (final e in currencies) {
      await CurrencyDao(txn).upsert(e);
    }
    final accounts = _accounts();
    for (final e in accounts) {
      await AccountDao(txn).upsert(e);
    }
    final categories = _categories();
    for (final e in categories) {
      await CategoryDao(txn).upsert(e);
    }
    final tags = _tags();
    for (final e in tags) {
      await TagDao(txn).upsert(e);
    }
    final budgets = _budgets();
    for (final e in budgets) {
      await BudgetDao(txn).upsert(e);
    }
    final budgetLimits = _budgetLimits();
    for (final e in budgetLimits) {
      await BudgetLimitDao(txn).upsert(e);
    }
    final bills = _bills();
    for (final e in bills) {
      await BillDao(txn).upsert(e);
    }
    final subscriptions = _subscriptions();
    for (final e in subscriptions) {
      await SubscriptionDao(txn).upsert(e);
    }
    final piggyBanks = _piggyBanks();
    for (final e in piggyBanks) {
      await PiggyBankDao(txn).upsert(e);
    }
    final ruleGroups = _ruleGroups();
    for (final e in ruleGroups) {
      await RuleGroupDao(txn).upsert(e);
    }
    final rules = _rules();
    for (final e in rules) {
      await RuleDao(txn).upsert(e);
    }
    final recurrences = _recurrences();
    for (final e in recurrences) {
      await RecurrenceDao(txn).upsert(e);
    }
    final attachments = _attachments();
    for (final e in attachments) {
      await AttachmentDao(txn).upsert(e);
    }
    final transactions = _transactions();
    for (final e in transactions) {
      await TransactionDao(txn).upsert(e);
    }
    await meta.setIn(txn, demoSeededMetaKey, '1');
  });
}

/// Deletes every `demo-` row from every business table (plus recurrence
/// children) in one transaction and clears the [demoSeededMetaKey] flag.
Future<void> eraseDemoData(Database db) async {
  await db.transaction<void>((txn) async {
    // Recurrences first: hardDelete cascades to recurrence_repetitions.
    final recurrenceDao = RecurrenceDao(txn);
    final recIds = await _demoIds(txn, 'recurrences');
    for (final id in recIds) {
      await recurrenceDao.hardDelete(id, txn);
    }
    // Clear the seeded flag on the same txn (DeviceMetaDao.remove takes the
    // outer Database, which would deadlock inside a transaction).
    await txn.delete(
      'device_meta',
      where: 'key = ?',
      whereArgs: [demoSeededMetaKey],
    );
    for (final table in _businessTables) {
      final ids = await _demoIds(txn, table);
      for (final id in ids) {
        await txn.delete(table, where: 'id = ?', whereArgs: [id]);
      }
    }
  });
}

/// Seeds only when the DB is empty (no business rows) and the demo-seeded
/// flag is unset. Returns true when a seed actually ran.
///
/// Called once from the home shell's first frame; the Settings "Load demo
/// data" tile calls [seedDemoData] directly.
Future<bool> ensureDemoSeeded(Database db) async {
  final meta = DeviceMetaDao(db);
  final flag = await meta.get(demoSeededMetaKey);
  if (flag == '1') return false;
  for (final table in _businessTables) {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL',
    );
    if ((rows.first['c']! as int) > 0) return false;
  }
  await seedDemoData(db);
  return true;
}

/// All fourteen business tables in FK-safe erase order (recurrences handled
/// separately by the caller because of their child table).
const List<String> _businessTables = [
  'transactions',
  'attachments',
  'rules',
  'rule_groups',
  'piggy_banks',
  'subscriptions',
  'bills',
  'budget_limits',
  'budgets',
  'tags',
  'categories',
  'accounts',
  'currencies',
];

Future<List<String>> _demoIds(DatabaseExecutor txn, String table) async {
  final rows = await txn.query(
    table,
    columns: ['id'],
    where: "id LIKE 'demo-%'",
  );
  return rows.map((r) => r['id']! as String).toList(growable: false);
}

// ---------------------------------------------------------------------------
// Fixture builders — deterministic, human-readable names so the demo looks
// like a real Firefly install on first open.
// ---------------------------------------------------------------------------

List<Currency> _currencies() => [
  Currency(
    id: 'demo-cur-usd',
    code: 'USD',
    name: 'US Dollar',
    symbol: r'$',
    rate: '1',
    isDefault: true,
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Currency(
    id: 'demo-cur-eur',
    code: 'EUR',
    name: 'Euro',
    symbol: '€',
    rate: '0.92',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Account> _accounts() => [
  Account(
    id: 'demo-acc-checking',
    name: 'Demo Checking',
    type: 'asset',
    accountRole: 'defaultAsset',
    openingBalance: '2500',
    openingBalanceDate: _demoNow,
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Account(
    id: 'demo-acc-savings',
    name: 'Demo Savings',
    type: 'asset',
    accountRole: 'savingAsset',
    openingBalance: '10000',
    openingBalanceDate: _demoNow,
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Account(
    id: 'demo-acc-groceries',
    name: 'Demo Groceries',
    type: 'expense',
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Account(
    id: 'demo-acc-salary',
    name: 'Demo Salary',
    type: 'revenue',
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Category> _categories() => [
  Category(
    id: 'demo-cat-food',
    name: 'Food',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Category(
    id: 'demo-cat-transport',
    name: 'Transport',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Category(
    id: 'demo-cat-housing',
    name: 'Housing',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Tag> _tags() => [
  Tag(
    id: 'demo-tag-demo',
    tag: 'demo',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Tag(
    id: 'demo-tag-recurring',
    tag: 'recurring',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Budget> _budgets() => [
  Budget(
    id: 'demo-budget-groceries',
    name: 'Groceries',
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Budget(
    id: 'demo-budget-transport',
    name: 'Transport',
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<BudgetLimit> _budgetLimits() => [
  BudgetLimit(
    id: 'demo-bl-groceries-jan',
    budgetId: 'demo-budget-groceries',
    start: DateTime.utc(2026),
    end: DateTime.utc(2026, 1, 31),
    amount: '400',
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  BudgetLimit(
    id: 'demo-bl-transport-jan',
    budgetId: 'demo-budget-transport',
    start: DateTime.utc(2026),
    end: DateTime.utc(2026, 1, 31),
    amount: '150',
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Bill> _bills() => [
  Bill(
    id: 'demo-bill-rent',
    name: 'Rent',
    amount: '1200',
    currencyCode: 'USD',
    nextExpectedMatch: DateTime.utc(2026, 2),
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  Bill(
    id: 'demo-bill-internet',
    name: 'Internet',
    amount: '60',
    currencyCode: 'USD',
    nextExpectedMatch: DateTime.utc(2026, 2, 5),
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Subscription> _subscriptions() => [
  Subscription(
    id: 'demo-sub-streaming',
    title: 'Streaming',
    amount: '15',
    currencyCode: 'USD',
    nextDate: DateTime.utc(2026, 2, 10),
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<PiggyBank> _piggyBanks() => [
  PiggyBank(
    id: 'demo-piggy-vacation',
    name: 'Vacation Fund',
    accountId: 'demo-acc-savings',
    targetAmount: '2000',
    currentAmount: '350',
    currencyCode: 'USD',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<RuleGroup> _ruleGroups() => [
  RuleGroup(
    id: 'demo-rg-classify',
    title: 'Auto-classify',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Rule> _rules() => [
  Rule(
    id: 'demo-rule-groceries',
    title: 'Tag groceries',
    ruleGroupId: 'demo-rg-classify',
    trigger: 'store',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Recurrence> _recurrences() => [
  Recurrence(
    id: 'demo-rec-salary',
    title: 'Monthly salary',
    type: 'monthly',
    firstDate: DateTime.utc(2026),
    repetitions: const [
      RecurrenceRepetition(
        recurrenceId: 'demo-rec-salary',
        ord: 0,
        repetitionType: 'dayOfMonth',
        repetitionMoment: '1',
      ),
    ],
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<Attachment> _attachments() => [
  Attachment(
    id: 'demo-att-receipt',
    filename: 'demo-grocery-receipt.txt',
    notes: 'Placeholder demo attachment',
    mimeType: 'text/plain',
    size: 32,
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
];

List<app_transaction.Transaction> _transactions() {
  final rows = <app_transaction.Transaction>[
  app_transaction.Transaction(
    id: 'demo-tx-groceries',
    type: 'withdrawal',
    description: 'Weekly groceries',
    date: DateTime.utc(2026, 1, 10),
    amount: '85.40',
    currencyCode: 'USD',
    sourceAccountId: 'demo-acc-checking',
    sourceName: 'Demo Checking',
    categoryId: 'demo-cat-food',
    categoryName: 'Food',
    budgetId: 'demo-budget-groceries',
    budgetName: 'Groceries',
    tagsJson: '["demo"]',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  app_transaction.Transaction(
    id: 'demo-tx-salary',
    type: 'deposit',
    description: 'Salary',
    date: DateTime.utc(2026),
    amount: '3500',
    currencyCode: 'USD',
    destAccountId: 'demo-acc-salary',
    destName: 'Demo Salary',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  app_transaction.Transaction(
    id: 'demo-tx-bus',
    type: 'withdrawal',
    description: 'Bus pass',
    date: DateTime.utc(2026, 1, 12),
    amount: '45',
    currencyCode: 'USD',
    sourceAccountId: 'demo-acc-checking',
    sourceName: 'Demo Checking',
    categoryId: 'demo-cat-transport',
    categoryName: 'Transport',
    budgetId: 'demo-budget-transport',
    budgetName: 'Transport',
    tagsJson: '["demo", "recurring"]',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  app_transaction.Transaction(
    id: 'demo-tx-rent',
    type: 'withdrawal',
    description: 'Rent',
    date: DateTime.utc(2026),
    amount: '1200',
    currencyCode: 'USD',
    sourceAccountId: 'demo-acc-checking',
    sourceName: 'Demo Checking',
    categoryId: 'demo-cat-housing',
    categoryName: 'Housing',
    billId: 'demo-bill-rent',
    billName: 'Rent',
    updatedAt: _demoNow,
    seq: 0,
    syncStatus: SyncStatus.synced,
  ),
  ];

  // Aug–Dec 2025 sample months so the Reports bar chart has history to
  // draw. Same five-row shape per month (salary, rent, two groceries,
  // bus), all born `demo-`/synced/seq 0 like every other seeded row.
  const months = <int>[8, 9, 10, 11, 12];
  for (final m in months) {
    rows
      ..add(
        app_transaction.Transaction(
          id: 'demo-tx-salary-2025-$m',
          type: 'deposit',
          description: 'Salary',
          date: DateTime.utc(2025, m),
          amount: '3500',
          currencyCode: 'USD',
          destAccountId: 'demo-acc-salary',
          destName: 'Demo Salary',
          updatedAt: _demoNow,
          seq: 0,
          syncStatus: SyncStatus.synced,
        ),
      )
      ..add(
        app_transaction.Transaction(
          id: 'demo-tx-rent-2025-$m',
          type: 'withdrawal',
          description: 'Rent',
          date: DateTime.utc(2025, m),
          amount: '1200',
          currencyCode: 'USD',
          sourceAccountId: 'demo-acc-checking',
          sourceName: 'Demo Checking',
          categoryId: 'demo-cat-housing',
          categoryName: 'Housing',
          billId: 'demo-bill-rent',
          billName: 'Rent',
          updatedAt: _demoNow,
          seq: 0,
          syncStatus: SyncStatus.synced,
        ),
      )
      ..add(
        app_transaction.Transaction(
          id: 'demo-tx-groceries-2025-$m-a',
          type: 'withdrawal',
          description: 'Weekly groceries',
          date: DateTime.utc(2025, m, 8),
          amount: '85.40',
          currencyCode: 'USD',
          sourceAccountId: 'demo-acc-checking',
          sourceName: 'Demo Checking',
          categoryId: 'demo-cat-food',
          categoryName: 'Food',
          budgetId: 'demo-budget-groceries',
          budgetName: 'Groceries',
          tagsJson: '["demo"]',
          updatedAt: _demoNow,
          seq: 0,
          syncStatus: SyncStatus.synced,
        ),
      )
      ..add(
        app_transaction.Transaction(
          id: 'demo-tx-groceries-2025-$m-b',
          type: 'withdrawal',
          description: 'Weekly groceries',
          date: DateTime.utc(2025, m, 22),
          amount: '92.15',
          currencyCode: 'USD',
          sourceAccountId: 'demo-acc-checking',
          sourceName: 'Demo Checking',
          categoryId: 'demo-cat-food',
          categoryName: 'Food',
          budgetId: 'demo-budget-groceries',
          budgetName: 'Groceries',
          tagsJson: '["demo"]',
          updatedAt: _demoNow,
          seq: 0,
          syncStatus: SyncStatus.synced,
        ),
      )
      ..add(
        app_transaction.Transaction(
          id: 'demo-tx-bus-2025-$m',
          type: 'withdrawal',
          description: 'Bus pass',
          date: DateTime.utc(2025, m, 12),
          amount: '45',
          currencyCode: 'USD',
          sourceAccountId: 'demo-acc-checking',
          sourceName: 'Demo Checking',
          categoryId: 'demo-cat-transport',
          categoryName: 'Transport',
          budgetId: 'demo-budget-transport',
          budgetName: 'Transport',
          tagsJson: '["demo", "recurring"]',
          updatedAt: _demoNow,
          seq: 0,
          syncStatus: SyncStatus.synced,
        ),
      );
  }
  return rows;
}
