import 'dart:convert';

import 'package:firefly_mobile/core/providers.dart' show metaProvider;
import 'package:firefly_mobile/data/dao/device_meta_dao.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// User-selected currency display preferences and cached exchange rates.
///
/// Rates are sourced from the open, no-key fawazahmed0/exchange-api CDN
/// (daily-updated, 200+ currencies incl. PKR) with a Cloudflare Pages
/// fallback. Cached locally in `device_meta` so conversion works offline.
class CurrencyDisplaySettings {
  /// Creates immutable display settings.
  const CurrencyDisplaySettings({
    required this.displayCurrency,
    required this.cache,
    required this.fetchedAtMs,
    this.manualRates = const <String, Map<String, double>>{},
  });

  /// Hand-entered rates as `{FROM: {TO: rate}}` — "1 FROM = rate TO".
  ///
  /// Consulted before any online rate so a custom currency (BTC and friends,
  /// which no public feed covers reliably) converts exactly as the user typed
  /// it, in both directions, and keeps working offline.
  final Map<String, Map<String, double>> manualRates;

  /// Secondary currency to show converted amounts in (ISO 4217, uppercased),
  /// or null/empty when disabled.
  final String? displayCurrency;

  /// Cached rate payloads keyed by base currency code (lowercased).
  /// Each value is the decoded API response for that base.
  final Map<String, Map<String, dynamic>> cache;

  /// Epoch ms when the cache was last refreshed, or null if never.
  final int? fetchedAtMs;

  /// Whether a secondary display currency is configured.
  bool get enabled =>
      displayCurrency != null && displayCurrency!.trim().isNotEmpty;

  /// Converts [amount] from [fromCode] to [toCode] using cached rates.
  /// Returns null if codes are missing/equal or no rate is available.
  ///
  /// Tries, in order:
  /// 1. direct rates for base=[fromCode] (1 from = r to)
  /// 2. inverse rates for base=[toCode] (1 to = r from => amount/r)
  /// 3. cross rates via any cached base B (amount * B[to]/B[from])
  double? convert(double amount, String? fromCode, String? toCode) {
    final from = _norm(fromCode);
    final to = _norm(toCode);
    if (from == null || to == null) return null;
    if (from == to) return amount;
    final manual = manualRate(from, to);
    if (manual != null) return amount * manual;
    final direct = _rate(from, to);
    if (direct != null) return amount * direct;
    final inverse = _rate(to, from);
    if (inverse != null && inverse != 0) return amount / inverse;
    // Cross-convert through any base that knows both currencies.
    for (final entry in cache.entries) {
      final rates = entry.value[entry.key];
      if (rates is! Map) continue;
      final rFrom = _asDouble(rates[from.toLowerCase()]);
      final rTo = _asDouble(rates[to.toLowerCase()]);
      if (rFrom != null && rTo != null && rFrom != 0) {
        return amount * (rTo / rFrom);
      }
    }
    return null;
  }

  /// Rate: 1 [fromCode] = ? [toCode] from the manual table, or null.
  ///
  /// The reverse direction is used as a fallback only when the user did not
  /// enter it, so an explicitly typed "65,000.34 USD = 1 BTC" wins over the
  /// arithmetic reciprocal of "1 BTC = 65,000 USD".
  double? manualRate(String? fromCode, String? toCode) {
    final from = _norm(fromCode);
    final to = _norm(toCode);
    if (from == null || to == null || from == to) return null;
    final direct = manualRates[from]?[to];
    if (direct != null) return direct;
    final inverse = manualRates[to]?[from];
    if (inverse != null && inverse != 0) return 1 / inverse;
    return null;
  }

  /// Copies this settings object with a new manual-rate table.
  CurrencyDisplaySettings withManualRates(
    Map<String, Map<String, double>> rates,
  ) => CurrencyDisplaySettings(
    displayCurrency: displayCurrency,
    cache: cache,
    fetchedAtMs: fetchedAtMs,
    manualRates: rates,
  );

  /// Rate: 1 [baseCode] = ? [targetCode], or null if unavailable.
  double? _rate(String baseCode, String targetCode) {
    final base = baseCode.toLowerCase();
    final payload = cache[base];
    if (payload == null) return null;
    final rates = payload[base];
    if (rates is! Map) return null;
    return _asDouble(rates[targetCode.toLowerCase()]);
  }

