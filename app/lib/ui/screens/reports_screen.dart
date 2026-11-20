/// Reports screen: period-based financial report inspired by Firefly III's
/// default report (income/expense summary, trends, categories, budgets,
/// accounts, and bills).
library;

import 'dart:math' as math;

import 'package:firefly_mobile/core/currency/exchange_rates.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/utils/currency_format.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/budget.dart';
import 'package:firefly_mobile/domain/entities/budget_limit.dart';
import 'package:firefly_mobile/domain/entities/category.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:firefly_mobile/ui/models/dashboard_summary.dart'
    show accountBalance, parseAmount;
import 'package:firefly_mobile/ui/theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Reports tab.
class ReportsScreen extends ConsumerStatefulWidget {
  /// Creates the reports screen.
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

enum _PeriodPreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last3('Last 3 months'),
  last6('Last 6 months'),
  last12('Last 12 months'),
  ytd('Year to date'),
  all('All time'),
  custom('Custom range');

  const _PeriodPreset(this.label);
  final String label;
}

class _DateRange {
  const _DateRange(this.start, this.end, this.label);
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  final String label;
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _PeriodPreset _preset = _PeriodPreset.thisMonth;
  DateTimeRange? _custom;
  Future<_ReportData>? _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  void _reload() {
    setState(() {
      _loadFuture = _load();
    });
  }

