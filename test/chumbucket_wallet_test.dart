/// The Chumbucket wallet (behind CHUMBUCKET_WALLET_ENABLED): what the server
/// knows comes first, the provider is signed in only on need, the wallet is
/// linked with the same SIWS proof as every wallet (labelled "chumbucket"),
/// and every signature is held to the exact bytes it was asked for.
///
/// [_KeyBackend] is a test double for the provider seam: a real ed25519 key
/// standing in for Privy's enclave. The transactions are real v0 Panta buys.
library;

import 'dart:convert';

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_privy_tokens.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_signers.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_backend.dart';
import 'package:chumbucket/features/chumbucket_wallet/chumbucket_wallet_controller.dart';
import 'package:chumbucket/features/chumbucket_wallet/privy_chumbucket_wallet_backend.dart'
    show privyUserIsAccount;
import 'package:chumbucket/features/chumbucket_wallet/signed_transaction.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart';
import 'package:chumbucket/features/embedded_wallet/panta_signer_choice.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privy_flutter/privy_flutter.dart'
    show
        CustomAuthAccount,
        EmailAccount,
        EmbeddedSolanaWallet,
        Privy,
        PrivyConfig,
        Success;
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

/// A provider double that keeps a session the way Privy does: it can outlive
/// the app (a persisted session for another account), it ends on logout, and
/// every operation refuses once it is not the account [signIn] named.
class _KeyBackend implements ChumbucketWalletBackend {
  _KeyBackend(this.key, {this.hasWallet = false, this.session});
  final EmbeddedWalletKey key;
  bool hasWallet;
  _Answer answer = _Answer.whole;
  final calls = <String>[];

  /// Whose provider session exists right now (persists across "restarts").
  String? session;
  String? _account;
  int signInDelayMs = 0;

