/// Claiming a win with the wallet that lives on this phone: the signer refuses
/// anything but the reviewed `claim_win_usdc` (owner, market, the owner's own
/// USDC account) in the layout Panta's program uses on mainnet, and Profile →
/// Positions offers it only for the linked phone wallet's own positions.
///
/// The two accepted fixtures were compiled by the BFF's own claim builder
/// (`PantaClaimExecution.build`, which also validated them) from instructions
/// in the layout of real mainnet `ClaimWinUsdc` transactions (3 Oct 2026),
/// with the owner replaced by the public test phrase's wallet and the
/// position / win-claim PDAs synthetic. Every refusal below is built in that
/// same layout with one thing changed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/embedded_wallet/panta_wallet_app.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_claim.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart'
    show pantaMainnetProgramId, pantaPrimaryBuyDiscriminator;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_positions_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart'
    show
        Ed25519HDKeyPair,
        Ed25519HDPublicKey,
        Signature,
        findAssociatedTokenAddress,
        verifySignature;

import 'identity_embedded_wallet_test.dart' show LinkServer, kTestPhraseAddress;
import 'identity_fakes.dart';
import 'session_fakes.dart';

const _usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _system = '11111111111111111111111111111111';
const _computeBudget = 'ComputeBudget111111111111111111111111111111';
const _ata = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _memo = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';

// Real public mainnet accounts from claim 3ATu2Yd4…: Panta's config, the
// market, its vault authority and vault.
const _config = '8mJjfx7SuWwS4yfVZXtqC2cvzxr3TQHsCgKyjpuDWKAP';
const _market = 'ALio3GkarKxXy8qLdZwiUJo6XhS5QvuKw4bZKzruYdP6';
const _vaultAuthority = '3gpi7VkN9GFyRgXXHEbQxipSfykt5Sy4ccjLxQGFN5JW';
const _vault = '2Jt8nwPetkVA5ncRvzMWdZv2DNHLkPdwY6V1JJcX2TFp';
// Synthetic stand-ins for the owner's position and win-claim PDAs.
const _positionPda = '8gZngFATxStmT6PNtUbvEQfHJXzWtfwXjUQpomn2vZAy';
const _winClaim = '5UGJUxL1PXcjvAf7r4qnus7hyQBLoSrUxWT9qNEtCEQx';

/// ComputeBudget limit + claim, as `PantaClaimExecution.build` compiled it.
const _bffClaim =
    'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAACAAQAKDvA2J2JGp1ud4zSe1CsV4jL2UY/CD1/NTx1k6B+b0lj3E3Bg41xG'
    'mk1aATN2BA5YIAfwgPTkPjbiRc3Y45p2EKtCarsdJTJWtPOTRh6XC+MylP7WC+dbwgGWF64D'
    'YdvmiUDS8nxGHynp/roauKzTlJapxlsK5ipxPwH5QamTv1XtAwZGb+UhFzL/7K26csOb57yM'
    '5bvF9xJrLEObOkAAAABUXsogFmPstj/RQLtmhMmmhkvUfM4RVp/7q2Hy7fJzB3Nbavz020C2'
    'BEzP7dHfXJ3MAc15SU6jqSoAqeDVJ6UwisZ5XbCGPbQa5p6/acH7WQHzmP12fNnPOHMJJ4zx'
    'JQkn6vhOogd9oXNZ2cXhCPUoroo/uesiXd/cTB7nzb21T3IkiHOjSroYVF8b7Jdn9L1pi0Uu'
    'm9z2O3GHim2jvsI6xvp6877brTo9ZfNqq8l0MbG75MLS9uDkfKYCA0UvXWEG3fbh12Whk9nL'
    '4UbO63msHLSF7V9bN5E6jPWFfv8AqYyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZ'
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADEmud2A3ggVPF6nezqQ7RE66DtsSxv'
    'HTHG4OSoS/BS6wIEAAUCQA0DAAUMAAYHCAEJAgMKCwwNKCugajOnTBQf8DYnYkanW53jNJ7U'
    'KxXiMvZRj8IPX81PHWToH5vSWPcA';