  _DateRange _resolveRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (_preset) {
      case _PeriodPreset.thisMonth:
        final start = DateTime(today.year, today.month);
        return _DateRange(start, DateTime(today.year, today.month + 1), 'This month');
      case _PeriodPreset.lastMonth:
        final start = DateTime(today.year, today.month - 1);
        return _DateRange(start, DateTime(today.year, today.month), 'Last month');
      case _PeriodPreset.last3:
        final start = DateTime(today.year, today.month - 2);
        return _DateRange(start, DateTime(today.year, today.month + 1), 'Last 3 months');
      case _PeriodPreset.last6:
        final start = DateTime(today.year, today.month - 5);
        return _DateRange(start, DateTime(today.year, today.month + 1), 'Last 6 months');
      case _PeriodPreset.last12:
        final start = DateTime(today.year, today.month - 11);
        return _DateRange(start, DateTime(today.year, today.month + 1), 'Last 12 months');
      case _PeriodPreset.ytd:
        final start = DateTime(today.year, 1, 1);
        return _DateRange(start, DateTime(today.year, today.month + 1), 'Year to date');
      case _PeriodPreset.all:
        return _DateRange(DateTime(1970), DateTime(today.year + 1), 'All time');
      case _PeriodPreset.custom:
        if (_custom != null) {
          final s = DateTime(_custom!.start.year, _custom!.start.month, _custom!.start.day);
          final e = DateTime(_custom!.end.year, _custom!.end.month, _custom!.end.day + 1);
          final fmt = DateFormat('yMMMd');
          return _DateRange(s, e, '${fmt.format(s)} – ${fmt.format(DateTime(e.year, e.month, e.day - 1))}');
        }
        final start = DateTime(today.year, today.month);
        return _DateRange(start, DateTime(today.year, today.month + 1), 'This month');
    }
  }

  Future<_ReportData> _load() async {
    final txRepo = await ref.watch(transactionRepositoryProvider.future);
    final accRepo = await ref.watch(accountRepositoryProvider.future);
    final budRepo = await ref.watch(budgetRepositoryProvider.future);
    final blRepo = await ref.watch(budgetLimitRepositoryProvider.future);
    final billRepo = await ref.watch(billRepositoryProvider.future);
    final catRepo = await ref.watch(categoryRepositoryProvider.future);
    final results = await Future.wait([
      txRepo.getAll(limit: 100000),
      accRepo.getAll(limit: 100000),
      budRepo.getAll(limit: 100000),
      blRepo.getAll(limit: 100000),
      billRepo.getAll(limit: 100000),
      catRepo.getAll(limit: 100000),
    ]);
    return _ReportData(
      transactions: results[0] as List<Transaction>,
      accounts: results[1] as List<Account>,
      budgets: results[2] as List<Budget>,
      budgetLimits: results[3] as List<BudgetLimit>,
      bills: results[4] as List<Bill>,
      categories: results[5] as List<Category>,
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = _resolveRange(DateTime.now());
    return FutureBuilder<_ReportData>(
      future: _loadFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Couldn’t load report.\n${snap.error}', textAlign: TextAlign.center));
        }
        final data = snap.data!;
        final report = _compute(data, range);
        final currencyCode = report.currency == '—' ? null : report.currency;
        final hasData = report.months.isNotEmpty ||
            report.expenseByCategory.isNotEmpty ||
            report.incomeByCategory.isNotEmpty ||
            report.budgetRows.isNotEmpty ||
            report.accountRows.isNotEmpty ||
            report.bills.isNotEmpty;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _PeriodPicker(
                preset: _preset,
                label: range.label,
                onPreset: (p) async {
                  if (p == _PeriodPreset.custom) {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: _custom ??
                          DateTimeRange(
                            start: DateTime(now.year, now.month, 1),
                            end: now,
                          ),
                    );
                    if (picked != null) setState(() { _custom = picked; _preset = p; });
                  } else {
                    setState(() => _preset = p);
                  }
                },
              ),
              const SizedBox(height: 12),
              _SummaryCards(
                report: report,
                display: ref.watch(currencyDisplayProvider).asData?.value,
              ),
              const SizedBox(height: 20),
              if (report.months.isNotEmpty) ...[
                const _SectionTitle('Income vs expenses'),
                const SizedBox(height: 8),
                _IncomeExpenseChart(report: report),
                const SizedBox(height: 20),
              ],
              if (report.expenseByCategory.isNotEmpty) ...[
                const _SectionTitle('Expenses by category'),
                const SizedBox(height: 8),
                _CategoryBreakdown(
                  entries: report.expenseByCategory,
                  total: report.expense,
                  color: FireflyPalette.negative,
                  currencyCode: currencyCode,
                ),
                const SizedBox(height: 20),
              ],
              if (report.incomeByCategory.isNotEmpty) ...[
                const _SectionTitle('Income by category'),
                const SizedBox(height: 8),
                _CategoryBreakdown(
                  entries: report.incomeByCategory,
                  total: report.income,
                  color: FireflyPalette.chartGreen,
                  currencyCode: currencyCode,
                ),
                const SizedBox(height: 20),
              ],
              if (report.budgetRows.isNotEmpty) ...[
                const _SectionTitle('Budgets'),
                const SizedBox(height: 8),
                _BudgetReport(rows: report.budgetRows, currencyCode: currencyCode),
                const SizedBox(height: 20),
              ],
              if (report.accountRows.isNotEmpty) ...[
                const _SectionTitle('Account balances'),
                const SizedBox(height: 8),
                _AccountBalances(rows: report.accountRows),
                const SizedBox(height: 20),
              ],
              if (report.bills.isNotEmpty) ...[
                const _SectionTitle('Bills & subscriptions'),
                const SizedBox(height: 8),
                _BillsList(bills: report.bills),
              ],
              if (!hasData)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'No data for this period.',
                      style: TextStyle(color: FireflyPalette.textMuted),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportData {
  _ReportData({
    required this.transactions,
    required this.accounts,
    required this.budgets,
    required this.budgetLimits,
    required this.bills,
    required this.categories,
  });
  final List<Transaction> transactions;
  final List<Account> accounts;
  final List<Budget> budgets;
  final List<BudgetLimit> budgetLimits;
  final List<Bill> bills;
  final List<Category> categories;
}

class _MonthPoint {
  _MonthPoint(this.key, this.label, this.income, this.expense);
  final String key; // YYYY-MM
  final String label;
  final double income;
  final double expense;
}

class _CatEntry {
  _CatEntry(this.name, this.amount);
  final String name;
  final double amount;
}

class _BudgetRow {
  _BudgetRow(this.name, this.spent, this.limit);
  final String name;
  final double spent;
  final double? limit; // null = no limit covering period
}

class _AccountRow {
  _AccountRow(this.name, this.type, this.balance, this.currencyCode);
  final String name;
  final String type;
  final double balance;
  final String? currencyCode;
}

class _ComputedReport {
  _ComputedReport({
    required this.income,
    required this.expense,
    required this.currency,
    required this.months,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.budgetRows,
    required this.accountRows,
    required this.bills,
  });
  final double income;
  final double expense;
  double get net => income - expense;
  final String currency;
  final List<_MonthPoint> months;
  final List<_CatEntry> expenseByCategory;
  final List<_CatEntry> incomeByCategory;
  final List<_BudgetRow> budgetRows;
  final List<_AccountRow> accountRows;
  final List<Bill> bills;
}

_ComputedReport _compute(_ReportData data, _DateRange range) {
  final inRange = <Transaction>[
    for (final t in data.transactions)
      if (!t.date.isBefore(range.start) && t.date.isBefore(range.end)) t,
  ];

  var income = 0.0;
  var expense = 0.0;
  final currencyCounts = <String, int>{};
  final monthMap = <String, _MonthAcc>{};
  final expCat = <String, double>{};
  final incCat = <String, double>{};
  final budSpent = <String, double>{};

  for (final t in inRange) {
    final amt = parseAmount(t.amount);
    if (t.currencyCode != null) {
      currencyCounts[t.currencyCode!] = (currencyCounts[t.currencyCode!] ?? 0) + 1;
    }
    final mk = '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
    final acc = monthMap.putIfAbsent(mk, () => _MonthAcc());
    if (t.type == 'deposit') {
      income += amt;
      acc.income += amt;
      final c = (t.categoryName == null || t.categoryName!.isEmpty) ? '(no category)' : t.categoryName!;
      incCat[c] = (incCat[c] ?? 0) + amt;
    } else if (t.type == 'withdrawal') {
      expense += amt;
      acc.expense += amt;
      final c = (t.categoryName == null || t.categoryName!.isEmpty) ? '(no category)' : t.categoryName!;
      expCat[c] = (expCat[c] ?? 0) + amt;
      if (t.budgetId != null) {
        budSpent[t.budgetId!] = (budSpent[t.budgetId!] ?? 0) + amt;
      }
    }
  }

  final months = _buildMonths(range, monthMap);

  List<_CatEntry> sortCats(Map<String, double> m) {
    final list = [for (final e in m.entries) _CatEntry(e.key, e.value)];
    list.sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  // Budgets: show active budgets with spending in period (and limit if any overlaps period)
  final budgetRows = <_BudgetRow>[];
  for (final b in data.budgets.where((b) => b.active)) {
    final spent = budSpent[b.id] ?? 0.0;
    // find a limit overlapping the range
    double? limit;
    for (final l in data.budgetLimits) {
      if (l.budgetId != b.id) continue;
      if (l.start.isBefore(range.end) && l.end.isAfter(range.start.subtract(const Duration(days: 1)))) {
        limit = (limit ?? 0) + parseAmount(l.amount);
      }
    }
    if (spent > 0 || limit != null) {
      budgetRows.add(_BudgetRow(b.name, spent, limit));
    }
  }
  budgetRows.sort((a, b) => b.spent.compareTo(a.spent));

  // Account balances (current, asset/liability) like default report summaries
  final accountRows = <_AccountRow>[];
  for (final a in data.accounts) {
    if (!a.active) continue;
    if (a.type != 'asset' && a.type != 'liability') continue;
    accountRows.add(_AccountRow(a.name, a.type, accountBalance(a, data.transactions), a.currencyCode));
  }
  accountRows.sort((a, b) => a.type == b.type ? a.name.compareTo(b.name) : a.type.compareTo(b.type));

  final activeBills = [for (final b in data.bills) if (b.active) b];

  final currency = currencyCounts.isEmpty
      ? '—'
      : (currencyCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;

  return _ComputedReport(
    income: income,
    expense: expense,
    currency: currency,
    months: months,
    expenseByCategory: sortCats(expCat),
    incomeByCategory: sortCats(incCat),
    budgetRows: budgetRows,
    accountRows: accountRows,
    bills: activeBills,
  );
}

class _MonthAcc {
  double income = 0;
  double expense = 0;
}

List<_MonthPoint> _buildMonths(_DateRange range, Map<String, _MonthAcc> map) {
  // For "all time", only emit months that have data; else emit continuous range.
  if (range.label == 'All time') {
    final keys = map.keys.toList()..sort();
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return [
      for (final k in keys)
        () {
          final parts = k.split('-');
          final m = int.parse(parts[1]);
          final acc = map[k]!;
          return _MonthPoint(k, '${names[m - 1]} ${parts[0].substring(2)}', acc.income, acc.expense);
        }()
    ];
  }
  final points = <_MonthPoint>[];
  var cur = DateTime(range.start.year, range.start.month);
  final endMonth = DateTime(range.end.year, range.end.month);
  const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  while (cur.isBefore(endMonth)) {
    final k = '${cur.year}-${cur.month.toString().padLeft(2, '0')}';
    final acc = map[k] ?? _MonthAcc();
    final spanYears = range.end.year - range.start.year;
    final label = spanYears > 1 || range.start.year != range.end.year - (range.end.month == 1 && range.end.day == 1 ? 1 : 0)
        ? '${names[cur.month - 1]} ${cur.year.toString().substring(2)}'
        : names[cur.month - 1];
    points.add(_MonthPoint(k, label, acc.income, acc.expense));
    cur = DateTime(cur.year, cur.month + 1);
  }
  // if range is within single month, still show that month
  if (points.isEmpty) {
    final cur2 = DateTime(range.start.year, range.start.month);
    final k = '${cur2.year}-${cur2.month.toString().padLeft(2, '0')}';
    final acc = map[k] ?? _MonthAcc();
    points.add(_MonthPoint(k, names[cur2.month - 1], acc.income, acc.expense));
  }
  return points;
}

// --------------------------------------------------------------------------- UI

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.preset, required this.label, required this.onPreset});
  final _PeriodPreset preset;
  final String label;
  final ValueChanged<_PeriodPreset> onPreset;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<_PeriodPreset>(
          initialValue: preset,
          onSelected: onPreset,
          color: FireflyPalette.surfaceElevated,
          itemBuilder: (context) => [
            for (final p in _PeriodPreset.values)
              PopupMenuItem(value: p, child: Text(p.label)),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FireflyPalette.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FireflyPalette.outline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.date_range, size: 16, color: FireflyPalette.primary),
              const SizedBox(width: 6),
              Text(preset.label, style: const TextStyle(color: FireflyPalette.textPrimary, fontWeight: FontWeight.w600)),
              const Icon(Icons.arrow_drop_down, color: FireflyPalette.textDim),
            ]),
          ),
        ),
        Text(label, style: const TextStyle(color: FireflyPalette.textDim, fontSize: 12)),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.report, required this.display});
  final _ComputedReport report;
  final CurrencyDisplaySettings? display;

  @override
  Widget build(BuildContext context) {
    final code = report.currency == '—' ? null : report.currency;
    Widget card(String title, double value, Color color, IconData icon) {
      final secondary = display?.formatSecondary(value, code);
      return Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                // Three cards share a 360dp phone width: a fixed-width label
                // overflows as soon as the card gets ~90dp (R23 sweep:
                // "RenderFlex overflowed by up to 53 px on the right").
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FireflyPalette.textDim,
                      fontSize: 12,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text(
                formatMoney(value, code),
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (secondary != null)
                Text(
                  secondary,
                  style: const TextStyle(
                    color: FireflyPalette.textDim,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      card('Income', report.income, FireflyPalette.chartGreen, Icons.south_west),
      const SizedBox(width: 8),
      card('Expenses', report.expense, FireflyPalette.negative, Icons.north_east),
      const SizedBox(width: 8),
      card(
        'Net',
        report.net,
        report.net >= 0 ? FireflyPalette.primary : FireflyPalette.negative,
        Icons.balance,
      ),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(color: FireflyPalette.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
      );
}

class _IncomeExpenseChart extends StatelessWidget {
  const _IncomeExpenseChart({required this.report});
  final _ComputedReport report;

  @override
  Widget build(BuildContext context) {
    final months = report.months;
    final maxY = [
      for (final m in months) math.max(m.income, m.expense),
    ].fold<double>(0, math.max);
    final top = maxY <= 0 ? 1.0 : maxY * 1.2;
    final interval = top / 4;
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < months.length; i++) {
      final m = months[i];
      groups.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: m.income, color: FireflyPalette.chartGreen, width: months.length > 12 ? 5 : 8, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
        BarChartRodData(toY: m.expense, color: FireflyPalette.negative, width: months.length > 12 ? 5 : 8, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
      ]));
    }
    final step = months.length <= 6 ? 1 : (months.length / 6).ceil();

    String fmt(double v) {
      final a = v.abs();
      if (a >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
      if (a >= 1000) return '${(v / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}k';
      return v.toStringAsFixed(0);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
        child: Column(children: [
          SizedBox(
            height: 220,
            child: BarChart(BarChartData(
              maxY: top,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => const FlLine(color: FireflyPalette.outline, strokeWidth: 1, dashArray: [3, 3]),
              ),
              borderData: FlBorderData(show: false),
              barGroups: groups,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => FireflyPalette.surfaceElevated,
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final m = months[group.x.toInt()];
                    final label = rodIndex == 0 ? 'Income' : 'Expenses';
                    final val = rodIndex == 0 ? m.income : m.expense;
                    return BarTooltipItem('${m.label}\n$label: ${formatMoney(val, report.currency == '—' ? null : report.currency)}',
                        const TextStyle(color: FireflyPalette.textPrimary, fontSize: 12));
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 40, interval: interval,
                  getTitlesWidget: (v, _) => Text(fmt(v), style: const TextStyle(color: FireflyPalette.textDim, fontSize: 10)),
                )),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= months.length) return const SizedBox.shrink();
                    if (i % step != 0 && i != months.length - 1) return const SizedBox.shrink();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(months[i].label, style: const TextStyle(color: FireflyPalette.textDim, fontSize: 10)));
                  },
                )),
              ),
            )),
          ),
          const SizedBox(height: 8),
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _LegendDot(color: FireflyPalette.chartGreen, label: 'Income'),
            SizedBox(width: 16),
            _LegendDot(color: FireflyPalette.negative, label: 'Expenses'),
          ]),
        ]),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: FireflyPalette.textDim, fontSize: 11)),
      ]);
}

