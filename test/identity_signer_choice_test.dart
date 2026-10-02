/// Which wallet signs a Panta buy: a connected wallet app first, else the
/// account's on-phone wallet once the server has confirmed it, else none (the
/// caller opens the wallet sheet). The on-phone signer follows the account.
library;

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/panta_mwa_wallet.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart';
import 'package:chumbucket/features/embedded_wallet/panta_signer_choice.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/solana.dart' show Ed25519HDKeyPair;

import 'identity_embedded_wallet_test.dart' show LinkServer, kTestPhraseAddress;
import 'identity_fakes.dart';
import 'identity_panta_embedded_test.dart' show pantaBuy;
import 'session_fakes.dart';

const _walletApp = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';

class _WalletApp extends MwaAuthProvider {
  _WalletApp(this.wallet);
  String? wallet;
  @override
  bool get isAuthenticated => wallet != null;
  @override
  String? get walletAddress => wallet;
}

void main() {
  late String market;
  late MemorySecretStore secrets;
  late EmbeddedWalletController onPhone;

  setUpAll(() async {
    market =
        (await Ed25519HDKeyPair.fromPrivateKeyBytes(
          privateKey: List<int>.filled(32, 42),
        )).address;
  });

  setUp(() {
    secrets = MemorySecretStore();
    onPhone = EmbeddedWalletController(
      vault: EmbeddedWalletVault(store: secrets),
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: LinkServer().server.client,
      ),
      authToken: () async => null,
    );
  });
  tearDown(() => onPhone.dispose());

  Future<void> phoneWallet({required bool linked}) async {
    await EmbeddedWalletVault(store: secrets).save(
      kCanonicalUserId,
      EmbeddedWalletRecord(
        address: kTestPhraseAddress,
        recoveryPhrase: kTestPhrase,
        linked: linked,
        createdAt: DateTime.utc(2026, 10, 2),
      ),
    );
    await onPhone.bind(kCanonicalUserId);
  }

  PantaReviewedBuy reviewed() => PantaReviewedBuy(
    venueMarketId: market,
    side: Side.yes,
    amountBaseUnits: () => '2500000',
  );

  test(
    'a connected wallet app signs, even when a phone wallet exists',
    () async {
      await phoneWallet(linked: true);
      final app = _WalletApp(_walletApp);
      final choice = choosePantaSigner(
        walletApp: app,
        onPhone: onPhone,
        reviewed: reviewed(),
      );
      expect(choice!.kind, PantaSigner.walletApp);
      expect(choice.address, _walletApp);
      expect(choice.port, isA<PantaMwaWallet>());
      app.wallet = null;
      expect(choice.selectedWallet(), isNull);
    },
  );

  test(
    'no wallet app: the linked phone wallet signs the reviewed buy',
    () async {
      await phoneWallet(linked: true);
      final choice = choosePantaSigner(
        walletApp: _WalletApp(null),
        onPhone: onPhone,
        reviewed: reviewed(),
      );
      expect(choice!.kind, PantaSigner.thisPhone);
      expect(choice.address, kTestPhraseAddress);
      expect(choice.selectedWallet(), kTestPhraseAddress);
      final unsigned = await pantaBuy(kTestPhraseAddress, market);
      expect(
        await choice.port.signTransaction(unsigned),
        hasLength(unsigned.length),
      );

      // Signed out between review and signing: nothing is signed.
      await onPhone.bind(null);
      expect(choice.selectedWallet(), isNull);
      await expectLater(
        choice.port.signTransaction(unsigned),
        throwsA(
          isA<PantaException>().having(
            (e) => e.code,
            'code',
            PantaErrorCode.walletChanged,
          ),
        ),
      );
    },
  );

  test('a phone wallet the server has not confirmed never signs', () async {
    await phoneWallet(linked: false);
    // The bind re-proves an unlinked wallet; with no session it stays unlinked.
    await pumpEventQueue();
    expect(onPhone.hasWallet, isTrue);
    expect(onPhone.linked, isFalse);
    expect(
      choosePantaSigner(
        walletApp: _WalletApp(null),
        onPhone: onPhone,
        reviewed: reviewed(),
      ),
      isNull,
    );
  });

  test('no wallet at all, or no wallet feature: none', () {
    expect(
      choosePantaSigner(
        walletApp: _WalletApp(null),
        onPhone: onPhone,
        reviewed: reviewed(),
      ),
      isNull,
    );
    expect(
      choosePantaSigner(walletApp: null, onPhone: null, reviewed: reviewed()),
      isNull,
    );
  });
}