/// ComputeBudget + the owner's USDC create-idempotent + claim + memo.
const _bffClaimFull =
    'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAAAAAAAAAAAACAAQALD/A2J2JGp1ud4zSe1CsV4jL2UY/CD1/NTx1k6B+b0lj3QNLyfEYf'
    'Ken+uhq4rNOUlqnGWwrmKnE/AflBqZO/Ve0TcGDjXEaaTVoBM3YEDlggB/CA9OQ+NuJFzdjj'
    'mnYQq0Jqux0lMla085NGHpcL4zKU/tYL51vCAZYXrgNh2+aJAwZGb+UhFzL/7K26csOb57yM'
    '5bvF9xJrLEObOkAAAACMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4Wcb6evO+2606'
    'PWXzaqvJdDGxu+TC0vbg5HymAgNFL11hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    'AAAG3fbh12Whk9nL4UbO63msHLSF7V9bN5E6jPWFfv8AqVReyiAWY+y2P9FAu2aEyaaGS9R8'
    'zhFWn/urYfLt8nMHc1tq/PTbQLYETM/t0d9cncwBzXlJTqOpKgCp4NUnpTCKxnldsIY9tBrm'
    'nr9pwftZAfOY/XZ82c84cwknjPElCSfq+E6iB32hc1nZxeEI9Siuij+56yJd39xMHufNvbVP'
    'ciSIc6NKuhhUXxvsl2f0vWmLRS6b3PY7cYeKbaO+wjoFSlNamSkhBk0k6HFg2jh8fDW13byS'
    'u4HkH6hAQQVEjcSa53YDeCBU8Xqd7OpDtETroO2xLG8dMcbg5KhL8FLrBAQABQJADQMABQYA'
    'AQAGBwgBAQkMAAoLDAINAwEGCAUHKCugajOnTBQf8DYnYkanW53jNJ7UKxXiMvZRj8IPX81P'
    'HWToH5vSWPcOAQAOcGFudGE6djE6Y2xhaW0A';

Ed25519HDPublicKey _pk(String b58) => Ed25519HDPublicKey.fromBase58(b58);
Future<String> _account(int n) async =>
    (await Ed25519HDKeyPair.fromPrivateKeyBytes(
      privateKey: List<int>.filled(32, n),
    )).address;
Future<String> _usdcOf(String owner) async =>
    (await findAssociatedTokenAddress(
      owner: _pk(owner),
      mint: _pk(_usdc),
    )).toBase58();

/// A claim in the mainnet layout, with one thing changed at a time.
Future<Uint8List> _claim(
  String owner, {
  String market = _market,
  String? payTo,
  List<int>? data,
  String? arg,
  bool transferOut = false,
  List<int>? computePrice,
  bool signed = false,
  String? feePayer,
  String program = pantaMainnetProgramId,
}) async {
  final ownerUsdc = payTo ?? await _usdcOf(owner);
  AccountMeta w(String k, {bool signer = false}) =>
      AccountMeta(pubKey: _pk(k), isWriteable: true, isSigner: signer);
  AccountMeta r(String k) =>
      AccountMeta(pubKey: _pk(k), isWriteable: false, isSigner: false);
  final compiled = Message(
    instructions: [
      Instruction(
        programId: _pk(_computeBudget),
        accounts: const [],
        data: ByteArray([2, 0x40, 0x0d, 0x03, 0x00]),
      ),
      if (computePrice != null)
        Instruction(
          programId: _pk(_computeBudget),
          accounts: const [],
          data: ByteArray([3, ...computePrice]),
        ),
      Instruction(
        programId: _pk(program),
        accounts: [
          w(owner, signer: true),
          r(_config),
          r(market),
          r(_vaultAuthority),
          w(_vault),
          r(_positionPda),
          w(_winClaim),
          w(ownerUsdc),
          r(_usdc),
          r(_token),
          r(_ata),
          r(_system),
        ],
        data: ByteArray(
          data ?? [...pantaClaimWinDiscriminator, ..._pk(arg ?? owner).bytes],
        ),
      ),
      if (transferOut)
        Instruction(
          programId: _pk(_system),
          accounts: [w(owner, signer: true), w(_vault)],
          data: ByteArray([2, 0, 0, 0, 0, 202, 154, 59, 0, 0, 0, 0]),
        ),
      Instruction(
        programId: _pk(_memo),
        accounts: [r(owner)],
        data: ByteArray(utf8.encode('panta:v1:claim')),
      ),
    ],
  ).compileV0(
    recentBlockhash: 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k',
    feePayer: _pk(feePayer ?? owner),
  );
  return Uint8List.fromList(
    SignedTx(
      compiledMessage: compiled,
      signatures: [
        Signature(
          List<int>.filled(64, signed ? 1 : 0),
          publicKey: _pk(feePayer ?? owner),
        ),
      ],
    ).toByteArray().toList(),
  );
}

