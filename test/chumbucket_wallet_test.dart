/// The Chumbucket wallet (behind CHUMBUCKET_WALLET_ENABLED): what the server
/// knows comes first, the provider is signed in only on need, the wallet is
/// linked with the same SIWS proof as every wallet (labelled "chumbucket"),
/// and every signature is held to the exact bytes it was asked for.
///
/// [_KeyBackend] is a test double for the provider seam: a real ed25519 key
/// standing in for Privy's enclave. The transactions are real v0 Panta buys.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_signers.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_backend.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_controller.dart';
import 'package:chumbucket/features/chumbucket_wallet/signed_transaction.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart';
import 'package:chumbucket/features/embedded_wallet/panta_signer_choice.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart' show Ed25519HDPublicKey, verifySignature;

import 'bff_calls_fixtures.dart';
import 'identity_embedded_wallet_test.dart' show linkNonceFor;
import 'identity_fakes.dart' show kTestPhrase;
import 'identity_panta_embedded_test.dart' show Tx, pantaBuy;
import 'session_fakes.dart';

const _market = '6yEBmxJu2oWdubFVKZshVVUpLLsXd61csSfmf8y4Qtwd';

/// How the double answers a transaction: as Privy's SDK documents it (the
/// whole signed transaction), as a bare signature, or tampered.
enum _Answer { whole, bare, rewritten }

class _KeyBackend implements ChumbucketWalletBackend {
  _KeyBackend(this.key, {this.hasWallet = false});
  final EmbeddedWalletKey key;
  bool hasWallet;
  _Answer answer = _Answer.whole;
  final calls = <String>[];
  String? signedInAs;

  @override
  Future<void> signIn(String authUserId) async {
    calls.add('signIn');
    signedInAs = authUserId;
  }

  @override
  Future<String?> wallet() async => hasWallet ? key.address : null;

  @override
  Future<String> createWallet() async {
    calls.add('createWallet');
    hasWallet = true;
    return key.address;
  }

  @override
  Future<Uint8List> signMessage(String address, Uint8List message) async {
    calls.add('signMessage');
    return Uint8List.fromList(await key.sign(message));
  }

  @override
  Future<Uint8List> signTransaction(String address, Uint8List unsigned) async {
    calls.add('signTransaction');
    final signature = await key.sign(signatureMessage(unsigned));
    switch (answer) {
      case _Answer.bare:
        return Uint8List.fromList(signature);
      case _Answer.whole:
        return Uint8List.fromList(unsigned)..setRange(1, 65, signature);
      case _Answer.rewritten:
        final tampered = Uint8List.fromList(unsigned)
          ..setRange(1, 65, signature);
        tampered[tampered.length - 1] ^= 1;
        return tampered;
    }
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    signedInAs = null;
  }
}

Uint8List signatureMessage(Uint8List tx) =>
    tx.sublist(signatureSection(tx).messageOffset);

/// A BFF that knows which Chumbucket wallet the account has linked, and links
/// one by verifying the SIWS signature, as `auth.linkWallet` does.
class _Server {
  _Server({this.linkedWallet});
  String? linkedWallet;
  String? lastWalletType;

  late final FakeBffServer server = FakeBffServer((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final input = body['json'] as Map<String, dynamic>? ?? const {};
    switch (request.procedurePath) {
      case 'wallet.status':
        return okResponse({
          'enabled': true,
          'account': {'tradingWallet': null, 'chumbucketWallet': linkedWallet},
        });
      case 'auth.requestWalletNonce':
        return okResponse(linkNonceFor(input['address'] as String));
      case 'auth.linkWallet':
        lastWalletType = input['walletType'] as String?;
        linkedWallet = input['address'] as String;
        return okResponse({
          'userId': kCanonicalUserId,
          'address': input['address'],
          'outcome': 'linked',
          'proofVersion': 1,
        });
    }
    return errorResponse(code: 'NOT_FOUND', httpStatus: 404, message: 'nope');
  });

  Future<bool> linkSignatureVerifies() async {
    final request = server.requestFor('auth.linkWallet');
    final input =
        (jsonDecode(request.body) as Map<String, dynamic>)['json']
            as Map<String, dynamic>;
    return verifySignature(
      message: utf8.encode(input['message'] as String),
      signature: base58decode(input['signature'] as String),
      publicKey: Ed25519HDPublicKey.fromBase58(input['address'] as String),
    );
  }
}

