import 'package:firefly_mobile/core/constants.dart'
    show kDefaultCurrencyCode;

import 'package:intl/intl.dart';

/// Formats a double as a locale currency string for the dashboard and
/// list rows (Phase 1). Uses the ISO [currencyCode] when given, else the
/// app default ([kDefaultCurrencyCode] — Firefly's usual fallback).
///
/// Zero fractionals for whole amounts ("€12" not "€12.00") keeps the
/// cards scannable; negative amounts keep their sign (net can go red).
String formatMoney(double amount, String? currencyCode) {
  final code = currencyCode ?? kDefaultCurrencyCode;
  final symbol = _symbolFor(code);
  final formatted = NumberFormat.decimalPattern().format(amount);
  return '$symbol$formatted';
}

/// Minimal ISO-code → symbol map for the currencies Firefly users hit
/// most; unknown codes render as "CODE " prefix (never invent a symbol).
String _symbolFor(String code) {
  switch (code.toUpperCase()) {
    case 'EUR':
      return '€';
    case 'USD':
      return r'$';
    case 'GBP':
      return '£';
    case 'PKR':
      return 'Rs ';
    case 'JPY':
      return '¥';
    default:
      return '$code ';
  }
}
