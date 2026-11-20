/// Deterministic name → icon/color pairs for list rows (dashboard budgets,
/// bills, transactions, reports legends). Pure keyword lookup with a
/// stable hash fallback — no randomness, no provider, rebuild-safe.
library;

import 'package:flutter/material.dart';

/// One colored icon resolved for a display name.
class NameIcon {
  /// Builds a name-icon pair.
  const new({required this.icon, required this.color});

  /// Glyph to render.
  final IconData icon;

  /// Foreground/background tint (muted, readable on the dark theme).
  final Color color;
}

/// Curated dark-theme palette the hash fallback cycles through.
const List<(IconData, Color)> kNameIconPalette = [
  (Icons.shopping_cart_outlined, Color(0xFFA5D075)),
  (Icons.directions_bus_outlined, Color(0xFF7BB8C9)),
  (Icons.home_outlined, Color(0xFFCCBB62)),
  (Icons.work_outline, Color(0xFFB49AD8)),
  (Icons.restaurant_outlined, Color(0xFFF1A36E)),
  (Icons.local_cafe_outlined, Color(0xFFD4929B)),
  (Icons.local_grocery_store_outlined, Color(0xFF8FC56A)),
  (Icons.flight_outlined, Color(0xFF6EC0E0)),
  (Icons.favorite_outline, Color(0xFFF08A8A)),
  (Icons.savings_outlined, Color(0xFF9BCF7F)),
  (Icons.devices_other_outlined, Color(0xFF9AA8D8)),
  (Icons.local_laundry_service_outlined, Color(0xFFC9A87B)),
];

/// Keyword → palette-index table; first substring hit wins (lowercase).
/// Extensible — add a word per domain as it shows up in demo/real data.
const Map<String, int> kNameIconKeywords = {
  'grocer': 6,
  'supermarket': 6,
  'food': 4,
  'restaurant': 4,
  'dining': 4,
  'coffee': 5,
  'cafe': 5,
  'rent': 2,
  'mortgage': 2,
  'house': 2,
  'home': 2,
  'salary': 3,
  'payroll': 3,
  'freelance': 3,
  'transport': 1,
  'bus': 1,
  'train': 1,
  'metro': 1,
  'uber': 1,
  'fuel': 1,
  'petrol': 1,
  'travel': 7,
  'flight': 7,
  'hotel': 7,
  'health': 8,
  'doctor': 8,
  'medical': 8,
  'pharmacy': 8,
  'saving': 9,
  'investment': 9,
  'income': 0,
  'shopping': 0,
  'amazon': 0,
  'electronics': 10,
  'phone': 10,
  'internet': 10,
  'utility': 11,
  'electric': 11,
  'water': 11,
};

/// Resolves [name] to a stable icon + color: keyword table first, then
/// [String.hashCode] into [kNameIconPalette]. Empty names get the first
/// palette slot. Same name always resolves to the same pair.
NameIcon nameIconFor(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) {
    final slot = kNameIconPalette.first;
    return NameIcon(icon: slot.$1, color: slot.$2);
  }
  for (final entry in kNameIconKeywords.entries) {
    if (key.contains(entry.key)) {
      final slot = kNameIconPalette[entry.value];
      return NameIcon(icon: slot.$1, color: slot.$2);
    }
  }
  final slot = kNameIconPalette[key.hashCode.abs() % kNameIconPalette.length];
  return NameIcon(icon: slot.$1, color: slot.$2);
}

/// Account-type glyph for the dashboard cards row and entity lists.
IconData accountTypeIcon(String type, {String? accountRole}) {
  switch (type) {
    case 'liability':
      return Icons.credit_card_outlined;
    case 'expense':
      return Icons.payments_outlined;
    case 'revenue':
      return Icons.savings_outlined;
    default:
      // Asset sub-roles (checking/savings/cash) all render a wallet/bank.
      return switch (accountRole) {
        'savingAsset' => Icons.savings_outlined,
        'cashWalletAsset' => Icons.account_balance_wallet_outlined,
        _ => Icons.account_balance_outlined,
      };
  }
}
