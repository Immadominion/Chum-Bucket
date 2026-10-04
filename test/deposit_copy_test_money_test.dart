// Crossmint staging (devnet test USDC) never reads as real money: every state
// of a test deposit says so, every time; a mainnet deposit never does.
import 'package:chumbucket/features/deposits/data/deposits_models.dart';
import 'package:chumbucket/features/deposits/presentation/deposit_copy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'deposits_fakes.dart';

const _states = [
  'awaiting_payment',
  'verifying_identity',
  'identity_review',
  'identity_failed',
  'awaiting_wallet_proof',
  'payment_processing',
  'payment_failed',
  'delivering',
  'delivered',
  'delivery_failed',
  'expired',
];

DepositOrder _order(String state, String network) => DepositOrder.fromJson(
  orderJson(
    state: state,
    network: network,
    receive:
        state == 'delivering' || state == 'delivered'
            ? const {'min': '24.21', 'max': '24.21'}
            : const {'min': '24.1', 'max': '24.4'},
    proof: state == 'awaiting_wallet_proof' ? 'Sign this message' : null,
  ),
);

void main() {
  test('every test-money state says test, in its title and its message', () {
    for (final state in _states) {
      final copy = depositStateCopy(_order(state, 'solana-devnet'));
      expect(
        copy.title,
        matches(RegExp('test', caseSensitive: false)),
        reason: state,
      );
      expect(copy.message, contains(kTestMoneyLine), reason: state);
    }
  });

  test('funds added on staging is test USDC, never "USDC is in your wallet"', () {
    final copy = depositStateCopy(_order('delivered', 'solana-devnet'));
    expect(copy.title, 'Test funds added');
    expect(
      copy.message,
      '24.21 devnet test USDC is in your wallet. Test money, not real.',
    );
  });

  test('a mainnet deposit never says test', () {
    for (final state in _states) {
      final copy = depositStateCopy(_order(state, 'solana-mainnet'));
      expect(copy.title, isNot(contains('Test')), reason: state);
      expect(copy.message, isNot(contains(kTestMoneyLine)), reason: state);
    }
    expect(
      depositStateCopy(_order('delivered', 'solana-mainnet')).message,
      '24.21 USDC is in your wallet.',
    );
  });
}
