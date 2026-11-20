import 'package:firefly_mobile/core/currency/exchange_rates.dart';
import 'package:flutter_test/flutter_test.dart';

/// Manual rates: Firefly lets both directions of a pair be typed by hand
/// ("1 BTC = 65000 USD" and "65000.34 USD = 1 BTC"). Those entries are not
/// forced to be reciprocals, are checked before the online cache and work
/// offline, so a custom currency converts exactly as entered.
void main() {
  // "1 BTC = 65000 USD" and "65000.34 USD = 1 BTC" (i.e. 1 USD =
  // 1/65000.34 BTC) — the two directions are stored independently and need not
  // be exact reciprocals, exactly as Firefly lets the user enter them.
  const settings = CurrencyDisplaySettings(
    displayCurrency: 'USD',
    cache: <String, Map<String, dynamic>>{
      'usd': <String, dynamic>{
        'usd': <String, dynamic>{'eur': 0.9, 'gbp': 0.8},
      },
    },
    fetchedAtMs: 1,
    manualRates: <String, Map<String, double>>{
      'BTC': <String, double>{'USD': 65000},
      'USD': <String, double>{'BTC': 1 / 65000.34},
    },
  );

  test('each direction uses the rate the user typed', () {
    // 2 BTC at the entered 1 BTC = 65,000 USD.
    expect(settings.convert(2, 'BTC', 'USD'), 130000);
    // 65,000.34 USD is 1 BTC at the entered "65000.34 USD = 1 BTC" rate —
    // deliberately not the reciprocal of 65,000.
    expect(settings.convert(65000.34, 'USD', 'BTC'), closeTo(1, 1e-9));
  });

  test('manual rates win over the fetched cache', () {
    // The online table says 1 USD = 0.9 EUR; a manual USD→EUR rate must win.
    final withManual = settings.withManualRates(<String, Map<String, double>>{
      'USD': <String, double>{'EUR': 0.5},
    });
    expect(withManual.convert(10, 'USD', 'EUR'), 5);
    // Without the manual entry the cached rate still applies.
    expect(settings.convert(10, 'USD', 'EUR'), 9);
  });

  test('a one-way entry converts the other way via its reciprocal', () {
    const oneWay = CurrencyDisplaySettings(
      displayCurrency: null,
      cache: <String, Map<String, dynamic>>{},
      fetchedAtMs: null,
      manualRates: <String, Map<String, double>>{
        'BTC': <String, double>{'USD': 50000},
      },
    );
    expect(oneWay.convert(1, 'BTC', 'USD'), 50000);
    expect(oneWay.convert(50000, 'USD', 'BTC'), closeTo(1, 1e-9));
  });

  test('manual rates work with an empty online cache (offline)', () {
    const offline = CurrencyDisplaySettings(
      displayCurrency: null,
      cache: <String, Map<String, dynamic>>{},
      fetchedAtMs: null,
      manualRates: <String, Map<String, double>>{
        'POINT': <String, double>{'USD': 0.01},
      },
    );
    expect(offline.convert(250, 'POINT', 'USD'), closeTo(2.5, 1e-9));
  });

  test('manualRate is case-insensitive and null for unknown pairs', () {
    expect(settings.manualRate('btc', 'usd'), 65000);
    expect(settings.manualRate('BTC', 'GBP'), null);
    expect(settings.manualRate('BTC', 'BTC'), null);
  });
}
