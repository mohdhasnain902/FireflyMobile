import 'package:firefly_mobile/core/settings/connection_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-function tests for [normalizeBaseUrl] (P2.4 URL validation).
void main() {
  test('trims whitespace and drops any pasted path/query', () {
    expect(
      normalizeBaseUrl('  https://firefly.example.com/subpath/?a=1  '),
      'https://firefly.example.com',
    );
  });

  test('keeps a non-default port, drops the default 80/443', () {
    expect(normalizeBaseUrl('https://firefly.example.com:8443'), 'https://firefly.example.com:8443');
    expect(normalizeBaseUrl('https://firefly.example.com:443'), 'https://firefly.example.com');
    expect(normalizeBaseUrl('http://firefly.example.com:80'), 'http://firefly.example.com');
  });

  test('rejects empty, scheme-less, and non-http schemes', () {
    expect(normalizeBaseUrl(''), isNull);
    expect(normalizeBaseUrl('   '), isNull);
    expect(normalizeBaseUrl('firefly.example.com'), isNull);
    expect(normalizeBaseUrl('ftp://firefly.example.com'), isNull);
  });

  test('rejects values containing internal whitespace', () {
    expect(normalizeBaseUrl('https://fire fly.example.com'), isNull);
  });

  test('rejects a host with no authority', () {
    expect(normalizeBaseUrl('https://'), isNull);
  });
}