const _pieColors = <Color>[
  Color(0xFF5DA5DA), Color(0xFFF15854), Color(0xFF60BD68), Color(0xFFFAA43A),
  Color(0xFFB276B2), Color(0xFFF17CB0), Color(0xFFB2912F), Color(0xFF4D4D4D),
  Color(0xFF8DD3C7), Color(0xFFBEBADA),
];

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.entries,
    required this.total,
    required this.color,
    required this.currencyCode,
  });
  final List<_CatEntry> entries;
  final double total;
  final Color color;
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    final top = entries.take(8).toList();
    final rest = entries.skip(8).fold<double>(0, (s, e) => s + e.amount);
    final show = [...top, if (rest > 0) _CatEntry('Other', rest)];
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < show.length; i++) {
      final e = show[i];
      final pct = total <= 0 ? 0.0 : e.amount / total * 100;
      sections.add(PieChartSectionData(
        value: e.amount <= 0 ? 0.0001 : e.amount,
        color: _pieColors[i % _pieColors.length],
        radius: 44,
        title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          SizedBox(
            height: 170,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: PieChart(PieChartData(
                  sections: sections,
                  sectionsSpace: 2,
                  centerSpaceRadius: 26,
                )),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: _CatLegend(entries: show, total: total),
                ),
              ),
            ]),
          ),
          const Divider(height: 20),
          for (final e in top)
            _AmountRow(
              name: e.name,
              amount: e.amount,
              total: total,
              color: color,
              currencyCode: currencyCode,
            ),
          if (rest > 0)
            _AmountRow(
              name: 'Other',
              amount: rest,
              total: total,
              color: color,
              currencyCode: currencyCode,
            ),
        ]),
      ),
    );
  }
}

