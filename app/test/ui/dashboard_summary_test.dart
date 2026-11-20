import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:firefly_mobile/ui/models/dashboard_summary.dart';

import 'package:flutter_test/flutter_test.dart';

/// Deterministic clock for every case: mid-July 2026 local time.
final DateTime kNow = DateTime(2026, 7, 15, 12);

Transaction _tx({
  required String id,
  required String type,
  required String amount,
  required DateTime date,
  String? currencyCode = 'EUR',
  String? budgetId,
}) =>
    Transaction(
      id: id,
      type: type,
      description: 'tx-$id',
      date: date,
      amount: amount,
      updatedAt: kNow,
      seq: 0,
      currencyCode: currencyCode,
      budgetId: budgetId,
    );

Budget _budget({required String id, bool active = true}) => Budget(
      id: id,
      name: 'budget-$id',
      updatedAt: kNow,
      seq: 0,
      active: active,
    );

BudgetLimit _limit({
  required String budgetId,
  required double amount,
  DateTime? start,
  DateTime? end,
}) =>
    BudgetLimit(
      id: 'limit-$budgetId',
      budgetId: budgetId,
      start: start ?? DateTime(2026, 7),
      end: end ?? DateTime(2026, 7, 31, 23, 59, 59),
      amount: amount.toString(),
      updatedAt: kNow,
      seq: 0,
    );

Bill _bill({
  required String id,
  required String name,
  DateTime? next,
  bool active = true,
}) =>
    Bill(
      id: id,
      name: name,
      amount: '10',
      updatedAt: kNow,
      seq: 0,
      active: active,
      nextExpectedMatch: next,
    );

Account _account({
  required String id,
  required String type,
  bool active = true,
}) =>
    Account(
      id: id,
      name: 'acct-$id',
      type: type,
      updatedAt: kNow,
      seq: 0,
      active: active,
    );

DashboardSummary _build({
  List<Transaction> transactions = const [],
  List<Budget> budgets = const [],
  List<BudgetLimit> budgetLimits = const [],
  List<Bill> bills = const [],
  List<Account> accounts = const [],
}) =>
    buildDashboardSummary(
      transactions: transactions,
      budgets: budgets,
      budgetLimits: budgetLimits,
      bills: bills,
      accounts: accounts,
      now: kNow,
    );

