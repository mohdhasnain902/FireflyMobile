import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Golden-fixture contract smoke test.
///
/// The fixtures in `test/fixtures/api/` are captured verbatim (then
/// normalised) from the pinned Firefly III instance by
/// `infra/firefly/capture_fixtures.sh`. They exist to make an API contract
/// change *loud* — see DESIGN.md L476: "Any Firefly version bump that
/// changes the contract is caught by fixture diff."
///
/// This test is deliberately OFFLINE: it reads the committed JSON only, so
/// it runs in CI without a live server. Two things are proven here:
///   1. the fixtures are well-formed JSON:API and carry the fields the
///      app reads;
///   2. no live credential has been captured into a file we intend to
///      commit.
///
/// The live comparison is a separate step: `capture_fixtures.sh --check`.
const _fixDir = 'test/fixtures/api';

/// Every fixture we expect to ship, mapped to whether it is a JSON:API
/// *collection* (needs `data: []` + `meta.pagination`) or a single
/// resource / bare payload.
const _listFixtures = <String, String>{
  'accounts': 'accounts',
  'transactions': 'transactions',
  'budgets': 'budgets',
  'categories': 'categories',
  'tags': 'tags',
  'rules': 'rules',
  'rule_groups': 'rule_groups',
  'piggy_banks': 'piggy_banks',
  'currencies': 'currencies',
  'subscriptions': 'subscriptions',
  'bills': 'bills',
  'users': 'users',
  'preferences': 'preferences',
  'attachments': 'attachments',
};

/// Single-resource fixtures (shape: top-level object whose `data` is an
/// object rather than an array).
const _itemFixtures = <String>{
  'account_1',
  'transaction_1',
};

/// Seeded collections the test asserts are non-empty — an empty capture
/// would mean the seed script did not run against the live instance.
const _mustBeSeeded = <String>{'accounts', 'transactions', 'currencies'};

/// Preference rows whose `name` marks `data` as a credential. Matched
/// case-insensitively by substring — keep in sync with the redaction list
/// in `infra/firefly/capture_fixtures.sh`.
const _sensitiveNameMarkers = <String>[
  'token',
  'secret',
  'password',
  'key',
  'webhook',
  'recovery',
];

Map<String, dynamic> _load(String stem) {
  final file = File('$_fixDir/$stem.json');
  expect(file.existsSync(), isTrue, reason: 'missing fixture $stem.json');
  final decoded = jsonDecode(file.readAsStringSync());
  expect(decoded, isA<Map<String, dynamic>>(),
      reason: '$stem.json must be a JSON object');
  return decoded as Map<String, dynamic>;
}

/// `data` member of a fixture, always as a typed map (JSON:API resource
/// object). Avoids dynamic dispatch, which the linter forbids.
Map<String, dynamic> _resource(String stem) =>
    _load(stem)['data'] as Map<String, dynamic>;

/// `attributes` member of a single-resource fixture.
Map<String, dynamic> _attrs(String stem) =>
    _resource(stem)['attributes'] as Map<String, dynamic>;

