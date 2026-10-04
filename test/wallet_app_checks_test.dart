/// A wallet app (Mobile Wallet Adapter) is held to the same buy check as the
/// wallets with no second screen: anything but the reviewed buy is refused
/// on this phone, and the app is never opened for it.
library;

import 'dart:typed_data';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart';
import 'package:chumbucket/features/embedded_wallet/panta_signer_choice.dart';
import 'package:chumbucket/features/embedded_wallet/panta_wallet_app.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/solana.dart' show Ed25519HDKeyPair;

import 'identity_fakes.dart' show kTestPhrase;
import 'identity_panta_embedded_test.dart' show Tx, pantaBuy;

class _WalletApp extends MwaAuthProvider {
  _WalletApp(this.wallet);
  final String? wallet;
  @override
  bool get isAuthenticated => wallet != null;
  @override
  String? get walletAddress => wallet;
}

/// Stands in for the wallet app: fills the owner's slot, or tampers.
class _AppPort implements PantaWalletPort {
  _AppPort({this.tamper = false});
  final bool tamper;
  int asked = 0;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    asked++;
    final signed = Uint8List.fromList(unsigned)..fillRange(1, 65, 7);
    if (tamper) signed[signed.length - 1] ^= 1;
    return signed;
  }
}

Future<String> _account(int n) async =>
    (await Ed25519HDKeyPair.fromPrivateKeyBytes(
      privateKey: List<int>.filled(32, n),
    )).address;

void main() {
  late EmbeddedWalletKey key;
  late String market;
  setUpAll(() async {
    key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
    market = await _account(42);
  });

  PantaWalletPort port(_AppPort inner, {Side side = Side.yes}) =>
      walletAppBuyPort(
        _WalletApp(key.address),
        owner: key.address,
        reviewed: PantaReviewedBuy(
          venueMarketId: market,
          side: side,
          amountBaseUnits: () => '2500000',
        ),
        inner: inner,
      );

  test('the reviewed buy reaches the app; the same bytes come back', () async {
    final inner = _AppPort();
    final unsigned = await pantaBuy(key.address, market);
    final signed = await port(inner).signTransaction(unsigned);
    expect(inner.asked, 1);
    expect(signed.sublist(65), unsigned.sublist(65));
  });

  for (final (name, make) in <(String, Future<Uint8List> Function())>[
    (
      'a different amount',
      () async => pantaBuy(key.address, market, const Tx(amount: 9900000)),
    ),
    (
      'the other side',
      () async => pantaBuy(key.address, market, const Tx(side: Side.no)),
    ),
    (
      'a SOL transfer tucked in',
      () async =>
          pantaBuy(key.address, market, Tx(extraTransferTo: await _account(77))),
    ),
    (
      'a program that is not Panta',
      () async => pantaBuy(
        key.address,
        market,
        const Tx(program: 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA'),
      ),
    ),
    (
      'an inflated priority fee',
      () async => pantaBuy(key.address, market, const Tx(computePrice: 50000000)),
    ),
    (
      'a foreign token account',
      () async =>
          pantaBuy(key.address, market, const Tx(foreignTokenAccount: true)),
    ),
    (
      'a second signer',
      () async =>
          pantaBuy(key.address, market, Tx(secondSigner: await _account(9))),
    ),
    ('another market', () async => pantaBuy(key.address, await _account(43))),
    ('someone else paying', () async => pantaBuy(await _account(8), market)),
    ('garbage', () async => Uint8List.fromList([1, 2, 3])),
  ]) {
    test('never opens the app for $name', () async {
      final inner = _AppPort();
      await expectLater(
        port(inner).signTransaction(await make()),
        throwsA(isA<PantaException>()),
      );
      expect(inner.asked, 0);
    });
  }

  test('an answer that changes the transaction is refused', () async {
    final inner = _AppPort(tamper: true);
    await expectLater(
      port(inner).signTransaction(await pantaBuy(key.address, market)),
      throwsA(
        isA<PantaException>().having(
          (e) => e.code,
          'code',
          PantaErrorCode.signingFailed,
        ),
      ),
    );
  });

  test('the trade path picks the checked wallet-app port', () {
    final choice = choosePantaSigner(
      walletApp: _WalletApp(key.address),
      onPhone: null,
      reviewed: PantaReviewedBuy(
        venueMarketId: market,
        side: Side.yes,
        amountBaseUnits: () => '2500000',
      ),
    );
    expect(choice!.port, isA<CheckedPantaWalletPort>());
  });
}
