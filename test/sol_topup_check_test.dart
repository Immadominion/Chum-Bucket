/// The phone's own check of a gasless USDC -> SOL swap, and the two signers,
/// on REAL mainnet transaction shapes (test/fixtures/jupiter_gasless_fixtures
/// .dart: identities replaced by the BIP-39 test phrase's wallet). Nothing is
/// sent anywhere; the only key is public test data.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/sol_topup/domain/gasless_swap_check.dart';
import 'package:chumbucket/features/sol_topup/domain/sol_topup_signer.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/encoder.dart' as encoder;
import 'package:solana/solana.dart' show Ed25519HDPublicKey, verifySignature;
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'fixtures/jupiter_gasless_fixtures.dart';
import 'identity_fakes.dart' show kTestPhrase, kOtherTestPhrase;

Uint8List _bytes(String b64) => Uint8List.fromList(base64Decode(b64));

ExpectedSwap _metis({
  String owner = kSwapOwner,
  int inAmount = kMetisInAmount,
  SwapRouter router = SwapRouter.metis,
  int quotedOut = kMetisOutAmount,
  int feeBps = kMetisFeeBps,
}) => ExpectedSwap(
  owner: owner,
  inAmount: BigInt.from(inAmount),
  router: router,
  quotedOutLamports: BigInt.from(quotedOut),
  feeBps: feeBps,
  nowSeconds: kMetisBlockTime,
);

ExpectedSwap _rfq({int inAmount = kRfqInAmount, int? now}) => ExpectedSwap(
  owner: kSwapOwner,
  inAmount: BigInt.from(inAmount),
  router: SwapRouter.jupiterZ,
  quotedOutLamports: BigInt.from(kRfqOutAmount),
  feeBps: kRfqFeeBps,
  nowSeconds: now ?? kRfqBlockTime,
);

/// Rebuilds a fixture with a change to its compiled v0 message.
Uint8List _mutate(
  String b64, {
  void Function(List<Ed25519HDPublicKey> keys)? keys,
  void Function(List<encoder.CompiledInstruction> ixs, List<String> keys)?
  instructions,
  void Function(List<List<int>> signatures)? signatures,
}) {
  final tx = encoder.SignedTx.fromBytes(base64Decode(b64));
  final m = tx.compiledMessage as encoder.CompiledMessageV0;
  final accountKeys = m.accountKeys.toList();
  keys?.call(accountKeys);
  final ixs = m.instructions.toList();
  instructions?.call(ixs, accountKeys.map((k) => k.toBase58()).toList());
  final message = encoder.CompiledMessage.v0(
    header: m.header,
    accountKeys: accountKeys,
    recentBlockhash: m.recentBlockhash,
    instructions: ixs,
    addressTableLookups: m.addressTableLookups,
  );
  final sigs = [for (final s in tx.signatures) s.bytes.toList()];
  signatures?.call(sigs);
  return Uint8List.fromList([
    sigs.length,
    for (final s in sigs) ...s,
    ...message.toByteArray(),
  ]);
}

int _ixOf(List<String> keys, List<encoder.CompiledInstruction> ixs, String p) =>
    ixs.indexWhere((ix) => keys[ix.programIdIndex] == p);

encoder.CompiledInstruction _withAccount(
  encoder.CompiledInstruction ix,
  int position,
  int index,
) => encoder.CompiledInstruction(
  programIdIndex: ix.programIdIndex,
  accountKeyIndexes: [...ix.accountKeyIndexes]..[position] = index,
  data: ix.data,
);

encoder.CompiledInstruction _withData(
  encoder.CompiledInstruction ix,
  List<int> Function(List<int> data) change,
) => encoder.CompiledInstruction(
  programIdIndex: ix.programIdIndex,
  accountKeyIndexes: ix.accountKeyIndexes,
  data: encoder.ByteArray(change(ix.data.toList())),
);

