// R29 regression pin: an account created with an opening balance but no
// opening-balance date must still be pushable.
//
// Firefly III rejects `opening_balance` without `opening_balance_date`:
//   "The opening balance date field is required when opening balance is
//    present."
// The form's date picker starts empty, so the account row carried a balance
// and a NULL date, `Account.toJsonApi` omitted the date, and every push failed
// with a 422. Because a failed op stops the push batch, the stuck create also
// blocked everything queued behind it.

import 'package:firefly_mobile/ui/configs/entity_configs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final writtenAt = DateTime.utc(2026, 11, 18, 9, 30);

  Map<String, Object?> values({String? balance, DateTime? date}) => {
    'name': 'MOBILE_TEST_3_GBP',
    'type': 'asset',
    'accountRole': 'defaultAsset',
    'currencyCode': 'GBP',
    if (balance != null) 'openingBalance': balance,
    if (date != null) 'openingBalanceDate': date,
  };

  test('a balance without a date defaults to the write day', () {
    final account = accountsConfig.createWith(
      values(balance: '200'),
      id: 'local-1',
      updatedAt: writtenAt,
      seq: 1,
    );

    expect(account.openingBalance, '200');
    expect(account.openingBalanceDate, isNotNull);
    // The push payload carries it, which is what the server demands.
    final payload = account.toJsonApi();
    final attributes = payload['attributes'] as Map<String, dynamic>;
    expect(attributes['opening_balance'], '200');
    expect(attributes['opening_balance_date'], isNotNull);
  });

  test('a chosen date is kept as-is', () {
    final chosen = DateTime.utc(2026, 10, 1);
    final account = accountsConfig.createWith(
      values(balance: '50', date: chosen),
      id: 'local-2',
      updatedAt: writtenAt,
      seq: 2,
    );
    expect(account.openingBalanceDate, chosen);
  });

  test('no balance means no invented date', () {
    final account = accountsConfig.createWith(
      values(),
      id: 'local-3',
      updatedAt: writtenAt,
      seq: 3,
    );
    expect(account.openingBalanceDate, isNull);
  });

  test('a zero balance does not force a date', () {
    final account = accountsConfig.createWith(
      values(balance: '0'),
      id: 'local-4',
      updatedAt: writtenAt,
      seq: 4,
    );
    expect(account.openingBalanceDate, isNull);
  });
}
