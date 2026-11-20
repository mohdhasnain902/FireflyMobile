

import 'dart:math' as math;

import 'package:firefly_mobile/core/currency/exchange_rates.dart';
import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/core/utils/currency_format.dart';
import 'package:firefly_mobile/domain/entities/account.dart';
import 'package:firefly_mobile/domain/entities/bill.dart';
import 'package:firefly_mobile/domain/entities/sync_bookkeeping.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/models/dashboard_summary.dart';
import 'package:firefly_mobile/ui/models/entity_config.dart';
import 'package:firefly_mobile/ui/screens/services_screen.dart';
import 'package:firefly_mobile/ui/services/favorites_provider.dart';
import 'package:firefly_mobile/ui/services/service_pages.dart';
import 'package:firefly_mobile/ui/theme/app_theme.dart';
import 'package:firefly_mobile/ui/widgets/pnl_chart/pnl_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Dashboard tab (Phase 2).
///
/// Layout follows `app/docs/dashboard-min.png`: net-worth hero card with
/// month dropdown + income/spent + daily net sparkline, horizontal account
/// cards, budget progress, quick-access grid, upcoming bills. Reads only the
/// five list providers and builds a [DashboardSummary] in one pass.
class DashboardScreen extends ConsumerStatefulWidget {
  /// Creates the Dashboard tab.
  // ignore: unnecessary_type_name_in_constructor — generative ctor.
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Selected month for totals/sparkline; null = month containing now.
  DateTime? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    // Ledger providers, not the paged list providers: balances and net worth
    // sum the whole book, so a 50-row page produces wrong numbers.
    final transactions = ref.watch(ledgerTransactionsProvider);
    final budgets = ref.watch(budgetListProvider);
    final budgetLimits = ref.watch(budgetLimitListProvider);
    final bills = ref.watch(billListProvider);
    final accounts = ref.watch(ledgerAccountsProvider);

