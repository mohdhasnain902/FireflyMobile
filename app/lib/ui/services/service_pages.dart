/// Registry of every screen reachable from the "Services" favorites grid.
library;

import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:firefly_mobile/ui/screens/about_screen.dart';
import 'package:firefly_mobile/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';

/// A single page reachable from the Services favorites grid.
class ServicePage {
  /// Creates a service page descriptor.
  const new({
    required this.id,
    required this.title,
    required this.icon,
    required this.builder,
  });

  /// Stable identifier persisted in `device_meta` (`services_favorites`).
  final String id;

  /// Human-readable label shown under the tile.
  final String title;

  /// Icon shown on the tile.
  final IconData icon;

  /// Builds the screen to push when the tile is tapped.
  final WidgetBuilder builder;
}

/// The default five favorites shown on the home dashboard.
const List<String> kDefaultFavoriteIds = <String>[
  'accounts',
  'bills',
  'piggy_banks',
  'rules',
  'categories',
];

/// Maximum number of favorites the user may pin.
const int kMaxFavorites = 7;

/// All 14 service pages, in stable display order.
final List<ServicePage> allServicePages = <ServicePage>[
  ServicePage(
    id: 'accounts',
    title: accountsConfig.title,
    icon: accountsConfig.icon,
    builder: (_) => accountsConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'attachments',
    title: attachmentsConfig.title,
    icon: attachmentsConfig.icon,
    builder: (_) => attachmentsConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'bills',
    title: billsConfig.title,
    icon: billsConfig.icon,
    builder: (_) => billsConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'budget_limits',
    title: budgetLimitsConfig.title,
    icon: budgetLimitsConfig.icon,
    builder: (_) => budgetLimitsConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'categories',
    title: categoriesConfig.title,
    icon: categoriesConfig.icon,
    builder: (_) => categoriesConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'currencies',
    title: currenciesConfig.title,
    icon: currenciesConfig.icon,
    builder: (_) => currenciesConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'piggy_banks',
    title: piggyBanksConfig.title,
    icon: piggyBanksConfig.icon,
    builder: (_) => piggyBanksConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'recurrences',
    title: recurrencesConfig.title,
    icon: recurrencesConfig.icon,
    builder: (_) => recurrencesConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'rule_groups',
    title: ruleGroupsConfig.title,
    icon: ruleGroupsConfig.icon,
    builder: (_) => ruleGroupsConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'rules',
    title: rulesConfig.title,
    icon: rulesConfig.icon,
    builder: (_) => rulesConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'subscriptions',
    title: subscriptionsConfig.title,
    icon: subscriptionsConfig.icon,
    builder: (_) => subscriptionsConfig.buildListScreen(),
  ),
  ServicePage(
    id: 'tags',
    title: tagsConfig.title,
    icon: tagsConfig.icon,
    builder: (_) => tagsConfig.buildListScreen(),
  ),
  const ServicePage(
    id: 'settings',
    title: 'Settings',
    icon: Icons.settings_outlined,
    builder: _settingsBuilder,
  ),
  const ServicePage(
    id: 'about',
    title: 'About',
    icon: Icons.info_outline,
    builder: _aboutBuilder,
  ),
];

Widget _settingsBuilder(BuildContext context) => const SettingsScreen();

Widget _aboutBuilder(BuildContext context) => const AboutScreen();

/// Lookup helper.
ServicePage? servicePageById(String id) {
  for (final page in allServicePages) {
    if (page.id == id) return page;
  }
  return null;
}
