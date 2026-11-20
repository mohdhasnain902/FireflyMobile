/// Pure aggregation of the data the Dashboard tab shows.
///
/// No Flutter imports and no providers — the screen watches the five list
/// providers and calls [buildDashboardSummary]; unit tests feed fixture
/// rows straight into the same function. Amounts follow the Firefly
/// convention: always positive, direction lives in
/// [Transaction.type] (`withdrawal` | `deposit` | `transfer`).
library;

import 'package:firefly_mobile/core/constants.dart'
    show kDefaultCurrencyCode;
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';

/// Income / spent / net for one calendar month.
class MonthTotals {
  /// Builds month totals from summed deposit/withdrawal amounts.
  const new({
    required this.income,
    required this.spent,
    this.currencyCode,
  });

  /// Sum of in-month deposit amounts.
  final double income;

  /// Sum of in-month withdrawal amounts.
  final double spent;

  /// Majority currency of the contributing transactions, else the app
  /// default — Firefly is multi-currency, but the dashboard cards show one.
  final String? currencyCode;

  /// income − spent (positive = surplus).
  double get net => income - spent;
}

/// One budget's spend against its current-period limit.
class BudgetProgress {
  /// Builds a progress row for one [Budget] + its current [BudgetLimit].
  const new({
    required this.budget,
    required this.spent,
    required this.limitAmount,
  });

  /// The budget this progress belongs to.
  final Budget budget;

  /// Sum of withdrawal amounts tagged with this budget inside the period.
  final double spent;

  /// Current [BudgetLimit].amount, or 0 when no period row exists.
  final double limitAmount;

  /// 0 when there is no limit; 1.0+ means over budget.
  double get fraction =>
      limitAmount <= 0 ? 0 : spent / limitAmount;

  /// True when spend exceeds the limit (limit must exist).
  bool get over => limitAmount > 0 && spent > limitAmount;
}

/// One account paired with its locally computed balance.
class AccountBalance {
  /// Builds an account/balance pair for the dashboard cards row.
  const new({required this.account, required this.balance});

  /// The account this balance belongs to.
  final Account account;

  /// Opening balance ± ledger movements touching this account.
  final double balance;
}

/// Everything the Dashboard screen renders, computed in one pass.
class DashboardSummary {
  /// Builds a full dashboard snapshot from the five provider lists.
  const new({
    required this.month,
    required this.monthStart,
    required this.netWorth,
    required this.netWorthCurrencyCode,
    required this.netSeries,
    required this.availableMonths,
    required this.assetAccounts,
    required this.budgets,
    required this.upcomingBills,
    this.spendingByMonth = const <double>[],
    this.spendingMonthLabels = const <String>[],
  });

  /// Income / spent / net for the viewed calendar month.
  final MonthTotals month;

  /// First instant of the viewed calendar month (what the dropdown selects).
  final DateTime monthStart;

  /// Sum of all active asset + liability account balances — the big card.
  final double netWorth;

  /// Currency shown with [netWorth] (asset majority, else app default).
  final String netWorthCurrencyCode;

  /// Daily cumulative net for the viewed month — days-in-month + 1 points,
  /// point 0 is the running total as of the month's eve, each next point
  /// adds that day's signed (deposit + / withdrawal − / transfer 0) sum.
  /// The dashboard feeds these straight into a fl_chart line.
  final List<double> netSeries;

  /// Distinct transaction months, newest first, always including the
  /// current month; feeds the month dropdown. Capped at 24.
  final List<DateTime> availableMonths;

  /// Active asset accounts with balances, for the horizontal cards row.
  final List<AccountBalance> assetAccounts;

  /// Active budgets that have a current-period limit, at most four.
  final List<BudgetProgress> budgets;

  /// Active bills with [Bill.nextExpectedMatch] inside the horizon, at
  /// most four, soonest first.
  final List<Bill> upcomingBills;
  /// Monthly spending totals (withdrawals) for the last up to 6 months,
  /// oldest first, for the dashboard spending line chart.
  final List<double> spendingByMonth;
  /// Labels matching [spendingByMonth] (e.g. '2026-10').
  final List<String> spendingMonthLabels;
}

/// How many days ahead the "upcoming bills" card looks.
const int kDashboardBillHorizonDays = 45;

/// Parses a Firefly amount string; unparseable values count as zero
/// rather than poisoning the whole summary.
double parseAmount(String raw) => double.tryParse(raw) ?? 0;