void main() {
  group('golden fixtures — manifest & version pin', () {
    test('manifest pins the Firefly version the fixtures came from', () {
      final manifest = _load('manifest');
      expect(manifest['firefly_version'], isA<String>());
      expect(manifest['firefly_version'], isNotEmpty);
    });

    test('fixture version matches the pinned docker image tag', () {
      final version =
          (_load('manifest')['firefly_version'] as String).trim();

      // The compose file is the single source of truth for the image pin.
      final compose = File('../infra/firefly/docker-compose.yml');
      expect(compose.existsSync(), isTrue,
          reason: 'docker-compose.yml not found at ../infra/firefly/');

      // `image: fireflyiii/core:version-6.7.9` -> tag after the colon.
      final match = RegExp(r'image:\s*fireflyiii/core:version-(\S+)')
          .firstMatch(compose.readAsStringSync());
      expect(match, isNotNull,
          reason: 'could not find a PINNED fireflyiii/core image line — '
              'never use `latest` (DESIGN.md §7 risk table)');

      final pinned = match!.group(1);
      expect(version, equals(pinned),
          reason: 'fixtures were captured from $version but the container '
              'is pinned to $pinned. Re-run '
              'infra/firefly/capture_fixtures.sh after changing the pin.');
    });
  });

  group('golden fixtures — JSON:API envelope', () {
    test('every fixture parses and has a data member', () {
      for (final stem in [
        ..._listFixtures.keys,
        ..._itemFixtures,
        'about',
      ]) {
        final json = _load(stem);
        expect(json.containsKey('data'), isTrue,
            reason: '$stem.json has no `data` member');
      }
    });

    test('collection fixtures carry data[] + pagination', () {
      _listFixtures.forEach((file, stem) {
        final json = _load(file);
        final data = json['data'];
        expect(data, isA<List<dynamic>>(),
            reason: '$file.json `data` must be an array');
        expect(json.containsKey('meta'), isTrue,
            reason: '$file.json has no `meta`');
        final meta = json['meta'] as Map<String, dynamic>;
        expect(meta.containsKey('pagination'), isTrue,
            reason: '$file.json meta has no `pagination` — the app paged '
                'list reads');
        if (_mustBeSeeded.contains(stem)) {
          expect(data as List<dynamic>, isNotEmpty,
              reason: '$file.json came back empty — seed not applied?');
        }
      });
    });

    test('item fixtures carry an object resource with type + id', () {
      for (final stem in _itemFixtures) {
        final data = _resource(stem);
        expect(data['type'], isA<String>());
        expect(data['id'], isA<String>());
        expect(data['attributes'], isA<Map<String, dynamic>>());
      }
    });
  });

  group('transactions contract — fields the app reads', () {
    test('single transaction exposes legs under attributes.transactions', () {
      final attrs = _attrs('transaction_1');

      // DESIGN note: `description` is NOT a group-level attribute on GET —
      // it lives on each leg. Reading it off the group returns null.
      expect(attrs.containsKey('transactions'), isTrue);
      expect(attrs['description'], isNull,
          reason: 'contract quirk: description is per-leg, not per-group');

      final legs = attrs['transactions'] as List<dynamic>;
      expect(legs, isNotEmpty);

      final leg = legs.first as Map<String, dynamic>;
      const requiredLegKeys = [
        'type',
        'amount',
        'date',
        'description',
        'currency_code',
        'currency_decimal_places',
        'source_id',
        'source_name',
        'destination_id',
        'destination_name',
        'transaction_journal_id',
      ];
      for (final key in requiredLegKeys) {
        expect(leg.containsKey(key), isTrue,
            reason: 'transaction leg is missing `$key`');
      }

      const legTypes = [
        'deposit',
        'withdrawal',
        'transfer',
        'reconciliation',
      ];
      expect(leg['type'], anyOf(legTypes));
      // Amount is a STRING, and Firefly returns full float precision
      // (e.g. "2500.000000000000"). The model must parse, not assume,
      // the number of decimal places.
      expect(leg['amount'], isA<String>());
      expect(double.tryParse(leg['amount'] as String), isNotNull,
          reason: 'amount must parse as a decimal string');
      // Date is RFC3339 with an explicit offset.
      expect(DateTime.tryParse(leg['date'] as String), isNotNull);
    });

    test('transaction collection exposes at least one seeded group', () {
      final data = _load('transactions')['data'] as List<dynamic>;
      expect(data, isNotEmpty);
      final first = data.first as Map<String, dynamic>;
      expect(first['type'], 'transactions');
      expect(first['attributes'], isA<Map<String, dynamic>>());
    });
  });

  group('accounts contract — fields the app reads', () {
    test('asset account exposes identity + balance', () {
      final attrs = _attrs('account_1');

      const requiredAccountKeys = [
        'name',
        'type',
        'currency_code',
        'currency_symbol',
        'currency_decimal_places',
        'current_balance',
        'active',
        'account_role',
      ];
      for (final key in requiredAccountKeys) {
        expect(attrs.containsKey(key), isTrue,
            reason: 'account is missing `$key`');
      }

      expect(attrs['type'], 'asset');
      expect(attrs['currency_code'], 'EUR');
      expect(attrs['active'], isA<bool>());
      // Balance is a decimal STRING, not a number.
      expect(attrs['current_balance'], isA<String>());
      expect(double.tryParse(attrs['current_balance'] as String), isNotNull);
    });

    test('list response is paged and typed', () {
      final json = _load('accounts');
      final data = json['data'] as List<dynamic>;
      for (final row in data) {
        final r = row as Map<String, dynamic>;
        expect(r['type'], 'accounts');
        expect(r['id'], isA<String>());
      }
      final meta = json['meta'] as Map<String, dynamic>;
      final pagination = meta['pagination'] as Map<String, dynamic>;
      expect(pagination['total'], isA<int>());
    });
  });

  group('secrets never enter committed fixtures', () {
    // Regression guard. `preferences.json` once captured the live CLI
    // access token: a 32-char hex credential sitting in `attributes.data`
    // of the row whose `attributes.name == "access_token"`. A key-name
    // match missed it because the key was `data`. The capture script now
    // redacts by ROW NAME; this test makes a future regression fail hard.
    test('no fixture contains a raw 32-char hex credential', () {
      final hex = RegExp(r'\b[a-f0-9]{32}\b');
      final dir = Directory(_fixDir);
      expect(dir.existsSync(), isTrue);

      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final text = f.readAsStringSync();
        final match = hex.firstMatch(text);
        expect(match, isNull,
            reason: '${f.path} contains a 32-hex value that looks like a '
                'credential: ${match?.group(0)}');
      }
    });

    test('credential preference rows are redacted', () {
      final prefs = _load('preferences')['data'] as List<dynamic>;
      final sensitive = prefs
          .map((r) => (r as Map<String, dynamic>)['attributes']
              as Map<String, dynamic>)
          .where((a) {
        // `as String?` casts rather than calls, so the linter does not see
        // a method invocation on a `dynamic` target.
        final name = (a['name'] as String? ?? '').toLowerCase();
        return _sensitiveNameMarkers.any(name.contains);
      });

      expect(sensitive, isNotEmpty,
          reason: 'expected access_token/mfa_recovery rows in prefs');

      for (final a in sensitive) {
        expect(a['data'], '<redacted>',
            reason: 'preference `${a["name"]}` leaked its raw value');
      }
    });
  });
}