  /// Converts and formats "≈ ..." for display below a primary amount, or null
  /// when conversion is unavailable/disabled/same-currency.
  String? formatSecondary(double amount, String? fromCode) {
    if (!enabled) return null;
    final converted = convert(amount, fromCode, displayCurrency);
    if (converted == null) return null;
    return '≈ ${_formatSimple(converted, displayCurrency!)}';
  }

  static String? _norm(String? code) {
    if (code == null) return null;
    final t = code.trim();
    return t.isEmpty ? null : t.toUpperCase();
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  /// Lightweight formatting for converted/secondary amounts.
  static String _formatSimple(double amount, String code) {
    final abs = amount.abs();
    String numStr;
    if (abs == 0) {
      numStr = '0';
    } else if (abs >= 1000) {
      numStr = amount.toStringAsFixed(2);
    } else if (abs >= 1) {
      numStr = amount.toStringAsFixed(2);
    } else {
      numStr = amount.toStringAsFixed(4);
    }
    return '${_symbol(code)}$numStr';
  }

  static String _symbol(String code) {
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
      case 'AUD':
        return r'A$';
      case 'CAD':
        return r'C$';
      case 'INR':
        return '₹';
      case 'AED':
        return 'AED ';
      case 'SAR':
        return 'SAR ';
      case 'CNY':
        return '¥';
      default:
        return '${code.toUpperCase()} ';
    }
  }
}

/// Loads and persists currency display preferences and exchange-rate cache.
class CurrencyDisplayStore {
  /// Creates a store bound to [meta].
  CurrencyDisplayStore(this.meta);

  /// Device metadata DAO.
  final DeviceMetaDao meta;

  /// Reads current display settings and cached rates.
  Future<CurrencyDisplaySettings> read() async {
    final display = await meta.get(DeviceMetaDao.displayCurrencyKey);
    final cacheStr = await meta.get(DeviceMetaDao.exchangeRatesCacheKey);
    final fetchedStr = await meta.get(DeviceMetaDao.exchangeRatesFetchedAtKey);
    final cache = <String, Map<String, dynamic>>{};
    if (cacheStr != null && cacheStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(cacheStr);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            if (e.value is Map) {
              cache[e.key.toString().toLowerCase()] = Map<String, dynamic>.from(
                e.value as Map,
              );
            }
          }
        }
      } catch (_) {
        // Ignore corrupt cache; it will be refreshed.
      }
    }
    final manualStr = await meta.get(DeviceMetaDao.exchangeRatesManualKey);
    final manual = <String, Map<String, double>>{};
    if (manualStr != null && manualStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(manualStr);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is! Map) continue;
            final pairs = <String, double>{};
            for (final pair in (entry.value as Map).entries) {
              final rate = CurrencyDisplaySettings._asDouble(pair.value);
              if (rate == null) continue;
              pairs[pair.key.toString().toUpperCase()] = rate;
            }
            if (pairs.isNotEmpty) {
              manual[entry.key.toString().toUpperCase()] = pairs;
            }
          }
        }
      } catch (_) {
        // Ignore a corrupt manual table; the user can re-enter it.
      }
    }
    return CurrencyDisplaySettings(
      displayCurrency: (display == null || display.trim().isEmpty)
          ? null
          : display.trim().toUpperCase(),
      cache: cache,
      fetchedAtMs: fetchedStr == null ? null : int.tryParse(fetchedStr),
      manualRates: manual,
    );
  }

  /// Persists the manual rate table (`{FROM: {TO: rate}}`).
  Future<void> saveManualRates(Map<String, Map<String, double>> rates) async {
    await meta.set(DeviceMetaDao.exchangeRatesManualKey, jsonEncode(rates));
  }

  /// Persists the selected display currency (or clears when null/empty).
  Future<void> setDisplayCurrency(String? code) async {
    final v = code?.trim().toUpperCase() ?? '';
    await meta.set(DeviceMetaDao.displayCurrencyKey, v);
  }

  /// Persists the merged cache and fetch timestamp.
  Future<void> saveCache(
    Map<String, Map<String, dynamic>> cache, {
    required int fetchedAtMs,
  }) async {
    await meta.set(DeviceMetaDao.exchangeRatesCacheKey, jsonEncode(cache));
    await meta.set(
      DeviceMetaDao.exchangeRatesFetchedAtKey,
      fetchedAtMs.toString(),
    );
  }
}