/// Signed flow of one journal leg: deposits in, withdrawals out,
/// transfers net-zero (the per-account balance path handles the legs).
double signedAmount(Transaction tx) {
  final amount = parseAmount(tx.amount);
  switch (tx.type) {
    case 'deposit':
      return amount;
    case 'withdrawal':
      return -amount;
    default:
      return 0;
  }
}

/// One account's balance: opening balance ± every ledger leg that
/// references it as source (−) or destination (+).
///
/// Transactions store Firefly wire ids in [Transaction.sourceAccountId] /
/// [Transaction.destAccountId], so a leg matches when either equals the
/// account's [Account.fireflyId] or its local id (demo rows may only have
/// the local one).
///
/// Multi-currency journals carry the source amount in [Transaction.amount] /
/// [Transaction.currencyCode] and the destination amount in
/// [Transaction.foreignAmount] / [Transaction.foreignCurrencyCode]. Each leg
/// must therefore use the amount denominated in the account's currency, not
/// blindly the primary amount (which would, for example, add PKR to a USD
/// account).
double accountBalance(Account account, List<Transaction> transactions) {
  var balance = parseAmount(account.openingBalance ?? '0');
  final ids = <String?>{account.fireflyId, account.id}..remove(null);
  for (final tx in transactions) {
    if (ids.contains(tx.sourceAccountId)) {
      balance -= _amountForAccount(
        tx: tx,
        accountCurrency: account.currencyCode,
        isSource: true,
      );
    }
    if (ids.contains(tx.destAccountId)) {
      balance += _amountForAccount(
        tx: tx,
        accountCurrency: account.currencyCode,
        isSource: false,
      );
    }
  }
  return balance;
}

/// Amount of [tx] expressed in [accountCurrency] for one leg.
///
/// Prefers the primary or foreign amount whose currency matches the account.
/// When the account currency is unknown, falls back to the conventional side
/// (primary for the source, foreign for the destination when present) so
/// single-currency journals and legacy rows keep their previous behaviour.
double _amountForAccount({
  required Transaction tx,
  required String? accountCurrency,
  required bool isSource,
}) {
  final primary = parseAmount(tx.amount);
  final foreignRaw = tx.foreignAmount;
  final foreign =
      foreignRaw == null || foreignRaw.isEmpty ? null : parseAmount(foreignRaw);

  if (accountCurrency != null) {
    if (tx.currencyCode == accountCurrency) return primary;
    if (tx.foreignCurrencyCode == accountCurrency && foreign != null) {
      return foreign;
    }
  }

  if (isSource) return primary;
  return foreign ?? primary;
}

