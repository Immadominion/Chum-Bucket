/// The wallet that lives on the phone, for Google/X accounts with no wallet
/// app: the key, its per-account storage, the encrypted backup, and linking
/// it to the account through the server's existing SIWS link flow.
library;

import 'dart:convert';

import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/wallet_link_proof.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart' show Ed25519HDPublicKey, verifySignature;

import 'bff_calls_fixtures.dart';
import 'identity_fakes.dart';
import 'session_fakes.dart';

/// Phantom / Solflare's first account for [kTestPhrase] (m/44'/501'/0'/0').
const kTestPhraseAddress = 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk';

String _iso(DateTime t) => t.toUtc().toIso8601String();

/// What `auth.requestWalletNonce` answers, built exactly like the BFF's
/// `buildSiwsMessage` for purpose link_wallet.
Map<String, Object?> linkNonceFor(
  String address, {
  DateTime? issued,
  String statement = walletLinkStatement,
  String purpose = 'link_wallet',
  String network = 'devnet',
  String domain = 'chumbucket.fun',
}) {
  final at = (issued ?? DateTime.now().toUtc()).toUtc();
  final issuedAt = _iso(
    DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch, isUtc: true),
  );
  final expiresAt = _iso(
    DateTime.parse(issuedAt).add(const Duration(minutes: 5)),
  );
  final message = [
    '$domain wants you to sign in with your Solana account:',
    address,
    '',
    statement,
    '',
    'URI: https://chumbucket.fun',
    'Version: 1',
    'Chain ID: ${siwsChainId(network) ?? 'solana:unknown'}',
    'Nonce: ${'ab' * 32}',
    'Issued At: $issuedAt',
    'Expiration Time: $expiresAt',
    'Resources:',
    '- chumbucket:purpose:$purpose',
  ].join('\n');
  return {
    'message': message,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'domain': domain,
    'uri': 'https://chumbucket.fun',
    'network': network,
    'purpose': purpose,
    'proofVersion': 1,
  };
}

/// A fake BFF that issues a link challenge and verifies the signature over
/// it, as `WalletLinkService.linkWallet` does.
class LinkServer {
  LinkServer();
  final linked = <String>[];
  bool refuseLink = false;
  String? lastWalletType;

  late final FakeBffServer server = FakeBffServer((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final input = body['json'] as Map<String, dynamic>;
    switch (request.procedurePath) {
      case 'auth.requestWalletNonce':
        return okResponse(linkNonceFor(input['address'] as String));
      case 'auth.linkWallet':
        if (refuseLink) {
          return errorResponse(
            code: 'CONFLICT',
            httpStatus: 409,
            message: 'WALLET_OWNED_BY_ANOTHER_USER',
          );
        }
        lastWalletType = input['walletType'] as String?;
        linked.add(input['address'] as String);
        return okResponse({
          'userId': kCanonicalUserId,
          'address': input['address'],
          'outcome': 'linked',
          'proofVersion': 1,
        });
    }
    return errorResponse(code: 'NOT_FOUND', httpStatus: 404, message: 'nope');
  });