void main() {
  late EmbeddedWalletKey key;
  setUpAll(() async {
    key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
  });

  ChumbucketWalletController controller(_Server server, _KeyBackend backend) =>
      ChumbucketWalletController(
        backend: backend,
        bff: SessionBffClient(
          baseUrl: kSessionBase,
          httpClient: server.server.client,
        ),
        authToken: () async => kAccessToken,
      );

  group('signed bytes', () {
    test(
      'the whole signed transaction or a bare signature, nothing else',
      () async {
        final unsigned = await pantaBuy(key.address, _market);
        final signature = await key.sign(signatureMessage(unsigned));
        final whole = Uint8List.fromList(unsigned)..setRange(1, 65, signature);
        expect(adoptSignerAnswer(unsigned, whole), whole);
        expect(
          adoptSignerAnswer(unsigned, Uint8List.fromList(signature)),
          whole,
        );
        // Unsigned, a changed message, a wrong slot, a short answer: refused.
        expect(
          () => adoptSignerAnswer(unsigned, unsigned),
          throwsA(isA<SignedTransactionMismatch>()),
        );
        final changed = Uint8List.fromList(whole)..[whole.length - 1] ^= 1;
        expect(
          () => adoptSignerAnswer(unsigned, changed),
          throwsA(isA<SignedTransactionMismatch>()),
        );
        expect(
          () => adoptSignerAnswer(unsigned, whole, slot: 1),
          throwsA(isA<SignedTransactionMismatch>()),
        );
        expect(
          () => adoptSignerAnswer(unsigned, whole.sublist(0, whole.length - 1)),
          throwsA(isA<SignedTransactionMismatch>()),
        );
      },
    );
  });

  group('the wallet for the account', () {
    test(
      'a returning account reads its linked wallet from the server alone',
      () async {
        final server = _Server(linkedWallet: key.address);
        final backend = _KeyBackend(key, hasWallet: true);
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId, kAuthUserId);
        expect(wallet.phase, ChumbucketWalletPhase.ready);
        expect(wallet.address, key.address);
        expect(wallet.signer?.address, key.address);
        // No provider session just to show a wallet.
        expect(backend.calls, isEmpty);
        wallet.dispose();
      },
    );

    test(
      'first need: signed in as this account, made, then linked as "chumbucket"',
      () async {
        final server = _Server();
        final backend = _KeyBackend(key);
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId, kAuthUserId);
        expect(wallet.phase, ChumbucketWalletPhase.none);
        expect(wallet.signer, isNull);

        final signer = await wallet.ensure();
        expect(signer.address, key.address);
        expect(backend.signedInAs, kAuthUserId);
        expect(backend.calls, ['signIn', 'createWallet', 'signMessage']);
        expect(server.lastWalletType, 'chumbucket');
        expect(await server.linkSignatureVerifies(), isTrue);
        expect(wallet.phase, ChumbucketWalletPhase.ready);
        wallet.dispose();
      },
    );

    test(
      'a wallet made on another device is linked here, never made twice',
      () async {
        final server = _Server();
        final backend = _KeyBackend(key, hasWallet: true);
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId, kAuthUserId);
        await wallet.ensure();
        expect(backend.calls, ['signIn', 'signMessage']);
        wallet.dispose();
      },
    );

    test(
      'another account: the provider is signed out and the old signer refuses',
      () async {
        final server = _Server(linkedWallet: key.address);
        final backend = _KeyBackend(key, hasWallet: true);
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId, kAuthUserId);
        final signer = wallet.signer!;
        final unsigned = await pantaBuy(key.address, _market);
        await signer.signTransaction(unsigned);
        expect(backend.signedInAs, kAuthUserId);

        await wallet.bind('usr_other', 'auth-other');
        expect(backend.calls.last, 'signOut');
        await expectLater(
          signer.signTransaction(unsigned),
          throwsA(isA<ChumbucketWalletException>()),
        );
        wallet.dispose();
      },
    );
  });

  group('signing a Panta buy', () {
    Future<(ChumbucketWalletController, _KeyBackend)> ready() async {
      final server = _Server(linkedWallet: key.address);
      final backend = _KeyBackend(key, hasWallet: true);
      final wallet = controller(server, backend);
      await wallet.bind(kCanonicalUserId, kAuthUserId);
      return (wallet, backend);
    }

    PantaChumbucketWallet port(ChumbucketWalletController wallet) =>
        PantaChumbucketWallet(
          signer: () => wallet.signer,
          address: key.address,
          reviewed: PantaReviewedBuy(
            venueMarketId: _market,
            side: Side.yes,
            amountBaseUnits: () => '2500000',
          ),
        );

    test('the exact reviewed buy, signed in the owner slot', () async {
      for (final answer in [_Answer.whole, _Answer.bare]) {
        final (wallet, backend) = await ready();
        backend.answer = answer;
        final unsigned = await pantaBuy(key.address, _market);
        final signed = await port(wallet).signTransaction(unsigned);
        expect(signed.sublist(65), unsigned.sublist(65));
        expect(
          await verifySignature(
            message: signatureMessage(unsigned),
            signature: signed.sublist(1, 65),
            publicKey: Ed25519HDPublicKey.fromBase58(key.address),
          ),
          isTrue,
        );
        wallet.dispose();
      }
    });

    test('anything but the reviewed buy never reaches the wallet', () async {
      final (wallet, backend) = await ready();
      for (final bad in [
        await pantaBuy(key.address, _market, const Tx(amount: 9900000)),
        await pantaBuy(key.address, _market, const Tx(side: Side.no)),
        await pantaBuy(
          key.address,
          _market,
          const Tx(
            extraTransferTo: '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T',
          ),
        ),
      ]) {
        await expectLater(
          port(wallet).signTransaction(bad),
          throwsA(
            isA<PantaException>().having(
              (e) => e.code,
              'code',
              PantaErrorCode.invalidResponse,
            ),
          ),
        );
      }
      expect(backend.calls.where((c) => c == 'signTransaction'), isEmpty);
      wallet.dispose();
    });

    test('a wallet that rewrote the transaction is refused', () async {
      final (wallet, backend) = await ready();
      backend.answer = _Answer.rewritten;
      await expectLater(
        port(wallet).signTransaction(await pantaBuy(key.address, _market)),
        throwsA(
          isA<PantaException>().having(
            (e) => e.code,
            'code',
            PantaErrorCode.signingFailed,
          ),
        ),
      );
      wallet.dispose();
    });
  });

  group('who signs', () {
    final reviewed = PantaReviewedBuy(
      venueMarketId: _market,
      side: Side.yes,
      amountBaseUnits: () => '2500000',
    );

    test(
      'the Chumbucket wallet by default once linked, nothing before',
      () async {
        final server = _Server();
        final wallet = controller(server, _KeyBackend(key));
        await wallet.bind(kCanonicalUserId, kAuthUserId);
        expect(
          choosePantaSigner(
            walletApp: null,
            onPhone: null,
            chumbucket: wallet,
            reviewed: reviewed,
          ),
          isNull,
        );
        await wallet.ensure();
        final choice =
            choosePantaSigner(
              walletApp: null,
              onPhone: null,
              chumbucket: wallet,
              reviewed: reviewed,
            )!;
        expect(choice.kind, PantaSigner.chumbucket);
        expect(choice.address, key.address);
        expect(choice.selectedWallet(), key.address);
        // Asked for the wallet app with none connected: nothing, never this one.
        expect(
          choosePantaSigner(
            walletApp: null,
            onPhone: null,
            chumbucket: wallet,
            reviewed: reviewed,
            useWalletApp: true,
          ),
          isNull,
        );
        wallet.dispose();
      },
    );

    test('flag off: no Chumbucket wallet, the old order is unchanged', () {
      expect(
        choosePantaSigner(walletApp: null, onPhone: null, reviewed: reviewed),
        isNull,
      );
      expect(chumbucketWalletIds(enabled: false, values: const {}), isNull);
      expect(
        chumbucketWalletIds(
          enabled: true,
          values: const {'CHUMBUCKET_PRIVY_APP_ID': 'app'},
        ),
        isNull,
      );
      expect(
        chumbucketWalletIds(
          enabled: true,
          values: const {
            'CHUMBUCKET_PRIVY_APP_ID': 'app',
            'CHUMBUCKET_PRIVY_CLIENT_ID': 'client',
          },
        ),
        ('app', 'client'),
      );
    });
  });

  test(
    'an unlinked signing wallet is its own error, icon-led in the sheet',
    () {
      expect(
        const PantaException(PantaErrorCode.walletNotLinked).message,
        'Link this wallet first.',
      );
    },
  );
}