    return RefreshIndicator(
      // Fresh pull re-reads the providers (list providers re-fetch on
      // refresh()); the summary is recomputed from the new lists.
      onRefresh: () async {
        ref
          ..invalidate(ledgerTransactionsProvider)
          ..invalidate(ledgerAccountsProvider);
        await Future.wait([
          ref.read(ledgerTransactionsProvider.future),
          ref.read(budgetListProvider.future),
          ref.read(budgetLimitListProvider.future),
          ref.read(billListProvider.future),
          ref.read(ledgerAccountsProvider.future),
        ]);
      },
      // Each provider returns a Widget (not a list): loading/error wrap
      // their status view in a scrollable so RefreshIndicator always has
      // a Scrollable descendant; data nests into the next provider's when.
      child: transactions.when<Widget>(
        loading: () => const _CenteredLoading(),
        error: (e, _) => _CenteredError(error: e),
        data: (txs) => budgets.when<Widget>(
          loading: () => const _CenteredLoading(),
          error: (e, _) => _CenteredError(error: e),
          data: (budgetRows) => budgetLimits.when<Widget>(
            loading: () => const _CenteredLoading(),
            error: (e, _) => _CenteredError(error: e),
            data: (limitRows) => bills.when<Widget>(
              loading: () => const _CenteredLoading(),
              error: (e, _) => _CenteredError(error: e),
              data: (billRows) => accounts.when<Widget>(
                loading: () => const _CenteredLoading(),
                error: (e, _) => _CenteredError(error: e),
                data: (accountRows) {
                  final summary = buildDashboardSummary(
                    transactions: txs,
                    budgets: budgetRows,
                    budgetLimits: limitRows,
                    bills: billRows,
                    accounts: accountRows,
                    month: _selectedMonth,
                  );
                  return _DashboardBody(
                    summary: summary,
                    onMonthSelected: (m) =>
                        setState(() => _selectedMonth = m),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _DashboardBody extends StatelessWidget {
  const new({required this.summary, required this.onMonthSelected});

  final DashboardSummary summary;
  final ValueChanged<DateTime?> onMonthSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _NetWorthCard(summary: summary, onMonthSelected: onMonthSelected),
        if (summary.assetAccounts.isNotEmpty) ...[
          _SectionHeader(
            title: 'Accounts',
            onSeeAll: () => _push(context, accountsConfig),
          ),
          _AccountsCarousel(accounts: summary.assetAccounts),
        ],
        if (summary.budgets.isNotEmpty) ...[
          _SectionHeader(
            title: 'Budgets',
            onSeeAll: () => _push(context, budgetsConfig),
          ),
          _BudgetsSection(budgets: summary.budgets),
        ],
        if (summary.spendingByMonth.isNotEmpty) ...[
          const _SectionHeader(title: 'Spending trend'),
          SizedBox(
            height: 200,
            child: _SpendingLineChart(
              values: summary.spendingByMonth,
              labels: summary.spendingMonthLabels,
            ),
          ),
        ],
        const _SectionHeader(title: 'Quick access'),
        const _QuickAccessGrid(),
        if (summary.upcomingBills.isNotEmpty) ...[
          _SectionHeader(
            title: 'Upcoming bills',
            onSeeAll: () => _push(context, billsConfig),
          ),
          _BillsSection(bills: summary.upcomingBills),
        ],
      ],
    );
  }

  /// Pushes a generic entity list (own app bar) — same path as More.
  static void _push(
    BuildContext context,
    EntityConfig<SyncBookkeeping> config,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => config.buildListScreen()),
    );
  }
}

// ---------------------------------------------------------------------------
// Section chrome
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const new({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: FireflyPalette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(
                  color: FireflyPalette.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Net worth hero card
// ---------------------------------------------------------------------------

class _NetWorthCard extends ConsumerWidget {
  const _NetWorthCard({required this.summary, required this.onMonthSelected});

  final DashboardSummary summary;
  final ValueChanged<DateTime?> onMonthSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final display = ref.watch(currencyDisplayProvider).asData?.value;
    final netSecondary = display?.formatSecondary(
      summary.netWorth,
      summary.netWorthCurrencyCode,
    );
    final incomeSecondary = display?.formatSecondary(
      summary.month.income,
      summary.month.currencyCode,
    );
    final spentSecondary = display?.formatSecondary(
      summary.month.spent,
      summary.month.currencyCode,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Net worth',
                    style: TextStyle(
                      color: FireflyPalette.textDim,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Month dropdown — every month that has transactions,
                // newest first (always includes the current month).
                DropdownButtonHideUnderline(
                  child: DropdownButton<DateTime>(
                    value: summary.monthStart,
                    isDense: true,
                    dropdownColor: FireflyPalette.surfaceElevated,
                    style: const TextStyle(
                      color: FireflyPalette.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: FireflyPalette.textDim,
                      size: 18,
                    ),
                    items: [
                      for (final m in summary.availableMonths)
                        DropdownMenuItem(
                          value: m,
                          child: Text(
                            m.year == now.year && m.month == now.month
                                ? 'This month'
                                : DateFormat('MMMM yyyy').format(m),
                          ),
                        ),
                    ],
                    onChanged: onMonthSelected,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              formatMoney(summary.netWorth, summary.netWorthCurrencyCode),
              style: const TextStyle(
                color: FireflyPalette.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (netSecondary != null)
              Text(
                netSecondary,
                style: const TextStyle(
                  color: FireflyPalette.textDim,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _FlowBadge(
                    icon: Icons.arrow_downward,
                    iconColor: FireflyPalette.chartGreen,
                    label: 'Income',
                    value: formatMoney(
                      summary.month.income,
                      summary.month.currencyCode,
                    ),
                    secondary: incomeSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FlowBadge(
                    icon: Icons.arrow_upward,
                    iconColor: FireflyPalette.negative,
                    label: 'Spent',
                    value: formatMoney(
                      summary.month.spent,
                      summary.month.currencyCode,
                    ),
                    secondary: spentSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _NetPnlChart(summary: summary),
          ],
        ),
      ),
    );
  }
}

class _FlowBadge extends StatelessWidget {
  const _FlowBadge({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.secondary,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: FireflyPalette.textDim,
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: FireflyPalette.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (secondary != null)
                Text(
                  secondary!,
                  style: const TextStyle(
                    color: FireflyPalette.textDim,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Net PnL chart (replaces sparkline)
// ---------------------------------------------------------------------------

class _NetPnlChart extends StatefulWidget {
  const _NetPnlChart({required this.summary});

  final DashboardSummary summary;

  @override
  State<_NetPnlChart> createState() => _NetPnlChartState();
}

class _NetPnlChartState extends State<_NetPnlChart> {
  List<DailyPnl> _data = const [];
  Object? _key;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _NetPnlChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final s = widget.summary;
    final key = (s.monthStart, s.netSeries.length, s.netSeries.isEmpty ? 0.0 : s.netSeries.last);
    if (key == _key) return;
    _key = key;
    final series = s.netSeries;
    if (series.length < 2) {
      _data = const [];
      return;
    }
    final start = s.monthStart;
    _data = List<DailyPnl>.generate(series.length - 1, (i) {
      final day = DateTime(start.year, start.month, start.day + i);
      return DailyPnl(day, series[i + 1] - series[i]);
    }, growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    if (_data.isEmpty) {
      return const SizedBox.shrink();
    }
    final days = _data.length;
    final endDate = DateTime(s.monthStart.year, s.monthStart.month, s.monthStart.day + days - 1);
    return PnlChart(
      data: _data,
      currency: s.month.currencyCode ?? s.netWorthCurrencyCode,
      endDate: endDate,
      initialRange: PnlRange.all,
      chartHeight: 220,
      theme: PnlChartTheme.dark,
    );
  }
}

// ---------------------------------------------------------------------------
// Accounts carousel
// ---------------------------------------------------------------------------

class _AccountsCarousel extends StatelessWidget {
  const new({required this.accounts});

  final List<AccountBalance> accounts;

  /// Icon by Firefly account role (config/firefly.php accountRoles).
  static IconData _iconFor(Account account) {
    switch (account.accountRole) {
      case 'defaultAsset':
        return Icons.account_balance_wallet_outlined;
      case 'savingAsset':
        return Icons.savings_outlined;
      case 'ccAsset':
        return Icons.credit_card_outlined;
      case 'cashWalletAsset':
        return Icons.payments_outlined;
      default:
        return Icons.account_balance_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: accounts.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final entry = accounts[i];
          final color = entry.balance >= 0
              ? FireflyPalette.primary
              : FireflyPalette.negative;
          return SizedBox(
            width: 140,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_iconFor(entry.account), size: 22, color: color),
                    const Spacer(),
                    Text(
                      entry.account.name,
                      style: const TextStyle(
                        color: FireflyPalette.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      formatMoney(
                        entry.balance,
                        entry.account.currencyCode,
                      ),
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

class _BudgetsSection extends StatelessWidget {
  const new({required this.budgets});

  final List<BudgetProgress> budgets;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (var i = 0; i < budgets.length; i++) ...[
              if (i > 0) const Divider(height: 16),
              _BudgetRow(progress: budgets[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const new({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction.clamp(0.0, 1.0);
    final barColor = progress.over
        ? FireflyPalette.negative
        : FireflyPalette.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                progress.budget.name,
                style: const TextStyle(
                  color: FireflyPalette.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${formatMoney(progress.spent, progress.budget.currencyCode)}'
              ' / ${formatMoney(progress.limitAmount, progress.budget.currencyCode)}',
              style: const TextStyle(
                color: FireflyPalette.textDim,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: FireflyPalette.outline,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Quick access grid
// ---------------------------------------------------------------------------

class _QuickAccessGrid extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider).value ?? kDefaultFavoriteIds;
    final pages = <ServicePage>[
      for (final id in favorites) ...[
        if (servicePageById(id) != null) servicePageById(id)!,
      ],
    ];
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.85,
      children: <Widget>[
        for (final page in pages)
          _QuickAccessTile(
            icon: page.icon,
            label: page.title,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: page.builder),
            ),
          ),
        _QuickAccessTile(
          icon: Icons.apps,
          label: 'More',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ServicesScreen(),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickAccessTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: FireflyPalette.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: FireflyPalette.primary),
            ),
            const SizedBox(height: 8),
            // Flexible: at narrow widths keep label visible without overflow.
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: FireflyPalette.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming bills
// ---------------------------------------------------------------------------

class _BillsSection extends StatelessWidget {
  const new({required this.bills});

  final List<Bill> bills;

  /// "in 3 days" / "tomorrow" / "today" from nextExpectedMatch vs now.
  static String _dueLabel(Bill bill, DateTime now) {
    final next = bill.nextExpectedMatch!;
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(next.year, next.month, next.day);
    final days = due.difference(today).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'tomorrow';
    return 'in $days days';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (var i = 0; i < bills.length; i++) ...[
              if (i > 0) const Divider(height: 16),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: FireflyPalette.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.schedule,
                    size: 18,
                    color: FireflyPalette.primary,
                  ),
                ),
                title: Text(
                  bills[i].name,
                  style: const TextStyle(
                    color: FireflyPalette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _dueLabel(bills[i], now),
                  style: const TextStyle(
                    color: FireflyPalette.textDim,
                    fontSize: 11,
                  ),
                ),
                trailing: Text(
                  formatMoney(
                    parseAmount(bills[i].amount),
                    bills[i].currencyCode,
                  ),
                  style: const TextStyle(
                    color: FireflyPalette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared status widgets (loading / error)
// ---------------------------------------------------------------------------

class _CenteredLoading extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    // SliverFillRemaining keeps a Scrollable under RefreshIndicator and
    // centers the spinner in the viewport.
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }
}

class _CenteredError extends StatelessWidget {
  const new({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    // Same scrollable wrapper as _CenteredLoading (pull-to-refresh must
    // always find a Scrollable descendant).
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 40,
                    color: FireflyPalette.negative,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Couldn’t load the dashboard.\n$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: FireflyPalette.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Spending trend chart
// ---------------------------------------------------------------------------

class _SpendingLineChart extends StatelessWidget {
  const _SpendingLineChart({required this.values, required this.labels});

  final List<double> values;
  final List<String> labels;

  String _fmtAxis(double v) {
    final a = v.abs();
    String s;
    if (a >= 1000000) {
      s = '${(v / 1000000).toStringAsFixed(1)}M';
    } else if (a >= 1000) {
      s = '${(v / 1000).toStringAsFixed(a >= 10000 ? 0 : 1)}k';
    } else if (a == a.roundToDouble()) {
      s = v.toStringAsFixed(0);
    } else {
      s = v.toStringAsFixed(1);
    }
    return s.replaceAll('.0k', 'k').replaceAll('.0M', 'M');
  }

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final maxV = values.reduce(math.max);
    final minV = 0.0;
    final span = maxV <= 0 ? 1.0 : maxV;
    final top = span * 1.15;
    final interval = top / 4;

    final spots = <FlSpot>[
      for (var i = 0; i < values.length; i++)
        FlSpot(i.toDouble(), values[i]),
    ];

    final labelStep = values.length <= 6 ? 1 : (values.length / 6).ceil();

    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8),
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (values.length - 1).toDouble(),
          minY: minV,
          maxY: top,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: FireflyPalette.outline,
              strokeWidth: 1,
              dashArray: [3, 3],
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: interval,
                getTitlesWidget: (v, _) {
                  if (v < 0) return const SizedBox.shrink();
                  return Text(
                    _fmtAxis(v),
                    style: const TextStyle(
                      color: FireflyPalette.textDim,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  if (i % labelStep != 0 && i != labels.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labels[i],
                      style: const TextStyle(
                        color: FireflyPalette.textDim,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => FireflyPalette.surfaceElevated,
              getTooltipItems: (touched) => [
                for (final t in touched)
                  LineTooltipItem(
                    '${labels[t.x.toInt().clamp(0, labels.length - 1)]}\n${t.y.toStringAsFixed(2)}',
                    const TextStyle(
                      color: FireflyPalette.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            handleBuiltInTouches: true,
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: FireflyPalette.negative,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                  radius: 3,
                  color: FireflyPalette.negative,
                  strokeWidth: 1.5,
                  strokeColor: FireflyPalette.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    FireflyPalette.negative.withValues(alpha: 0.25),
                    FireflyPalette.negative.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}