/// Builds the [DashboardSummary] from raw list-provider payloads.
///
/// [now] is injectable so month-window and bill-horizon tests are
/// deterministic; production passes none and gets [DateTime.now].
///
/// [month] selects which calendar month the totals / net series / dropdown
/// highlight; null (production) means the month containing [now].
/// Budget limits and bill horizon always answer against [now] — they are
/// "current period" concepts, not "viewed month".
DashboardSummary buildDashboardSummary({
  required List<Transaction> transactions,
  required List<Budget> budgets,
  required List<BudgetLimit> budgetLimits,
  required List<Bill> bills,
  required List<Account> accounts,
  DateTime? now,
  DateTime? month,
}) {
  final clock = now ?? DateTime.now();
  // Whichever month the dropdown points at; day defaults to 1.
  final viewed = month ?? clock;
  final monthStart = DateTime(viewed.year, viewed.month);
  final nextMonthStart = DateTime(viewed.year, viewed.month + 1);

  var income = 0.0;
  var spent = 0.0;
  String? currency;
  for (final tx in transactions) {
    // Transactions store UTC instants; compare as-is against the local
    // month bounds — off-by-hours at the edge is acceptable for a summary.
    if (tx.date.isBefore(monthStart) || !tx.date.isBefore(nextMonthStart)) {
      continue;
    }
    currency ??= tx.currencyCode;
    final amount = parseAmount(tx.amount);
    switch (tx.type) {
      case 'withdrawal':
        spent += amount;
      case 'deposit':
        income += amount;
      // Transfers move money between own accounts — not income/spent.
      default:
        break;
    }
  }

  // Daily cumulative net for the viewed month: point 0 is everything
  // before the month, then one point per day. Feeds the sparkline.
  var running = 0.0;
  for (final tx in transactions) {
    if (tx.date.isBefore(monthStart)) {
      running += signedAmount(tx);
    }
  }
  final daysInMonth =
      DateTime(viewed.year, viewed.month + 1).difference(monthStart).inDays;
  final series = <double>[running];
  for (var day = 1; day <= daysInMonth; day++) {
    final dayStart = DateTime(viewed.year, viewed.month, day);
    final dayEnd = DateTime(viewed.year, viewed.month, day + 1);
    for (final tx in transactions) {
      if (!tx.date.isBefore(dayStart) && tx.date.isBefore(dayEnd)) {
        running += signedAmount(tx);
      }
    }
    series.add(running);
  }

  // Months that have any transaction, newest first; the current month is
  // always offered even when empty so the dropdown never collapses.
  final monthSet = <DateTime>{monthStart};
  for (final tx in transactions) {
    monthSet.add(DateTime(tx.date.year, tx.date.month));
  }
  final months = monthSet.toList()
    ..sort((a, b) => b.compareTo(a));

  // Budget progress: active budgets that have a period limit covering now.
  final progress = <BudgetProgress>[];
  for (final budget in budgets) {
    if (!budget.active) continue;
    BudgetLimit? period;
    for (final limit in budgetLimits) {
      if (limit.budgetId != budget.id) continue;
      if (!limit.start.isAfter(clock) && !limit.end.isBefore(clock)) {
        period = limit;
        break;
      }
    }
    if (period == null) continue;
    final periodLimit = parseAmount(period.amount);
    var periodSpent = 0.0;
    for (final tx in transactions) {
      if (tx.budgetId != budget.id || tx.type != 'withdrawal') continue;
      if (tx.date.isBefore(period.start) || tx.date.isAfter(period.end)) {
        continue;
      }
      periodSpent += parseAmount(tx.amount);
    }
    progress.add(
      BudgetProgress(
        budget: budget,
        spent: periodSpent,
        limitAmount: periodLimit,
      ),
    );
  }
  progress.sort((a, b) => b.fraction.compareTo(a.fraction));

  // Upcoming bills: active, next match within the horizon, soonest first.
  final horizon = clock.add(const Duration(days: kDashboardBillHorizonDays));
  final upcoming = <Bill>[
    for (final bill in bills)
      if (bill.active &&
          bill.nextExpectedMatch != null &&
          !bill.nextExpectedMatch!.isBefore(clock) &&
          !bill.nextExpectedMatch!.isAfter(horizon))
        bill,
  ]..sort(
      (a, b) => a.nextExpectedMatch!.compareTo(b.nextExpectedMatch!),
    );

  // Per-account balances for the horizontal cards row (active assets).
  final balances = <AccountBalance>[
    for (final account in accounts)
      if (account.active && account.type == 'asset')
        AccountBalance(
          account: account,
          balance: accountBalance(account, transactions),
        ),
  ];

  // Net worth = every active asset + liability balance. Revenue/expense
  // accounts are income-statement buckets, not worth — excluded. Majority
  // currency of asset accounts labels the card.
  var netWorth = 0.0;
  final currencyCounts = <String, int>{};
  for (final account in accounts) {
    if (!account.active) continue;
    if (account.type != 'asset' && account.type != 'liability') continue;
    netWorth += accountBalance(account, transactions);
    if (account.type == 'asset' && account.currencyCode != null) {
      currencyCounts[account.currencyCode!] =
          (currencyCounts[account.currencyCode!] ?? 0) + 1;
    }
  }
  final netWorthCurrency = currencyCounts.isEmpty
      ? kDefaultCurrencyCode
      : (currencyCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key;

  // Monthly spending (withdrawals) for the dashboard line chart: last up to
  // 6 months, oldest first.
  final spendingMap = <String, double>{};
  for (final tx in transactions) {
    if (tx.type != 'withdrawal') continue;
    final key = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
    spendingMap[key] = (spendingMap[key] ?? 0) + parseAmount(tx.amount);
  }
  final spendingKeys = spendingMap.keys.toList()..sort();
  final lastKeys = spendingKeys.length > 6
      ? spendingKeys.sublist(spendingKeys.length - 6)
      : spendingKeys;
  final spendingByMonth = <double>[for (final k in lastKeys) spendingMap[k]!];
  final spendingLabels = <String>[...lastKeys];

  return DashboardSummary(
    month: MonthTotals(
      income: income,
      spent: spent,
      currencyCode: currency ?? kDefaultCurrencyCode,
    ),
    monthStart: monthStart,
    netWorth: netWorth,
    netWorthCurrencyCode: netWorthCurrency,
    netSeries: series,
    availableMonths: months.take(24).toList(growable: false),
    assetAccounts: balances,
    budgets: progress.take(4).toList(growable: false),
    upcomingBills: upcoming.take(4).toList(growable: false),
    spendingByMonth: spendingByMonth,
    spendingMonthLabels: spendingLabels,
  );
}
