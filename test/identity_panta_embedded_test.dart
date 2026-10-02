/// Signing a reviewed Panta buy with the on-phone wallet. With no wallet app
/// to show a second screen, the signer itself refuses anything but exactly
/// the reviewed buy: these are real v0 transactions in the BFF's shape.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart'
    show Ed25519HDKeyPair, Ed25519HDPublicKey, Signature, verifySignature;

import 'identity_fakes.dart';

const _usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _system = '11111111111111111111111111111111';
const _computeBudget = 'ComputeBudget111111111111111111111111111111';
const _ata = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _memo = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';

Ed25519HDPublicKey _pk(String b58) => Ed25519HDPublicKey.fromBase58(b58);

/// Deterministic distinct accounts for the buy's other roles.
Future<String> _account(int n) async =>
    (await Ed25519HDKeyPair.fromPrivateKeyBytes(
      privateKey: List<int>.filled(32, n),
    )).address;

class Tx {
  const Tx({
    this.amount = 2500000,
    this.side = Side.yes,
    this.computePrice = 5000,
    this.extraTransferTo,
    this.program = pantaMainnetProgramId,
    this.memo = 'panta:v1:partner-1:quote-1:order-1',
    this.secondSigner,
  });
  final int amount;
  final Side side;
  final int computePrice;
  final String? extraTransferTo;
  final String program;
  final String memo;
  final String? secondSigner;
}

/// An unsigned v0 primary buy laid out as the BFF's PantaExecution builds it:
/// ComputeBudget limit + price, ATA create-idempotent, the buy, the memo.
Future<Uint8List> pantaBuy(
  String owner,
  String market, [
  Tx tx = const Tx(),
]) async {
  final roles = [for (var i = 1; i <= 6; i++) await _account(i)];
  final ownerKey = _pk(owner);
  AccountMeta w(String k, {bool signer = false}) =>
      AccountMeta(pubKey: _pk(k), isWriteable: true, isSigner: signer);
  AccountMeta r(String k) =>
      AccountMeta(pubKey: _pk(k), isWriteable: false, isSigner: false);
  final buyData = ByteArray([
    ...pantaPrimaryBuyDiscriminator,
    tx.side == Side.yes ? 0 : 1,
    ...(ByteData(8)
      ..setUint64(0, tx.amount, Endian.little)).buffer.asUint8List(),
  ]);
  final instructions = <Instruction>[
    Instruction(
      programId: _pk(_computeBudget),
      accounts: const [],
      data: ByteArray([
        2,
        ...(ByteData(4)
          ..setUint32(0, 400000, Endian.little)).buffer.asUint8List(),
      ]),
    ),
    Instruction(
      programId: _pk(_computeBudget),
      accounts: const [],
      data: ByteArray([
        3,
        ...(ByteData(8)
          ..setUint64(0, tx.computePrice, Endian.little)).buffer.asUint8List(),
      ]),
    ),
    Instruction(
      programId: _pk(_ata),
      accounts: [
        w(owner, signer: true),
        w(roles[0]),
        r(owner),
        r(_usdcMint),
        r(_system),
        r(_token),
      ],
      data: ByteArray([1]),
    ),
    Instruction(
      programId: _pk(tx.program),
      accounts: [
        w(owner, signer: true),
        w(market),
        r(roles[1]),
        r(roles[2]),
        w(roles[3]),
        w(roles[4]),
        r(_usdcMint),
        w(roles[0]),
        w(roles[5]),
        r(_token),
        r(_ata),
        r(_system),
      ],
      data: buyData,
    ),
    if (tx.extraTransferTo != null)
      Instruction(
        programId: _pk(_system),
        accounts: [w(owner, signer: true), w(tx.extraTransferTo!)],
        data: ByteArray([2, 0, 0, 0, 0, 202, 154, 59, 0, 0, 0, 0]),
      ),
    Instruction(
      programId: _pk(_memo),
      accounts: [
        AccountMeta(pubKey: ownerKey, isWriteable: false, isSigner: true),
        if (tx.secondSigner != null)
          AccountMeta(
            pubKey: _pk(tx.secondSigner!),
            isWriteable: false,
            isSigner: true,
          ),
      ],
      data: ByteArray(utf8.encode(tx.memo)),
    ),
  ];
  final compiled = Message(instructions: instructions).compileV0(
    recentBlockhash: 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k',
    feePayer: ownerKey,
  );
  final signers = compiled.requiredSignatureCount;
  return Uint8List.fromList(
    SignedTx(
      compiledMessage: compiled,
      signatures: [
        for (var i = 0; i < signers; i++)
          Signature(
            List<int>.filled(64, 0),
            publicKey: compiled.accountKeys[i],
          ),
      ],
    ).toByteArray().toList(),
  );
}