class _WalletApp extends MwaAuthProvider {
  _WalletApp(this.wallet);
  final String? wallet;
  @override
  bool get isAuthenticated => wallet != null;
  @override
  String? get walletAddress => wallet;
}

void main() {
  late EmbeddedWalletKey key;
  setUpAll(() async {
    key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
  });

  PantaClaimSigningIntent intent({
    String? owner,
    String market = _market,
    String shares = '12.5',
  }) => PantaClaimSigningIntent(
    owner: owner ?? key.address,
    venueMarketId: market,
    outcome: Side.yes,
    winningShares: shares,
  );

  PantaEmbeddedClaimWallet port([PantaClaimSigningIntent? reviewed]) =>
      PantaEmbeddedClaimWallet(signer: () => key, intent: reviewed ?? intent());

  test('signs the claims the BFF builds, and only the payer slot', () async {
    expect(key.address, kTestPhraseAddress);
    for (final fixture in [_bffClaim, _bffClaimFull]) {
      final unsigned = base64Decode(fixture);
      final signed = await port().signTransaction(unsigned);
      expect(signed.sublist(65), unsigned.sublist(65));
      expect(
        await verifySignature(
          message: unsigned.sublist(65),
          signature: signed.sublist(1, 65),
          publicKey: _pk(key.address),
        ),
        isTrue,
      );
    }
    // The synthetic builder matches the BFF's layout.
    await port().signTransaction(await _claim(key.address));
  });

  Future<void> refuses(
    Future<Uint8List> bytes, {
    PantaClaimSigningIntent? reviewed,
  }) async => expectLater(
    port(reviewed).signTransaction(await bytes),
    throwsA(isA<PantaException>()),
  );

  test(
    'refuses another market, payout account, argument or instruction',
    () async {
      // The review was for another market.
      await refuses(
        _claim(key.address),
        reviewed: intent(market: await _account(7)),
      );
      // The claim names another market than the review.
      await refuses(_claim(key.address, market: await _account(7)));
      // Paid into someone else's USDC account.
      await refuses(
        _claim(key.address, payTo: await _usdcOf(await _account(8))),
      );
      // Claimed on someone else's behalf.
      await refuses(_claim(key.address, arg: await _account(9)));
      // A buy dressed up as a claim.
      await refuses(
        _claim(
          key.address,
          data: [
            ...pantaPrimaryBuyDiscriminator,
            0,
            0,
            202,
            154,
            59,
            0,
            0,
            0,
            0,
          ],
        ),
      );
      // Another program.
      await refuses(_claim(key.address, program: await _account(10)));
    },
  );

  test(
    'refuses a SOL transfer, a runaway fee, a stranger paying, or a signed slot',
    () async {
      await refuses(_claim(key.address, transferOut: true));
      // A u64 price with its top bit set must not wrap under the ceiling.
      await refuses(
        _claim(key.address, computePrice: List<int>.filled(8, 0xff)),
      );
      await refuses(
        _claim(key.address, computePrice: [0x41, 0x42, 0x0f, 0, 0, 0, 0, 0]),
      );
      await refuses(_claim(key.address, signed: true));
      await refuses(_claim(key.address, feePayer: await _account(11)));
      // A bounded price is fine.
      await port().signTransaction(
        await _claim(
          key.address,
          computePrice: [0x40, 0x42, 0x0f, 0, 0, 0, 0, 0],
        ),
      );
    },
  );

  test('refuses a review that is not a win, or another key', () async {
    await refuses(_claim(key.address), reviewed: intent(shares: '0'));
    await refuses(_claim(key.address), reviewed: intent(shares: '-1'));
    await refuses(_claim(key.address), reviewed: intent(shares: 'lots'));
    final other = await EmbeddedWalletKey.fromRecoveryPhrase(kOtherTestPhrase);
    await expectLater(
      PantaEmbeddedClaimWallet(
        signer: () => other,
        intent: intent(),
      ).signTransaction(await _claim(key.address)),
      throwsA(isA<PantaException>()),
    );
    await expectLater(
      PantaEmbeddedClaimWallet(
        signer: () => null,
        intent: intent(),
      ).signTransaction(await _claim(key.address)),
      throwsA(isA<PantaException>()),
    );
  });

  group('Profile → Positions picks the signer', () {
    late MemorySecretStore secrets;
    late EmbeddedWalletController onPhone;
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

    test('the linked phone wallet signs its own claim', () async {
      await phoneWallet(linked: true);
      final signer = profilePantaSigners(_WalletApp(null), onPhone)(
        kTestPhraseAddress,
        intent(),
      );
      expect(signer, isA<PantaEmbeddedClaimWallet>());
      final unsigned = base64Decode(_bffClaim);
      expect(
        (await signer!.signTransaction(unsigned)).sublist(65),
        unsigned.sublist(65),
      );
    });

    test(
      'a wallet app comes first; nothing for an unlinked or other wallet',
      () async {
        await phoneWallet(linked: true);
        expect(
          profilePantaSigners(_WalletApp(kTestPhraseAddress), onPhone)(
            kTestPhraseAddress,
            intent(),
          ),
          isA<CheckedPantaWalletPort>(),
        );
        final other = await _account(12);
        expect(
          profilePantaSigners(_WalletApp(null), onPhone)(
            other,
            intent(owner: other),
          ),
          isNull,
        );
        expect(profilePantaSigners(null)(kTestPhraseAddress, intent()), isNull);

        await onPhone.bind(null);
        await phoneWallet(linked: false);
        expect(
          profilePantaSigners(_WalletApp(null), onPhone)(
            kTestPhraseAddress,
            intent(),
          ),
          isNull,
        );
      },
    );
  });

  group('a wallet app signs a claim only after the same check', () {
    PantaWalletPort appPort(_AppPort inner, [PantaClaimSigningIntent? reviewed]) =>
        walletAppClaimPort(
          _WalletApp(kTestPhraseAddress),
          intent: reviewed ?? intent(),
          inner: inner,
        );

    test('the reviewed claim reaches the app, the same bytes back', () async {
      final inner = _AppPort();
      final unsigned = base64Decode(_bffClaim);
      final signed = await appPort(inner).signTransaction(unsigned);
      expect(inner.asked, 1);
      expect(inner.seen.single, unsigned);
      expect(signed.sublist(65), unsigned.sublist(65));
    });

    for (final (name, bytes) in <(String, Future<Uint8List> Function())>[
      ('another market', () async => _claim(key.address, market: await _account(7))),
      (
        'another payout account',
        () async => _claim(key.address, payTo: await _usdcOf(await _account(8))),
      ),
      ('a SOL transfer tucked in', () async => _claim(key.address, transferOut: true)),
      ('another program', () async => _claim(key.address, program: await _account(10))),
      (
        'an inflated priority fee',
        () async => _claim(key.address, computePrice: List<int>.filled(8, 0xff)),
      ),
      ('someone else paying', () async => _claim(key.address, feePayer: await _account(11))),
    ]) {
      test('never opens the app for $name', () async {
        final inner = _AppPort();
        await expectLater(
          appPort(inner).signTransaction(await bytes()),
          throwsA(isA<PantaException>()),
        );
        expect(inner.asked, 0);
      });
    }

    test('an answer that changes the transaction is refused', () async {
      final inner = _AppPort(tamper: true);
      await expectLater(
        appPort(inner).signTransaction(base64Decode(_bffClaim)),
        throwsA(
          isA<PantaException>().having(
            (e) => e.code,
            'code',
            PantaErrorCode.signingFailed,
          ),
        ),
      );
    });
  });
}

/// Stands in for the wallet app: fills the owner's slot, or tampers.
class _AppPort implements PantaWalletPort {
  _AppPort({this.tamper = false});
  final bool tamper;
  int asked = 0;
  final seen = <Uint8List>[];

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    asked++;
    seen.add(Uint8List.fromList(unsigned));
    final signed = Uint8List.fromList(unsigned)..fillRange(1, 65, 7);
    if (tamper) signed[signed.length - 1] ^= 1;
    return signed;
  }
}
