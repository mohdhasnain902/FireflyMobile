import 'dart:async';

import 'package:firefly_mobile/core/providers.dart';
import 'package:firefly_mobile/domain/entities/transaction.dart';
import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/screens/dashboard_screen.dart';
import 'package:firefly_mobile/ui/screens/entity_list_screen.dart';
import 'package:firefly_mobile/ui/screens/reports_screen.dart';
import 'package:firefly_mobile/ui/screens/settings_screen.dart';
import 'package:firefly_mobile/ui/widgets/sync_status.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation shell: bottom [NavigationBar] destinations — Dashboard,
/// Transactions, Budgets, Reports, Settings — and a shared app bar whose
/// title follows the active tab.
///
/// Tabs live in an [IndexedStack] so each keeps its scroll position and
/// form state when the user switches away. Transactions and Budgets host
/// the generic list in `embedded: true` mode (no own app bar); Settings
/// is also embedded in the shell.
///
/// The one provider touchpoint in this shell is the [SyncStatusIndicator]
/// in the app bar (connection state + last-sync age + pending backlog).
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates the bottom-nav home shell.
  const new({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Index of the active tab; also the [IndexedStack] child index.
  int _index = 0;

  /// Tab titles — index-matched with [NavigationBar] destinations.
  static const List<_TabSpec> _tabs = [
    _TabSpec('Dashboard', Icons.dashboard_outlined),
    _TabSpec('Transactions', Icons.swap_vert),
    _TabSpec('Budgets', Icons.savings_outlined),
    _TabSpec('Reports', Icons.pie_chart_outline),
    _TabSpec('Settings', Icons.settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    // Post-frame: the first build must not block on a real async DB open.
    // After the frame settles, kick the one-shot auto-seed (no-ops when
    // demoSeedEnabledProvider is false or the DB already has data).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(autoDemoSeedProvider.future));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Product name is the Settings/About brand; the mockup shows the
        // active tab as the screen title.
        title: Text(_tabs[_index].label),
        actions: const [SyncStatusIndicator()],
      ),
      body: IndexedStack(
        index: _index,
        // Not const: the EntityConfig instances (transactionsConfig,
        // budgetsConfig) are runtime top-level finals, not const.
        children: [
          const DashboardScreen(),
          // Embedded: shell owns the app bar; the list keeps its own FAB
          // and pull-to-refresh (they attach to the inner Scaffold).
          EntityListScreen<Transaction>(
            config: transactionsConfig,
            embedded: true,
          ),
          EntityListScreen(
            config: budgetsConfig,
            embedded: true,
          ),
          const ReportsScreen(),
          const SettingsScreen(embedded: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.icon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

/// One bottom-nav destination: label + icon (same icon selected or not —
/// the lime indicator pill carries the active state, per the mockup).
class _TabSpec {
  const new(this.label, this.icon);

  final String label;
  final IconData icon;
}