void main() {
  late EmbeddedWalletKey key;
  late String market;

  setUpAll(() async {
    key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
    market = await _account(42);
  });

  PantaEmbeddedWallet port({
    String amount = '2500000',
    Side side = Side.yes,
    String? address,
    EmbeddedWalletKey Function()? signer,
  }) => PantaEmbeddedWallet(
    signer: signer ?? () => key,
    address: address ?? key.address,
    reviewed: PantaReviewedBuy(
      venueMarketId: market,
      side: side,
      amountBaseUnits: () => amount,
    ),
  );

  test(
    'signs exactly the reviewed buy, and the server-side checks pass',
    () async {
      final unsigned = await pantaBuy(key.address, market);
      // The app's own structural validator agrees it is the wallet's to sign.
      const PantaTransactionValidator().validateUnsigned(unsigned, key.address);
      final signed = await port().signTransaction(unsigned);
      const PantaTransactionValidator().validateSigned(
        unsigned,
        signed,
        key.address,
      );
      final tx = SignedTx.fromBytes(signed);
      expect(
        await verifySignature(
          message: tx.compiledMessage.toByteArray().toList(),
          signature: tx.signatures.single.bytes,
          publicKey: _pk(key.address),
        ),
        isTrue,
      );
      // Only the signature slot changed.
      expect(signed.sublist(65), unsigned.sublist(65));
    },
  );

  test('a NO buy signs only when NO was reviewed', () async {
    final no = await pantaBuy(key.address, market, const Tx(side: Side.no));
    await expectLater(
      port().signTransaction(no),
      throwsA(isA<PantaException>()),
    );
    expect(await port(side: Side.no).signTransaction(no), hasLength(no.length));
  });

  for (final (name, make) in <(String, Future<Tx> Function())>[
    ('a different amount than reviewed', () async => const Tx(amount: 9900000)),
    (
      'a SOL transfer tucked in',
      () async => Tx(extraTransferTo: await _account(77)),
    ),
    ('a program that is not Panta', () async => const Tx(program: _token)),
    ('an inflated priority fee', () async => const Tx(computePrice: 50000000)),
    ('a memo that is not Panta attribution', () async => const Tx(memo: 'gm')),
  ]) {
    test('refuses $name', () async {
      final unsigned = await pantaBuy(key.address, market, await make());
      await expectLater(
        port().signTransaction(unsigned),
        throwsA(
          isA<PantaException>().having(
            (e) => e.code,
            'code',
            PantaErrorCode.invalidResponse,
          ),
        ),
      );
    });
  }

  test(
    'refuses a second signer, another market, or another fee payer',
    () async {
      final twoSigners = await pantaBuy(
        key.address,
        market,
        Tx(secondSigner: await _account(9)),
      );
      await expectLater(
        port().signTransaction(twoSigners),
        throwsA(isA<PantaException>()),
      );
      final otherMarket = await pantaBuy(key.address, await _account(43));
      await expectLater(
        port().signTransaction(otherMarket),
        throwsA(isA<PantaException>()),
      );
      final someoneElse = await pantaBuy(await _account(8), market);
      await expectLater(
        port().signTransaction(someoneElse),
        throwsA(isA<PantaException>()),
      );
      await expectLater(
        port().signTransaction(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<PantaException>()),
      );
    },
  );

  test('an account change between review and signing signs nothing', () async {
    final unsigned = await pantaBuy(key.address, market);
    final other = await EmbeddedWalletKey.fromRecoveryPhrase(kOtherTestPhrase);
    await expectLater(
      port(signer: () => other).signTransaction(unsigned),
      throwsA(
        isA<PantaException>().having(
          (e) => e.code,
          'code',
          PantaErrorCode.walletChanged,
        ),
      ),
    );
    await expectLater(
      port(
        signer: () => throw StateError('signed out'),
      ).signTransaction(unsigned),
      throwsA(
        isA<PantaException>().having(
          (e) => e.code,
          'code',
          PantaErrorCode.walletChanged,
        ),
      ),
    );
  });
}
