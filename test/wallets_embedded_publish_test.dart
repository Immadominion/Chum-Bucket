/// Publishing a market with the wallet that lives on this phone: the signer
/// refuses anything but a create shaped as the BFF builds and checks it
/// (`PantaMarketCreator`, policy panta-create/docs-v1), for the market that
/// was reviewed. Transactions are synthetic v0 creates in that shape.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_create.dart';
import 'package:chumbucket/features/embedded_wallet/panta_embedded_wallet.dart'
    show pantaMainnetProgramId;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart'
    show
        Ed25519HDKeyPair,
        Ed25519HDPublicKey,
        Signature,
        findAssociatedTokenAddress,
        verifySignature;

import 'identity_fakes.dart';

const _usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _system = '11111111111111111111111111111111';
const _computeBudget = 'ComputeBudget111111111111111111111111111111';
const _ata = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _memo = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';

Ed25519HDPublicKey _pk(String b58) => Ed25519HDPublicKey.fromBase58(b58);
Future<String> _account(int n) async =>
    (await Ed25519HDKeyPair.fromPrivateKeyBytes(
      privateKey: List<int>.filled(32, n),
    )).address;

Future<Uint8List> _create(
  String owner,
  String event, {
  String program = pantaMainnetProgramId,
  bool transferOut = false,
  int computePrice = 5000,
  bool signed = false,
}) async {
  final roles = [for (var i = 1; i <= 3; i++) await _account(i)];
  final ownerUsdc =
      (await findAssociatedTokenAddress(
        owner: _pk(owner),
        mint: _pk(_usdc),
      )).toBase58();
  AccountMeta w(String k, {bool signer = false}) =>
      AccountMeta(pubKey: _pk(k), isWriteable: true, isSigner: signer);
  AccountMeta r(String k) =>
      AccountMeta(pubKey: _pk(k), isWriteable: false, isSigner: false);
  final compiled = Message(
    instructions: [
      Instruction(
        programId: _pk(_computeBudget),
        accounts: const [],
        data: ByteArray([2, 0x80, 0x1a, 0x06, 0x00]),
      ),
      Instruction(
        programId: _pk(_computeBudget),
        accounts: const [],
        data: ByteArray([
          3,
          ...(ByteData(8)
            ..setUint64(0, computePrice, Endian.little)).buffer.asUint8List(),
        ]),
      ),
      Instruction(
        programId: _pk(_ata),
        accounts: [
          w(owner, signer: true),
          w(ownerUsdc),
          r(owner),
          r(_usdc),
          r(_system),
          r(_token),
        ],
        data: ByteArray([1]),
      ),
      Instruction(
        programId: _pk(program),
        accounts: [
          w(owner, signer: true),
          w(event),
          w(roles[0]),
          r(_usdc),
          w(ownerUsdc),
          r(roles[1]),
          r(_token),
          r(_system),
        ],
        data: ByteArray([7, 1, 2, 3]),
      ),
      if (transferOut)
        Instruction(
          programId: _pk(_system),
          accounts: [w(owner, signer: true), w(roles[2])],
          data: ByteArray([2, 0, 0, 0, 0, 202, 154, 59, 0, 0, 0, 0]),
        ),
      Instruction(
        programId: _pk(_memo),
        accounts: const [],
        data: ByteArray(utf8.encode('chumbucket:create')),
      ),
    ],
  ).compileV0(
    recentBlockhash: 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k',
    feePayer: _pk(owner),
  );
  return Uint8List.fromList(
    SignedTx(
      compiledMessage: compiled,
      signatures: [
        Signature(List<int>.filled(64, signed ? 1 : 0), publicKey: _pk(owner)),
      ],
    ).toByteArray().toList(),
  );
}

void main() {
  late EmbeddedWalletKey key;
  late String event;
  setUpAll(() async {
    key = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
    event = await _account(42);
  });

  PantaEmbeddedCreateWallet port({String? reviewedEvent}) =>
      PantaEmbeddedCreateWallet(signer: () => key, address: key.address)
        ..reviewedEvent = () => reviewedEvent;

  test('signs the reviewed create, and only the payer slot', () async {
    final unsigned = await _create(key.address, event);
    final signed = await port(reviewedEvent: event).signTransaction(unsigned);
    expect(signed.sublist(65), unsigned.sublist(65));
    expect(
      await verifySignature(
        message: unsigned.sublist(65),
        signature: signed.sublist(1, 65),
        publicKey: _pk(key.address),
      ),
      isTrue,
    );
  });

  Future<void> refuses(Future<Uint8List> bytes, {String? reviewed}) async =>
      expectLater(
        port(reviewedEvent: reviewed ?? event).signTransaction(await bytes),
        throwsA(isA<PantaException>()),
      );

  test(
    'refuses another market, program, a SOL transfer or an inflated fee',
    () async {
      await refuses(_create(key.address, event), reviewed: await _account(43));
      await refuses(_create(key.address, event, program: await _account(9)));
      await refuses(_create(key.address, event, transferOut: true));
      await refuses(_create(key.address, event, computePrice: 1000001));
      await refuses(_create(key.address, event, signed: true));
      // Paid by someone else.
      await refuses(_create(await _account(5), event));
    },
  );

  test('refuses before a review is bound, or with another key', () async {
    final unsigned = await _create(key.address, event);
    await expectLater(
      port().signTransaction(unsigned),
      throwsA(isA<PantaException>()),
    );
    final other = await EmbeddedWalletKey.fromRecoveryPhrase(kOtherTestPhrase);
    await expectLater(
      (PantaEmbeddedCreateWallet(signer: () => other, address: key.address)
        ..reviewedEvent = () => event).signTransaction(unsigned),
      throwsA(isA<PantaException>()),
    );
  });
}