class _CatLegend extends StatelessWidget {
  const _CatLegend({required this.entries, required this.total});
  final List<_CatEntry> entries;
  final double total;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++)
          () {
            final e = entries[i];
            final pct = total <= 0 ? 0.0 : e.amount / total * 100;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  color: _pieColors[i % _pieColors.length],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FireflyPalette.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: FireflyPalette.textDim,
                    fontSize: 11,
                  ),
                ),
              ]),
            );
          }(),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.name,
    required this.amount,
    required this.total,
    required this.color,
    required this.currencyCode,
  });
  final String name;
  final double amount;
  final double total;
  final Color color;
  final String? currencyCode;
  @override
  Widget build(BuildContext context) {
    final frac = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                color: FireflyPalette.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            formatMoney(amount, currencyCode),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 4,
            backgroundColor: FireflyPalette.outline,
            valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.8)),
          ),
        ),
      ]),
    );
  }
}

class _BudgetReport extends StatelessWidget {
  const _BudgetReport({required this.rows, required this.currencyCode});
  final List<_BudgetRow> rows;
  final String? currencyCode;
  @override
  Widget build(BuildContext context) {
    String m(double v) => formatMoney(v, currencyCode);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 16),
            () {
              final r = rows[i];
              final hasLimit = r.limit != null && r.limit! > 0;
              final frac = hasLimit ? (r.spent / r.limit!).clamp(0.0, 1.0) : 0.0;
              final over = hasLimit && r.spent > r.limit!;
              final barColor =
                  over ? FireflyPalette.negative : FireflyPalette.primary;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      r.name,
                      style: const TextStyle(
                        color: FireflyPalette.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    hasLimit ? '${m(r.spent)} / ${m(r.limit!)}' : m(r.spent),
                    style: TextStyle(
                      color: over
                          ? FireflyPalette.negative
                          : FireflyPalette.textDim,
                      fontSize: 12,
                    ),
                  ),
                ]),
                if (hasLimit) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 6,
                      backgroundColor: FireflyPalette.outline,
                      valueColor: AlwaysStoppedAnimation(barColor),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    over
                        ? 'Over by ${m(r.spent - r.limit!)}'
                        : 'Left ${m(r.limit! - r.spent)}',
                    style: TextStyle(
                      color: over
                          ? FireflyPalette.negative
                          : FireflyPalette.chartGreen,
                      fontSize: 11,
                    ),
                  ),
                ],
              ]);
            }(),
          ],
        ]),
      ),
    );
  }
}