List<int> _writeU64(List<int> data, int offset, int value) {
  final out = [...data];
  var v = BigInt.from(value);
  for (var i = 0; i < 8; i++) {
    out[offset + i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

Future<void> _refuses(Uint8List bytes, ExpectedSwap expected, [String? why]) =>
    expectLater(
      checkGaslessSwap(bytes, expected),
      throwsA(
        isA<SwapCheckException>().having(
          (e) => e.reason,
          'reason',
          why == null ? anything : contains(why),
        ),
      ),
    );

class _Signing implements MwaSigningSession {
  _Signing(this.sign);
  final Uint8List Function(Uint8List) sign;
  int closed = 0;
  @override
  Future<SignPayloadsResult> signTransactions({
    required List<Uint8List> transactions,
  }) async => SignPayloadsResult(signedPayloads: [sign(transactions.single)]);
  @override
  Future<void> close() async => closed++;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Broadcast and other wallet APIs are forbidden');
}

class _Auth extends MwaAuthProvider {
  _Auth(this.signing);
  final _Signing signing;
  String? cluster;
  @override
  bool get isAuthenticated => true;
  @override
  String get walletAddress => kSwapOwner;
  @override
  int get authRevision => 1;
  @override
  Future<MwaSigningSession?> createSigningSession({String? cluster}) async {
    this.cluster = cluster;
    return signing;
  }
}

void main() {
  late EmbeddedWalletKey owner;
  setUpAll(() async {
    owner = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
    dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet');
  });

  group('checkGaslessSwap on real mainnet shapes', () {
    test('the fixtures belong to the test phrase\'s wallet', () async {
      expect(owner.address, kSwapOwner);
      expect(await ownerTokenAccount(kSwapOwner, usdcMint), kSwapOwnerUsdc);
      expect(await ownerTokenAccount(kSwapOwner, wsolMint), kSwapOwnerWsol);
    });

    test(
      'a Jupiter-sponsored Metis route_v2 passes, with what lands',
      () async {
        final c = await checkGaslessSwap(_bytes(kMetisSwapBase64), _metis());
        expect(c.router, SwapRouter.metis);
        expect(c.feePayer, jupiterGasWallet);
        expect(c.ownerSignatureIndex, 1);
        expect(c.inAmount, BigInt.from(kMetisInAmount));
        expect(c.feeBps, 11);
        expect(c.slippageBps, 34);
        // The same integers as the server's verify.ts.
        expect(c.minOutLamports, BigInt.from(105660949));
        expect(c.expectedOutLamports, BigInt.from(106021423));
        // What really landed for the original swapper was more than promised.
        expect(c.minOutLamports <= BigInt.from(106119149), isTrue);
      },
    );

    test(
      'a market-maker-paid JupiterZ fill passes; its fee is counted',
      () async {
        final c = await checkGaslessSwap(_bytes(kRfqSwapBase64), _rfq());
        expect(c.router, SwapRouter.jupiterZ);
        expect(c.feePayer, kRfqMaker);
        expect(c.feeBps, kRfqFeeBps);
        expect(c.minOutLamports, BigInt.from(4592968));
      },
    );

    test('another amount, owner, router, fee or a worse price', () async {
      final b = _bytes(kMetisSwapBase64);
      await _refuses(b, _metis(inAmount: kMetisInAmount + 1), 'amount');
      await _refuses(b, _metis(owner: kRfqMaker), 'signer');
      await _refuses(b, _metis(router: SwapRouter.jupiterZ), 'swap');
      await _refuses(b, _metis(quotedOut: 108000000), 'quote');
      await _refuses(b, _metis(feeBps: 5), 'fee');
      await _refuses(_bytes(kRfqSwapBase64), _rfq(inAmount: 1), 'amount');
    });

    test('a swap the person would pay gas for', () async {
      final b = _mutate(
        kMetisSwapBase64,
        keys: (k) {
          final first = k[0];
          k[0] = k[1];
          k[1] = first;
        },
      );
      await _refuses(b, _metis(), 'network fee');
    });

    test('anything already signed for the person', () async {
      final b = _mutate(
        kMetisSwapBase64,
        signatures: (s) => s[1] = List.filled(64, 7),
      );
      await _refuses(b, _metis(), 'already signed');
    });

    test('a route that pays someone else or spends another account', () async {
      for (final (position, why) in [
        (2, 'someone else'),
        (7, 'someone else'),
        (1, 'another account'),
      ]) {
        final b = _mutate(
          kMetisSwapBase64,
          instructions: (ixs, keys) {
            final i = _ixOf(keys, ixs, jupiterV6Program);
            ixs[i] = _withAccount(ixs[i], position, 2);
          },
        );
        await _refuses(b, _metis(), why);
      }
    });

    test('a changed amount inside the route data', () async {
      final b = _mutate(
        kMetisSwapBase64,
        instructions: (ixs, keys) {
          final i = _ixOf(keys, ixs, jupiterV6Program);
          ixs[i] = _withData(
            ixs[i],
            (d) => _writeU64(d, 8, kMetisInAmount * 2),
          );
        },
      );
      await _refuses(b, _metis(), 'amount');
    });

    test(
      'an extra transfer from the person, or a bigger rent repayment',
      () async {
        final steal = _mutate(
          kMetisSwapBase64,
          instructions: (ixs, keys) {
            ixs.add(
              encoder.CompiledInstruction(
                programIdIndex: keys.indexOf(systemProgram),
                accountKeyIndexes: const [1, 2],
                data: encoder.ByteArray([2, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]),
              ),
            );
          },
        );
        await _refuses(steal, _metis(), 'transfer');
        final greedy = _mutate(
          kMetisSwapBase64,
          instructions: (ixs, keys) {
            final i = _ixOf(keys, ixs, systemProgram);
            ixs[i] = _withData(ixs[i], (d) => _writeU64(d, 4, 5000000));
          },
        );
        await _refuses(greedy, _metis(), 'rent');
      },
    );

    test(
      'a close to someone else, a token transfer, another program',
      () async {
        final close = _mutate(
          kMetisSwapBase64,
          instructions: (ixs, keys) {
            final i = _ixOf(keys, ixs, tokenProgram);
            ixs[i] = _withAccount(ixs[i], 1, 0);
          },
        );
        await _refuses(close, _metis(), 'close');
        final transfer = _mutate(
          kMetisSwapBase64,
          instructions: (ixs, keys) {
            final i = _ixOf(keys, ixs, tokenProgram);
            ixs[i] = _withData(ixs[i], (_) => [3, 1, 0, 0, 0, 0, 0, 0, 0]);
          },
        );
        await _refuses(transfer, _metis(), 'token instruction');
        final memo = _mutate(
          kMetisSwapBase64,
          keys: (k) {
            final i = k.indexWhere((key) => key.toBase58() == jupiterV6Program);
            k[i] = Ed25519HDPublicKey.fromBase58(
              'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr',
            );
          },
        );
        await _refuses(memo, _metis(), 'program');
      },
    );

    test(
      'a fill not paid by its maker, stale, overcharged or redirected',
      () async {
        final makerless = _mutate(
          kRfqSwapBase64,
          instructions: (ixs, keys) {
            final i = _ixOf(keys, ixs, jupiterZProgram);
            ixs[i] = _withAccount(ixs[i], 1, 3);
          },
        );
        await _refuses(makerless, _rfq(), 'maker');
        await _refuses(
          _bytes(kRfqSwapBase64),
          _rfq(now: kRfqBlockTime + 3600),
          'expiry',
        );
        final fee = _mutate(
          kRfqSwapBase64,
          instructions: (ixs, keys) {
            final i = _ixOf(keys, ixs, systemProgram);
            ixs[i] = _withData(ixs[i], (d) => _writeU64(d, 4, 100000));
          },
        );
        await _refuses(fee, _rfq(), 'fee');
        final elsewhere = _mutate(
          kRfqSwapBase64,
          instructions: (ixs, keys) {
            final i = _ixOf(keys, ixs, jupiterZProgram);
            ixs[i] = _withAccount(ixs[i], 4, 3);
          },
        );
        await _refuses(elsewhere, _rfq(), 'someone else');
      },
    );

    test('garbage and oversize input', () async {
      await _refuses(Uint8List.fromList([1, 2, 3]), _metis(), 'encoding');
      await _refuses(Uint8List(1300), _metis(), 'size');
    });
  });

  group('signers', () {
    test(
      'the wallet on this phone signs exactly the checked message',
      () async {
        final unsigned = _bytes(kMetisSwapBase64);
        final checked = await checkGaslessSwap(unsigned, _metis());
        final signer = EmbeddedSolTopUpSigner(
          signer: () => owner,
          address: kSwapOwner,
        );
        expect(signer.kind, TopUpSignerKind.thisPhone);
        final signed = await signer.sign(unsigned, checked);
        expect(signed.length, unsigned.length);
        // The sponsor's slot is untouched; the person's is a valid signature.
        expect(signed.sublist(1, 65), unsigned.sublist(1, 65));
        expect(
          await verifySignature(
            message: checked.messageBytes,
            signature: signed.sublist(65, 129),
            publicKey: Ed25519HDPublicKey.fromBase58(kSwapOwner),
          ),
          isTrue,
        );
        expect(signed.sublist(129), unsigned.sublist(129));
      },
    );

    test('a different key on this phone signs nothing', () async {
      final unsigned = _bytes(kMetisSwapBase64);
      final checked = await checkGaslessSwap(unsigned, _metis());
      final other = await EmbeddedWalletKey.fromRecoveryPhrase(
        kOtherTestPhrase,
      );
      await expectLater(
        EmbeddedSolTopUpSigner(
          signer: () => other,
          address: kSwapOwner,
        ).sign(unsigned, checked),
        throwsA(isA<TopUpSignRefused>()),
      );
      await expectLater(
        EmbeddedSolTopUpSigner(
          signer: () => null,
          address: kSwapOwner,
        ).sign(unsigned, checked),
        throwsA(isA<TopUpSignRefused>()),
      );
      // Bytes other than the ones checked.
      await expectLater(
        EmbeddedSolTopUpSigner(
          signer: () => owner,
          address: kSwapOwner,
        ).sign(_bytes(kRfqSwapBase64), checked),
        throwsA(isA<TopUpSignRefused>()),
      );
    });

    test(
      'a wallet app: mainnet session, then only the reviewed message back',
      () async {
        final unsigned = _bytes(kMetisSwapBase64);
        final checked = await checkGaslessSwap(unsigned, _metis());
        Future<Uint8List> honest(Uint8List tx) async {
          final out = Uint8List.fromList(tx);
          out.setRange(65, 129, await owner.sign(checked.messageBytes));
          return out;
        }

        final signedByWallet = await honest(unsigned);
        final auth = _Auth(_Signing((_) => signedByWallet));
        final signer = MwaSolTopUpSigner(auth);
        expect(signer.kind, TopUpSignerKind.walletApp);
        final signed = await signer.sign(unsigned, checked);
        expect(signed, signedByWallet);
        expect(auth.cluster, NetworkConfig.mainnetBeta);
        expect(auth.signing.closed, 1);

        // The wallet touched the sponsor's slot: refused.
        final payerTouched = Uint8List.fromList(signedByWallet)
          ..setRange(1, 65, List.filled(64, 9));
        await expectLater(
          MwaSolTopUpSigner(
            _Auth(_Signing((_) => payerTouched)),
          ).sign(unsigned, checked),
          throwsA(isA<TopUpSignRefused>()),
        );
        // The wallet returned it unsigned, or signed with garbage.
        await expectLater(
          MwaSolTopUpSigner(
            _Auth(_Signing((tx) => tx)),
          ).sign(unsigned, checked),
          throwsA(isA<TopUpSignRefused>()),
        );
        final forged = Uint8List.fromList(unsigned)
          ..setRange(65, 129, List.filled(64, 3));
        await expectLater(
          MwaSolTopUpSigner(
            _Auth(_Signing((_) => forged)),
          ).sign(unsigned, checked),
          throwsA(isA<TopUpSignRefused>()),
        );
        // The wallet changed the message (e.g. its own priority fee).
        final changed = Uint8List.fromList(signedByWallet)
          ..[signedByWallet.length - 1] ^= 1;
        await expectLater(
          MwaSolTopUpSigner(
            _Auth(_Signing((_) => changed)),
          ).sign(unsigned, checked),
          throwsA(isA<TopUpSignRefused>()),
        );
      },
    );
  });
}