void main() {
  test('empty inputs produce an all-zero summary with default currency', () {
    final s = _build();
    expect(s.month.income, 0);
    expect(s.month.spent, 0);
    expect(s.month.net, 0);
    expect(s.month.currencyCode, 'EUR'); // kDefaultCurrencyCode fallback
    expect(s.budgets, isEmpty);
    expect(s.upcomingBills, isEmpty);
    expect(s.assetAccounts, isEmpty);
    expect(s.netWorth, 0);
    // No transactions → only the viewed (current) month is offered.
    expect(s.availableMonths, [DateTime(2026, 7)]);
    // Series is always daysInMonth + 1 points, all zero when empty.
    expect(s.netSeries.length, 32); // July has 31 days
    expect(s.netSeries.every((v) => v == 0), isTrue);
  });

  test('income/spent/net only count the current calendar month', () {
    final s = _build(
      transactions: [
        // In-month: deposit 100 + withdrawal 40.
        _tx(
          id: 'in-dep',
          type: 'deposit',
          amount: '100',
          date: DateTime(2026, 7, 2),
        ),
        _tx(
          id: 'in-wd',
          type: 'withdrawal',
          amount: '40',
          date: DateTime(2026, 7, 10),
        ),
        // Out-of-month: must not count (June).
        _tx(
          id: 'old-dep',
          type: 'deposit',
          amount: '999',
          date: DateTime(2026, 6, 30),
        ),
        // Transfer: never counts as income/spent.
        _tx(
          id: 'transfer',
          type: 'transfer',
          amount: '50',
          date: DateTime(2026, 7, 5),
        ),
      ],
    );
    expect(s.month.income, 100);
    expect(s.month.spent, 40);
    expect(s.month.net, 60);
    expect(s.month.currencyCode, 'EUR'); // first in-month tx's currency
  });

  test('unparseable amounts count as 0 instead of crashing', () {
    final s = _build(
      transactions: [
        _tx(
          id: 'bad',
          type: 'withdrawal',
          amount: 'not-a-number',
          date: DateTime(2026, 7),
        ),
      ],
    );
    expect(s.month.spent, 0);
  });

  test('netSeries is cumulative: eve point + one point per day', () {
    final s = _build(
      transactions: [
        // Before the month → lands on point 0 (the eve baseline).
        _tx(
          id: 'pre',
          type: 'deposit',
          amount: '10',
          date: DateTime(2026, 6, 30),
        ),
        // Day 2 deposit +20, day 10 withdrawal −5.
        _tx(
          id: 'd2',
          type: 'deposit',
          amount: '20',
          date: DateTime(2026, 7, 2),
        ),
        _tx(
          id: 'd10',
          type: 'withdrawal',
          amount: '5',
          date: DateTime(2026, 7, 10),
        ),
      ],
    );
    expect(s.netSeries.length, 32); // eve + 31 days
    expect(s.netSeries[0], 10); // eve baseline
    expect(s.netSeries[1], 10); // day 1: nothing yet
    expect(s.netSeries[2], 30); // day 2: +20
    expect(s.netSeries[9], 30); // days 3–9 flat
    expect(s.netSeries[10], 25); // day 10: −5
    expect(s.netSeries.last, 25); // stays through month end
  });

  test('availableMonths lists transaction months newest first, capped 24', () {
    final s = _build(
      transactions: [
        _tx(
          id: 'old',
          type: 'deposit',
          amount: '1',
          date: DateTime(2026, 5, 3),
        ),
        _tx(
          id: 'newer',
          type: 'deposit',
          amount: '1',
          date: DateTime(2026, 6, 3),
        ),
        _tx(
          id: 'viewed',
          type: 'deposit',
          amount: '1',
          date: DateTime(2026, 7, 3),
        ),
      ],
    );
    // Newest first; current month (July) already in the set from monthStart.
    expect(
      s.availableMonths.map((m) => '${m.year}-${m.month}').toList(),
      ['2026-7', '2026-6', '2026-5'],
    );
  });

  test('budget progress uses the current-period limit and spends', () {
    final s = _build(
      budgets: [_budget(id: 'b1'), _budget(id: 'b2', active: false)],
      budgetLimits: [
        _limit(budgetId: 'b1', amount: 100),
        // Period that ended in June — must NOT be picked up.
        _limit(
          budgetId: 'b1',
          amount: 500,
          start: DateTime(2026, 6),
          end: DateTime(2026, 6, 30),
        ),
      ],
      transactions: [
        // In period, withdrawal → counted.
        _tx(
          id: 's1',
          type: 'withdrawal',
          amount: '30',
          date: DateTime(2026, 7, 3),
          budgetId: 'b1',
        ),
        // Deposit tagged with budget → NOT spent.
        _tx(
          id: 's2',
          type: 'deposit',
          amount: '999',
          date: DateTime(2026, 7, 3),
          budgetId: 'b1',
        ),
        // Outside period end → NOT counted.
        _tx(
          id: 's3',
          type: 'withdrawal',
          amount: '40',
          date: DateTime(2026, 8),
          budgetId: 'b1',
        ),
      ],
    );
    // Inactive budget b2 skipped entirely (no period row either).
    expect(s.budgets.length, 1);
    final p = s.budgets.single;
    expect(p.budget.id, 'b1');
    expect(p.spent, 30);
    expect(p.limitAmount, 100);
    expect(p.fraction, closeTo(0.3, 1e-9));
    expect(p.over, isFalse);
  });

  test('over-budget fraction > 1 and over flag flips', () {
    final s = _build(
      budgets: [_budget(id: 'b1')],
      budgetLimits: [_limit(budgetId: 'b1', amount: 50)],
      transactions: [
        _tx(
          id: 'big',
          type: 'withdrawal',
          amount: '80',
          date: DateTime(2026, 7),
          budgetId: 'b1',
        ),
      ],
    );
    final p = s.budgets.single;
    expect(p.over, isTrue);
    expect(p.fraction, greaterThan(1));
  });

  test('budgets with no current-period limit are omitted from the list', () {
    final s = _build(
      budgets: [_budget(id: 'b1')],
      // budgetLimits defaults to [] — no limit → no progress row.
    );
    expect(s.budgets, isEmpty);
  });

  test('budget progress list is sorted most-over first, capped at 4', () {
    final s = _build(
      budgets: [
        for (var i = 1; i <= 5; i++) _budget(id: 'b$i'),
      ],
      budgetLimits: [
        _limit(budgetId: 'b1', amount: 100), // 0%
        _limit(budgetId: 'b2', amount: 100),
        _limit(budgetId: 'b3', amount: 100),
        _limit(budgetId: 'b4', amount: 100),
        _limit(budgetId: 'b5', amount: 100),
      ],
      transactions: [
        for (var i = 1; i <= 5; i++)
          _tx(
            id: 's$i',
            type: 'withdrawal',
            amount: '${i * 10}',
            date: DateTime(2026, 7, 2),
            budgetId: 'b$i',
          ),
      ],
    );
    expect(s.budgets.length, 4);
    expect(s.budgets.first.budget.id, 'b5'); // 50/100 highest
    expect(s.budgets.last.budget.id, 'b2'); // b1 (0%) dropped from tail
  });

  test('upcoming bills: active + within 45d horizon only, soonest first', () {
    final s = _build(
      bills: [
        _bill(
          id: 'far',
          name: 'far',
          next: kNow.add(const Duration(days: 50)),
        ),
        _bill(id: 'now', name: 'now', next: kNow),
        _bill(
          id: 'soon',
          name: 'soon',
          next: kNow.add(const Duration(days: 3)),
        ),
        _bill(
          id: 'past',
          name: 'past',
          next: kNow.subtract(const Duration(days: 1)),
        ),
        _bill(
          id: 'off',
          name: 'off',
          next: kNow.add(const Duration(days: 2)),
          active: false,
        ),
        _bill(
          id: 'null-next',
          name: 'null-next',
          // next omitted → null; inactive / past / far excluded below.
        ),
      ],
    );
    // far (>45d), past, inactive and null-next excluded.
    expect(s.upcomingBills.map((b) => b.id).toList(), ['now', 'soon']);
  });

  test('upcoming bills capped at 4', () {
    final s = _build(
      bills: [
        for (var i = 0; i <= 10; i++)
          _bill(
            id: 'b$i',
            name: 'b$i',
            next: kNow.add(Duration(days: i)),
          ),
      ],
    );
    expect(s.upcomingBills.length, 4);
    expect(s.upcomingBills.first.id, 'b0'); // soonest first
  });

  test('assetAccounts holds only active assets; netWorth adds liabilities', () {
    final s = _build(
      accounts: [
        _account(id: 'a1', type: 'asset'),
        _account(id: 'a2', type: 'asset'),
        _account(id: 'l1', type: 'liability'),
        _account(id: 'a3', type: 'asset', active: false),
      ],
    );
    // Cards row: active assets only (inactive + liability excluded).
    expect(s.assetAccounts.length, 2);
    expect(
      s.assetAccounts.map((b) => b.account.id).toList(),
      ['a1', 'a2'],
    );
    // Net worth: active asset + liability balances, no opening balance → 0.
    expect(s.netWorth, 0);
    expect(s.netWorthCurrencyCode, 'EUR'); // no currencyCodes set → default
  });

  test('month currency comes from the first in-month transaction', () {
    final s = _build(
      transactions: [
        _tx(
          id: 'pk',
          type: 'deposit',
          amount: '10',
          date: DateTime(2026, 7, 2),
          currencyCode: 'PKR',
        ),
        _tx(
          id: 'us',
          type: 'deposit',
          amount: '10',
          date: DateTime(2026, 7, 3),
          currencyCode: 'USD',
        ),
      ],
    );
    expect(s.month.currencyCode, 'PKR');
  });

  test('parseAmount handles valid, negative and garbage strings', () {
    expect(parseAmount('12.5'), 12.5);
    expect(parseAmount('-3'), -3);
    expect(parseAmount('abc'), 0);
    expect(parseAmount(''), 0);
  });
}