/// Fetches latest exchange rates for [baseCode] (e.g. USD) from the open
/// fawazahmed0/exchange-api CDN with a Cloudflare fallback. Returns the
/// decoded payload (contains `date` and `<base>` rates map) or null on failure.
Future<Map<String, dynamic>?> fetchExchangeRates(String baseCode) async {
  final base = baseCode.trim().toLowerCase();
  if (base.isEmpty) return null;
  final urls = <String>[
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/$base.json',
    'https://latest.currency-api.pages.dev/v1/currencies/$base.json',
  ];
  for (final url in urls) {
    try {
      debugPrint('[rates] fetching base=$base from $url');
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      debugPrint('[rates] base=$base status=${resp.statusCode} from $url');
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('[rates] fetch failed base=$base url=$url error=$e');
      // Try fallback.
    }
  }
  return null;
}

/// Ensures rates for [baseCode] are cached (refreshes if missing/stale).
/// Returns updated settings.
Future<CurrencyDisplaySettings> ensureRatesFor(
  CurrencyDisplayStore store,
  CurrencyDisplaySettings current,
  String baseCode, {
  Duration maxAge = const Duration(hours: 12),
}) async {
  final base = baseCode.trim().toLowerCase();
  if (base.isEmpty) return current;
  final now = DateTime.now().millisecondsSinceEpoch;
  final fresh =
      current.cache.containsKey(base) &&
      current.fetchedAtMs != null &&
      (now - current.fetchedAtMs!) < maxAge.inMilliseconds;
  if (fresh) return current;
  final fetched = await fetchExchangeRates(base);
  if (fetched == null) return current;
  final merged = Map<String, Map<String, dynamic>>.from(current.cache);
  merged[base] = fetched;
  await store.saveCache(merged, fetchedAtMs: now);
  return CurrencyDisplaySettings(
    displayCurrency: current.displayCurrency,
    cache: merged,
    fetchedAtMs: now,
    manualRates: current.manualRates,
  );
}

/// Ensures we can convert between common currencies by fetching a few
/// well-connected bases (USD/EUR) whose rate tables cover most pairs via
/// cross-conversion. Safe to call repeatedly (respects [maxAge]).
Future<CurrencyDisplaySettings> ensureConversionRates(
  CurrencyDisplayStore store,
  CurrencyDisplaySettings current, {
  Iterable<String> preferredBases = const <String>['usd', 'eur'],
  Duration maxAge = const Duration(hours: 12),
}) async {
  var out = current;
  for (final base in preferredBases) {
    out = await ensureRatesFor(store, out, base, maxAge: maxAge);
  }
  return out;
}

/// Provider: currency display store.
final currencyDisplayStoreProvider = FutureProvider<CurrencyDisplayStore>((
  ref,
) async {
  final meta = await ref.watch(metaProvider.future);
  return CurrencyDisplayStore(meta);
});

/// Provider: current currency display settings (rates cache + selected display currency).
///
/// When a display currency is enabled, proactively ensures a few well-connected
/// base rate tables (USD/EUR, plus the display currency) are cached so
/// cross-currency conversion works without requiring a manual refresh.
final currencyDisplayProvider = FutureProvider<CurrencyDisplaySettings>((
  ref,
) async {
  final store = await ref.watch(currencyDisplayStoreProvider.future);
  var settings = await store.read();
  if (settings.enabled) {
    final bases = <String>{
      'usd',
      'eur',
      settings.displayCurrency!.toLowerCase(),
    };
    settings = await ensureConversionRates(
      store,
      settings,
      preferredBases: bases,
      maxAge: const Duration(hours: 12),
    );
  }
  return settings;
});

/// Common ISO currency codes offered in pickers (broad set incl. PKR).
const List<String> kCommonCurrencyCodes = <String>[
  'USD', 'EUR', 'GBP', 'PKR', 'AUD', 'CAD', 'JPY', 'CNY', 'INR', 'AED',
  'SAR', 'CHF', 'SEK', 'NOK', 'DKK', 'NZD', 'SGD', 'HKD', 'ZAR', 'TRY',
  'MYR', 'THB', 'IDR', 'BDT', 'NGN', 'KES', 'EGP', 'QAR', 'KWD', 'BHD',
];