  @override
  Future<void> signIn(String account) async {
    calls.add('signIn:$account');
    if (signInDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: signInDelayMs));
    }
    if (session != null && session != account) calls.add('logout');
    session = account;
    _account = account;
  }

  void _requireSession() {
    if (_account == null || session != _account) {
      _account = null;
      throw ChumbucketWalletException.signedOut;
    }
  }

  @override
  Future<String?> wallet() async {
    _requireSession();
    return hasWallet ? key.address : null;
  }

  @override
  Future<String> createWallet() async {
    _requireSession();
    calls.add('createWallet');
    hasWallet = true;
    return key.address;
  }

  @override
  Future<Uint8List> signMessage(String address, Uint8List message) async {
    _requireSession();
    calls.add('signMessage:$session');
    return Uint8List.fromList(await key.sign(message));
  }

  @override
  Future<Uint8List> signTransaction(String address, Uint8List unsigned) async {
    _requireSession();
    calls.add('signTransaction:$session');
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
    session = null;
    _account = null;
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
        await wallet.bind(kCanonicalUserId);
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
        await wallet.bind(kCanonicalUserId);
        expect(wallet.phase, ChumbucketWalletPhase.none);
        expect(wallet.signer, isNull);

        final signer = await wallet.ensure();
        expect(signer.address, key.address);
        expect(backend.session, kCanonicalUserId);
        expect(backend.calls, [
          'signIn:$kCanonicalUserId',
          'createWallet',
          'signMessage:$kCanonicalUserId',
        ]);
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
        await wallet.bind(kCanonicalUserId);
        await wallet.ensure();
        expect(backend.calls, [
          'signIn:$kCanonicalUserId',
          'signMessage:$kCanonicalUserId',
        ]);
        wallet.dispose();
      },
    );

    test(
      'another account: the provider is signed out and the old signer refuses',
      () async {
        final server = _Server(linkedWallet: key.address);
        final backend = _KeyBackend(key, hasWallet: true);
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId);
        final signer = wallet.signer!;
        final unsigned = await pantaBuy(key.address, _market);
        await signer.signTransaction(unsigned);
        expect(backend.session, kCanonicalUserId);

        await wallet.bind('usr_other');
        expect(backend.calls.last, 'signOut');
        await expectLater(
          signer.signTransaction(unsigned),
          throwsA(isA<ChumbucketWalletException>()),
        );
        wallet.dispose();
      },
    );
  });

  group('the provider session follows the account', () {
    test(
      'after a restart, a persisted session for another account is replaced before anything is signed',
      () async {
        final server = _Server(linkedWallet: key.address);
        final backend = _KeyBackend(
          key,
          hasWallet: true,
          session: 'usr_previous',
        );
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId);
        // Showing the wallet needed no provider at all.
        expect(backend.calls, isEmpty);
        final signed = await wallet.signer!.signTransaction(
          await pantaBuy(key.address, _market),
        );
        expect(signed.length, greaterThan(65));
        expect(backend.calls, [
          'signIn:$kCanonicalUserId',
          'logout',
          'signTransaction:$kCanonicalUserId',
        ]);
        expect(
          backend.calls.where((c) => c.endsWith(':usr_previous')),
          isEmpty,
        );
        wallet.dispose();
      },
    );

    test(
      'signing out ends the provider session even if this run never signed in',
      () async {
        final server = _Server(linkedWallet: key.address);
        final backend = _KeyBackend(
          key,
          hasWallet: true,
          session: kCanonicalUserId,
        );
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId);
        await wallet.bind(null);
        expect(backend.calls, ['signOut']);
        expect(backend.session, isNull);
        wallet.dispose();
      },
    );

    test('an app that starts signed out ends a session left behind', () async {
      final backend = _KeyBackend(key, session: 'usr_previous');
      final wallet = controller(_Server(), backend);
      await wallet.bind(null);
      expect(backend.calls, ['signOut']);
      expect(backend.session, isNull);
      wallet.dispose();
    });

    test(
      'another account: signed out first, then signed in as the new one',
      () async {
        final server = _Server(linkedWallet: key.address);
        final backend = _KeyBackend(key, hasWallet: true);
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId);
        await wallet.signer!.signMessage(Uint8List.fromList([1, 2, 3]));
        await wallet.bind('usr_other');
        await wallet.signer!.signMessage(Uint8List.fromList([1, 2, 3]));
        expect(backend.calls, [
          'signIn:$kCanonicalUserId',
          'signMessage:$kCanonicalUserId',
          'signOut',
          'signIn:usr_other',
          'signMessage:usr_other',
        ]);
        wallet.dispose();
      },
    );

    test(
      'a session the provider ended is signed into again once, then signs',
      () async {
        final server = _Server(linkedWallet: key.address);
        final backend = _KeyBackend(key, hasWallet: true);
        final wallet = controller(server, backend);
        await wallet.bind(kCanonicalUserId);
        final signer = wallet.signer!;
        await signer.signMessage(Uint8List.fromList([1]));
        backend.session = null; // expired, or logged out elsewhere
        await signer.signMessage(Uint8List.fromList([2]));
        expect(
          backend.calls.where((c) => c.startsWith('signIn')),
          hasLength(2),
        );
        wallet.dispose();
      },
    );

    test('concurrent signatures share one sign-in', () async {
      final server = _Server(linkedWallet: key.address);
      final backend = _KeyBackend(key, hasWallet: true)..signInDelayMs = 20;
      final wallet = controller(server, backend);
      await wallet.bind(kCanonicalUserId);
      final signer = wallet.signer!;
      await Future.wait([
        signer.signMessage(Uint8List.fromList([1])),
        signer.signMessage(Uint8List.fromList([2])),
        signer.signMessage(Uint8List.fromList([3])),
      ]);
      expect(backend.calls.where((c) => c.startsWith('signIn')), hasLength(1));
      wallet.dispose();
    });

    test('Privy users are matched to the account by the custom-auth id', () {
      expect(
        privyUserIsAccount([
          EmailAccount(emailAddress: 'a@b.c'),
          CustomAuthAccount(customUserId: kCanonicalUserId),
        ], kCanonicalUserId),
        isTrue,
      );
      expect(
        privyUserIsAccount([
          CustomAuthAccount(customUserId: 'usr_previous'),
        ], kCanonicalUserId),
        isFalse,
      );
      expect(privyUserIsAccount(const [], kCanonicalUserId), isFalse);
    });
  });

  group('the account token for Privy', () {
    String jwt(String sub) =>
        'eyJhbGciOiJFUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode({'sub': sub}))).replaceAll('=', '')}.c2ln';

    ({
      FakeBffServer server,
      ChumbucketPrivyTokens tokens,
      List<int> mints,
      void Function(Duration) advance,
    })
    rig({String Function()? sub}) {
      var now = DateTime.utc(2026, 10, 4, 12);
      final mints = <int>[];
      final server = FakeBffServer((request) {
        if (request.procedurePath != 'wallet.privyToken') {
          return errorResponse(
            code: 'NOT_FOUND',
            httpStatus: 404,
            message: 'nope',
          );
        }
        mints.add(1);
        return okResponse({
          'token': jwt(sub?.call() ?? kCanonicalUserId),
          'expiresAt':
              now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
        });
      });
      final tokens = ChumbucketPrivyTokens(
        bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
        authToken: () async => kAccessToken,
        now: () => now,
      );
      return (
        server: server,
        tokens: tokens,
        mints: mints,
        advance: (d) => now = now.add(d),
      );
    }

    test(
      'minted for the bound account, held until a minute before expiry',
      () async {
        final r = rig();
        expect(await r.tokens.current(), isNull); // no account yet
        r.tokens.bind(kCanonicalUserId);
        final first = await r.tokens.current();
        expect(ChumbucketPrivyTokens.subjectOf(first!), kCanonicalUserId);
        expect(await r.tokens.current(), first);
        expect(r.mints, hasLength(1));
        r.advance(const Duration(minutes: 9, seconds: 1));
        await r.tokens.current();
        expect(r.mints, hasLength(2));
        // The BFF's own bearer is the session token; it never reaches Privy.
        expect(
          r.server.lastRequest.headers['authorization'],
          'Bearer $kAccessToken',
        );
      },
    );

    test(
      'another account drops the held token; a token for anyone else is never handed out',
      () async {
        var sub = kCanonicalUserId;
        final r = rig(sub: () => sub);
        r.tokens.bind(kCanonicalUserId);
        await r.tokens.current();
        r.tokens.bind('usr_other');
        sub = kCanonicalUserId; // a stale or wrong answer
        expect(await r.tokens.current(), isNull);
        sub = 'usr_other';
        expect(
          ChumbucketPrivyTokens.subjectOf((await r.tokens.current())!),
          'usr_other',
        );
        r.tokens.bind(null);
        expect(await r.tokens.current(), isNull);
      },
    );
  });

  group('the Privy method channel', () {
    const channel = MethodChannel('privy_flutter');
    const authState = MethodChannel('privy_flutter/authState');
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMethodCallHandler(authState, null);
    });

    test(
      'a transaction reaches the platform as a plain list of byte values',
      () async {
        Object? sent;
        messenger.setMockMethodCallHandler(authState, (_) async => null);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'solanaSignTransaction') return null;
          sent = (call.arguments as Map)['transaction'];
          return base64Encode([9, 9, 9]);
        });
        // The SDK's own start-up (its logger), against the mocked platform.
        Privy.init(config: PrivyConfig(appId: 'app', appClientId: 'client'));
        final unsigned = Uint8List.fromList([1, 2, 255, 0]);
        final result = await EmbeddedSolanaWallet(
          address: key.address,
          hdWalletIndex: 0,
        ).provider.signTransaction(unsigned);
        expect(result, isA<Success<String>>());
        // Swift casts `args["transaction"] as? [UInt8]` and Kotlin reads
        // `List<Int>`: both need a plain list, which a typed Uint8List is not.
        expect(sent, isA<List<Object?>>());
        expect(sent, isNot(isA<Uint8List>()));
        expect(sent, [1, 2, 255, 0]);
      },
    );
  });

  group('signing a Panta buy', () {
    Future<(ChumbucketWalletController, _KeyBackend)> ready() async {
      final server = _Server(linkedWallet: key.address);
      final backend = _KeyBackend(key, hasWallet: true);
      final wallet = controller(server, backend);
      await wallet.bind(kCanonicalUserId);
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
      expect(
        backend.calls.where((c) => c.startsWith('signTransaction')),
        isEmpty,
      );
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
        await wallet.bind(kCanonicalUserId);
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