  /// The signature sent with the last link, checked against its message.
  Future<bool> lastSignatureVerifies() async {
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
  group('the key', () {
    test(
      'a recovery phrase opens the same wallet Phantom and Solflare do',
      () async {
        final key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
        expect(key.address, kTestPhraseAddress);
        // Spacing and case are forgiven.
        final sloppy = await EmbeddedWalletKey.fromRecoveryPhrase(
          '  ${kTestPhrase.toUpperCase().replaceAll(' ', '   ')}\n',
        );
        expect(sloppy.address, kTestPhraseAddress);
      },
    );

    test('a wrong word or a bad checksum is refused', () async {
      for (final bad in [
        kTestPhrase.replaceFirst('about', 'abandon'),
        'not a recovery phrase at all',
        kTestPhrase.split(' ').take(11).join(' '),
      ]) {
        await expectLater(
          EmbeddedWalletKey.fromRecoveryPhrase(bad),
          throwsA(isA<EmbeddedWalletException>()),
        );
      }
    });

    test('a new wallet is a fresh 12-word phrase each time', () async {
      final a = await EmbeddedWalletKey.generate();
      final b = await EmbeddedWalletKey.generate();
      expect(a.recoveryPhrase.split(' '), hasLength(12));
      expect(a.address, isNot(b.address));
    });

    test(
      'signs exactly the message, verifiably, and never prints its secret',
      () async {
        final key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
        final message = utf8.encode('hello');
        final signature = await key.sign(message);
        expect(signature, hasLength(64));
        expect(
          await verifySignature(
            message: message,
            signature: signature,
            publicKey: Ed25519HDPublicKey.fromBase58(key.address),
          ),
          isTrue,
        );
        expect('$key', isNot(contains('abandon')));
        expect('$key', contains(key.address));
      },
    );

    test('exports the 64-byte private key wallets import', () async {
      final key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
      final exported = base58decode(await key.exportPrivateKey());
      expect(exported, hasLength(64));
      // The second half is the public key.
      expect(base58encode(exported.sublist(32)), key.address);
    });
  });

  group('the vault', () {
    test(
      'one wallet per account: another account on this phone sees none',
      () async {
        final store = MemorySecretStore();
        final vault = EmbeddedWalletVault(store: store);
        final record = EmbeddedWalletRecord(
          address: kTestPhraseAddress,
          recoveryPhrase: kTestPhrase,
          linked: true,
          createdAt: DateTime.utc(2026, 10, 2),
        );
        await vault.save('person-a', record);
        expect((await vault.load('person-a'))?.address, kTestPhraseAddress);
        expect(await vault.load('person-b'), isNull);
        expect(
          store.values.keys.single,
          'embedded_wallet_v1_person-a',
          reason: 'keyed by the canonical account, never by device',
        );
        expect('$record', isNot(contains('abandon')));
      },
    );

    test('a save that does not read back is not reported saved', () async {
      final store = MemorySecretStore()..corruptReads = true;
      final vault = EmbeddedWalletVault(store: store);
      await expectLater(
        vault.save(
          'person-a',
          EmbeddedWalletRecord(
            address: kTestPhraseAddress,
            recoveryPhrase: kTestPhrase,
            linked: false,
            createdAt: DateTime.utc(2026),
          ),
        ),
        throwsA(isA<EmbeddedWalletStorageException>()),
      );
    });

    test(
      'after a reinstall the key comes back from the encrypted backup',
      () async {
        final blockStore = MemoryBlockStore();
        final continuity = SessionContinuity(
          store: blockStore,
          adopt: (_) async => SessionAdoption.rejected,
          localSession: () async => null,
        );
        expect(
          await continuity.backupWalletSecret('person-a', kTestPhrase),
          WalletBackupOutcome.backedUp,
        );
        // A fresh install: empty secure storage, same Block Store.
        final vault = EmbeddedWalletVault(
          store: MemorySecretStore(),
          continuity: continuity,
        );
        final restored = await vault.load('person-a');
        expect(restored?.address, kTestPhraseAddress);
        expect(restored?.restoredFromBackup, isTrue);
        expect(restored?.linked, isFalse, reason: 're-proven to the server');
        expect(await vault.load('person-b'), isNull);
      },
    );
  });

  group('linking through the existing SIWS flow', () {
    test('a well-formed challenge parses; a tampered one is never signed', () {
      final good = linkNonceFor(kTestPhraseAddress);
      expect(
        WalletLinkProof.parse(good, address: kTestPhraseAddress).message,
        good['message'],
      );
      for (final bad in [
        linkNonceFor(kTestPhraseAddress, statement: 'Send all your USDC.'),
        linkNonceFor(kTestPhraseAddress, purpose: 'transfer_wallet'),
        linkNonceFor(kTestPhraseAddress, domain: 'evil.example'),
        linkNonceFor(kTestPhraseAddress, network: 'testnet'),
        linkNonceFor('11111111111111111111111111111111'),
        linkNonceFor(
          kTestPhraseAddress,
          issued: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        ),
      ]) {
        expect(
          () => WalletLinkProof.parse(bad, address: kTestPhraseAddress),
          throwsA(isA<SessionException>()),
        );
      }
      expect(
        '${WalletLinkProof.parse(good, address: kTestPhraseAddress)}',
        isNot(contains('Nonce')),
      );
    });

    EmbeddedWalletController controllerFor(
      LinkServer link, {
      MemorySecretStore? store,
      SessionContinuity? continuity,
      String? token = kAccessToken,
    }) => EmbeddedWalletController(
      vault: EmbeddedWalletVault(
        store: store ?? MemorySecretStore(),
        continuity: continuity,
      ),
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: link.server.client,
      ),
      authToken: () async => token,
      generate: () => EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase),
    );

    test(
      'create: saved on the phone first, backed up encrypted, then linked as embedded',
      () async {
        final link = LinkServer();
        final store = MemorySecretStore();
        final blockStore = MemoryBlockStore();
        final continuity = SessionContinuity(
          store: blockStore,
          adopt: (_) async => SessionAdoption.rejected,
          localSession: () async => null,
        );
        final wallet = controllerFor(
          link,
          store: store,
          continuity: continuity,
        );
        addTearDown(wallet.dispose);
        await wallet.bind(kCanonicalUserId);
        expect(wallet.phase, EmbeddedWalletPhase.none);
        expect(wallet.signer, isNull);

        await wallet.create();
        expect(wallet.address, kTestPhraseAddress);
        expect(wallet.linked, isTrue);
        expect(wallet.signer?.address, kTestPhraseAddress);
        expect(wallet.backup, WalletBackupOutcome.backedUp);
        expect(blockStore.cloudBackup[SessionContinuity.walletsKey], isTrue);
        expect(link.linked, [kTestPhraseAddress]);
        expect(link.lastWalletType, 'embedded');
        expect(await link.lastSignatureVerifies(), isTrue);
        // The phrase is in secure storage, linked, under this account only.
        final stored = EmbeddedWalletRecord.decode(
          store.values[EmbeddedWalletVault.keyFor(kCanonicalUserId)],
        );
        expect(stored?.linked, isTrue);
        // Neither the phrase nor the private key went to the server.
        for (final request in link.server.received) {
          expect(request.body, isNot(contains('abandon')));
          expect(request.url.toString(), isNot(contains(kAccessToken)));
        }
      },
    );

    test('no screen lock: not backed up, and the sheet can say so', () async {
      final link = LinkServer();
      final continuity = SessionContinuity(
        store: MemoryBlockStore(endToEndEncrypted: false),
        adopt: (_) async => SessionAdoption.rejected,
        localSession: () async => null,
      );
      final wallet = controllerFor(link, continuity: continuity);
      addTearDown(wallet.dispose);
      await wallet.bind(kCanonicalUserId);
      await wallet.create();
      expect(wallet.backup, WalletBackupOutcome.notEncrypted);
    });

    test(
      'a refused link keeps the wallet on the phone, unlinked, with the reason',
      () async {
        final link = LinkServer()..refuseLink = true;
        final store = MemorySecretStore();
        final wallet = controllerFor(link, store: store);
        addTearDown(wallet.dispose);
        await wallet.bind(kCanonicalUserId);
        await wallet.create();
        expect(wallet.hasWallet, isTrue);
        expect(wallet.linked, isFalse);
        expect(
          wallet.signer,
          isNull,
          reason: 'no trades until the server agrees',
        );
        expect(wallet.error, contains('another Chumbucket account'));
        expect(store.values, isNotEmpty, reason: 'the key is never discarded');
      },
    );

    test('a key that cannot be saved is never linked or used', () async {
      final link = LinkServer();
      final wallet = controllerFor(
        link,
        store: MemorySecretStore()..failWrites = true,
      );
      addTearDown(wallet.dispose);
      await wallet.bind(kCanonicalUserId);
      await wallet.create();
      expect(wallet.hasWallet, isFalse);
      expect(wallet.error, contains('Nothing was created'));
      expect(link.server.received, isEmpty);
    });

    test(
      'signed out, or another account: nothing of this wallet is reachable',
      () async {
        final link = LinkServer();
        final store = MemorySecretStore();
        final wallet = controllerFor(link, store: store);
        addTearDown(wallet.dispose);
        await wallet.bind(kCanonicalUserId);
        await wallet.create();
        await wallet.bind(null);
        expect(wallet.address, isNull);
        expect(wallet.signer, isNull);
        expect(wallet.revealRecoveryPhrase(), isNull);
        await wallet.bind('someone-else');
        expect(wallet.phase, EmbeddedWalletPhase.none);
        // The owner signs back in: the same wallet, still linked.
        await wallet.bind(kCanonicalUserId);
        expect(wallet.address, kTestPhraseAddress);
        expect(wallet.linked, isTrue);
      },
    );

    test(
      'importing a recovery phrase puts that wallet on the phone and links it',
      () async {
        final link = LinkServer();
        final wallet = EmbeddedWalletController(
          vault: EmbeddedWalletVault(store: MemorySecretStore()),
          bff: SessionBffClient(
            baseUrl: kSessionBase,
            httpClient: link.server.client,
          ),
          authToken: () async => kAccessToken,
        );
        addTearDown(wallet.dispose);
        await wallet.bind(kCanonicalUserId);
        await wallet.importRecoveryPhrase('not twelve words');
        expect(wallet.hasWallet, isFalse);
        expect(wallet.error, EmbeddedWalletException.invalidPhrase.message);
        await wallet.importRecoveryPhrase(kTestPhrase);
        expect(wallet.address, kTestPhraseAddress);
        expect(wallet.linked, isTrue);
        expect(wallet.revealRecoveryPhrase(), kTestPhrase);
        expect(await wallet.exportPrivateKey(), isNotEmpty);
      },
    );

    test(
      'a phrase the server refuses is not stored: no wallet the account can never link',
      () async {
        final link = LinkServer()..refuseLink = true;
        final store = MemorySecretStore();
        final blockStore = MemoryBlockStore();
        final wallet = controllerFor(
          link,
          store: store,
          continuity: SessionContinuity(
            store: blockStore,
            adopt: (_) async => SessionAdoption.rejected,
            localSession: () async => null,
          ),
        );
        addTearDown(wallet.dispose);
        await wallet.bind(kCanonicalUserId);
        await wallet.importRecoveryPhrase(kTestPhrase);
        expect(wallet.hasWallet, isFalse);
        expect(wallet.phase, EmbeddedWalletPhase.none);
        expect(wallet.error, contains('another Chumbucket account'));
        expect(wallet.error, contains('not saved'));
        expect(store.values, isEmpty);
        expect(blockStore.entries, isEmpty);
        // Still free to make a wallet, or import another phrase.
        link.refuseLink = false;
        await wallet.importRecoveryPhrase(kTestPhrase);
        expect(wallet.linked, isTrue);
        expect(store.values, hasLength(1));
      },
    );

    test(
      'a failed read never becomes a new key written over the stored one',
      () async {
        final link = LinkServer();
        final store = MemorySecretStore();
        final existing = EmbeddedWalletRecord(
          address: kTestPhraseAddress,
          recoveryPhrase: kTestPhrase,
          linked: true,
          createdAt: DateTime.utc(2026, 10, 1),
        );
        store.values[EmbeddedWalletVault.keyFor(kCanonicalUserId)] =
            existing.encode();
        final wallet = EmbeddedWalletController(
          vault: EmbeddedWalletVault(store: store),
          bff: SessionBffClient(
            baseUrl: kSessionBase,
            httpClient: link.server.client,
          ),
          authToken: () async => kAccessToken,
          generate:
              () => EmbeddedWalletKey.fromRecoveryPhrase(kOtherTestPhrase),
        );
        addTearDown(wallet.dispose);
        // A locked phone: the stored wallet cannot be read.
        store.failReads = true;
        await wallet.bind(kCanonicalUserId);
        expect(wallet.hasWallet, isFalse);
        expect(wallet.error, contains('Couldn’t open'));
        // Still unreadable: "Create" refuses rather than overwrite.
        await wallet.create();
        expect(wallet.hasWallet, isFalse);
        expect(wallet.error, contains('Nothing was created'));
        expect(
          EmbeddedWalletRecord.decode(
            store.values[EmbeddedWalletVault.keyFor(kCanonicalUserId)],
          )?.address,
          kTestPhraseAddress,
        );
        // Unlocked: "Create" finds the wallet that was there all along.
        store.failReads = false;
        await wallet.create();
        expect(wallet.address, kTestPhraseAddress);
        expect(wallet.error, contains('Nothing was replaced'));
        expect(link.server.received, isEmpty);
      },
    );

    test(
      'after a reinstall, a backup that could not be read is not "no wallet"',
      () async {
        final link = LinkServer();
        final blockStore = MemoryBlockStore();
        final continuity = SessionContinuity(
          store: blockStore,
          adopt: (_) async => SessionAdoption.rejected,
          localSession: () async => null,
        );
        await continuity.backupWalletSecret(kCanonicalUserId, kTestPhrase);
        final store = MemorySecretStore();
        final wallet = EmbeddedWalletController(
          vault: EmbeddedWalletVault(store: store, continuity: continuity),
          bff: SessionBffClient(
            baseUrl: kSessionBase,
            httpClient: link.server.client,
          ),
          authToken: () async => kAccessToken,
          generate:
              () => EmbeddedWalletKey.fromRecoveryPhrase(kOtherTestPhrase),
        );
        addTearDown(wallet.dispose);
        blockStore.failReads = true;
        await wallet.bind(kCanonicalUserId);
        expect(wallet.hasWallet, isFalse);
        await wallet.create();
        expect(wallet.hasWallet, isFalse, reason: 'no new key while unsure');
        expect(store.values, isEmpty);
        blockStore.failReads = false;
        await wallet.create();
        expect(wallet.address, kTestPhraseAddress, reason: 'the backed-up one');
        expect(
          await continuity.restoreWalletSecret(kCanonicalUserId),
          kTestPhrase,
        );
      },
    );

    test('no session: the wallet stays unlinked and says to sign in', () async {
      final link = LinkServer();
      final wallet = controllerFor(link, token: null);
      addTearDown(wallet.dispose);
      await wallet.bind(kCanonicalUserId);
      await wallet.create();
      expect(wallet.linked, isFalse);
      expect(wallet.error, contains('Sign in again'));
      expect(link.server.received, isEmpty);
    });
  });
}