class _AccountBalances extends StatelessWidget {
  const _AccountBalances({required this.rows});
  final List<_AccountRow> rows;
  @override
  Widget build(BuildContext context) {
    final assets = rows.where((r) => r.type == 'asset').toList();
    final liabilities = rows.where((r) => r.type == 'liability').toList();
    Widget section(String title, List<_AccountRow> list) {
      if (list.isEmpty) return const SizedBox.shrink();
      final total = list.fold<double>(0, (s, r) => s + r.balance);
      final totalCode = list.first.currencyCode;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: FireflyPalette.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatMoney(total, totalCode),
              style: const TextStyle(
                color: FireflyPalette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
        ),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  r.name,
                  style: const TextStyle(color: FireflyPalette.textPrimary),
                ),
              ),
              Text(
                formatMoney(r.balance, r.currencyCode),
                style: TextStyle(
                  color: r.balance >= 0
                      ? FireflyPalette.textPrimary
                      : FireflyPalette.negative,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ),
      ]);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          section('Asset accounts', assets),
          if (assets.isNotEmpty && liabilities.isNotEmpty)
            const Divider(height: 20),
          section('Liabilities', liabilities),
        ]),
      ),
    );
  }
}

class _BillsList extends StatelessWidget {
  const _BillsList({required this.bills});
  final List<Bill> bills;
  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yMMMd');
    final sorted = [...bills]..sort((a, b) => a.name.compareTo(b.name));
    const limit = 20;
    final shown = sorted.take(limit).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 14),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    shown[i].name,
                    style: const TextStyle(
                      color: FireflyPalette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (shown[i].nextExpectedMatch != null)
                    Text(
                      'Next: ${df.format(shown[i].nextExpectedMatch!)}',
                      style: const TextStyle(
                        color: FireflyPalette.textDim,
                        fontSize: 11,
                      ),
                    ),
                ]),
              ),
              Text(
                formatMoney(
                  parseAmount(shown[i].amount),
                  shown[i].currencyCode,
                ),
                style: const TextStyle(
                  color: FireflyPalette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ],
          if (sorted.length > limit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Showing $limit of ${sorted.length} bills',
                style: const TextStyle(
                  color: FireflyPalette.textDim,
                  fontSize: 11,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
