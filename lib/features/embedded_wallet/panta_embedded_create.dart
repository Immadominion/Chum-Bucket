/// Signs a reviewed Panta market create with the wallet that lives on this
/// phone.
///
/// A wallet app shows its own simulation before approving; an on-phone key
/// has none, so this refuses anything but a create shaped the way the BFF
/// builds and checks it (`PantaMarketCreator.validateTransaction`, policy
/// `panta-create/docs-v1`):
///
///  * one v0 (or legacy) transaction, no lookup tables, exactly one signer —
///    this wallet, also the fee payer — with an empty signature slot;
///  * only Panta's mainnet program (1–2 instructions, signed by this wallet,
///    writing the reviewed market's address), bounded ComputeBudget before it,
///    create-idempotent of USDC accounts paid by this wallet, and at most one
///    memo;
///  * no System or Token instruction at the top level, so nothing can move
///    SOL or USDC except inside Panta's program for the fee that was reviewed.
///
/// It signs only; the BFF broadcasts and verifies the exact debit on-chain.
library;

import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;
import 'package:solana/solana.dart'
    show Ed25519HDPublicKey, findAssociatedTokenAddress;

import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'embedded_wallet_key.dart';
import 'panta_embedded_wallet.dart' show pantaMainnetProgramId;

const _computeBudget = 'ComputeBudget111111111111111111111111111111';
const _ata = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _memo = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _system = '11111111111111111111111111111111';
const _usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

/// The BFF's ceilings for a create (`PantaMarketCreator`).
const _maxComputeUnits = 1400000;
const _maxComputePrice = 1000000;

class PantaEmbeddedCreateWallet implements PantaWalletPort {
  PantaEmbeddedCreateWallet({
    required EmbeddedWalletKey? Function() signer,
    required this.address,
  }) : _signer = signer;

  final EmbeddedWalletKey? Function() _signer;
  final String address;

  /// The reviewed market's on-chain address, bound by the publish screen once
  /// the review exists. Signing refuses until it is.
  String? Function()? reviewedEvent;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    final key = _signer();
    if (key == null || key.address != address) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
    final event = reviewedEvent?.call();
    if (event == null) throw const PantaException(PantaErrorCode.signingFailed);
    final message = await checkPantaCreateForEmbeddedSigning(
      unsigned,
      owner: address,
      eventAddress: event,
    );
    final signature = await key.sign(message);
    if (signature.length != 64) {
      throw const PantaException(PantaErrorCode.signingFailed);
    }
    final signed = Uint8List.fromList(unsigned);
    signed.setRange(1, 65, signature);
    return signed;
  }
}

/// The exact message bytes to sign, or [PantaErrorCode.invalidResponse].
Future<Uint8List> checkPantaCreateForEmbeddedSigning(
  Uint8List bytes, {
  required String owner,
  required String eventAddress,
}) async {
  void require(bool condition) {
    if (!condition) throw const PantaException(PantaErrorCode.invalidResponse);
  }

  final encoder.SignedTx tx;
  try {
    require(bytes.length > 65 && bytes.length <= 1232);
    tx = encoder.SignedTx.fromBytes(bytes);
  } on PantaException {
    rethrow;
  } catch (_) {
    throw const PantaException(PantaErrorCode.invalidResponse);
  }
  final message = tx.compiledMessage;
  final lookups =
      message is encoder.CompiledMessageV0
          ? message.addressTableLookups.length
          : 0;
  final keys = message.accountKeys.map((k) => k.toBase58()).toList();
  final header = message.header;
  final messageBytes = Uint8List.fromList(message.toByteArray().toList());
  require(
    lookups == 0 &&
        bytes[0] == 1 &&
        tx.signatures.length == 1 &&
        tx.signatures.single.bytes.every((b) => b == 0) &&
        header.numRequiredSignatures == 1 &&
        header.numReadonlySignedAccounts == 0 &&
        keys.isNotEmpty &&
        keys.first == owner &&
        keys.toSet().length == keys.length &&
        bytes.length == 65 + messageBytes.length,
  );
  for (var i = 0; i < messageBytes.length; i++) {
    require(bytes[65 + i] == messageBytes[i]);
  }
  final readonlyFrom = keys.length - header.numReadonlyUnsignedAccounts;
  bool writable(int index) =>
      index == 0 || (index >= 1 && index < readonlyFrom);

  var panta = 0, memo = 0, ata = 0;
  var limit = false, price = false, eventWritten = false;
  for (final ix in message.instructions) {
    // Invoked programs are never signers or writable.
    require(
      ix.programIdIndex >= readonlyFrom && ix.programIdIndex < keys.length,
    );
    final program = keys[ix.programIdIndex];
    final data = ix.data.toList();
    final accounts = [
      for (final index in ix.accountKeyIndexes)
        index < keys.length ? keys[index] : null,
    ];
    require(accounts.every((a) => a != null));
    switch (program) {
      case pantaMainnetProgramId:
        panta++;
        // This wallet signs it, and it writes the reviewed market.
        require(ix.accountKeyIndexes.contains(0));
        if (ix.accountKeyIndexes.any(
          (index) => keys[index] == eventAddress && writable(index),
        )) {
          eventWritten = true;
        }
      case _computeBudget:
        require(accounts.isEmpty && panta == 0);
        if (data.length == 5 && data[0] == 2 && !limit) {
          limit = true;
          final units = _le(data, 1, 4);
          require(units > 0 && units <= _maxComputeUnits);
        } else if (data.length == 9 && data[0] == 3 && !price) {
          price = true;
          require(_le(data, 1, 8) <= _maxComputePrice);
        } else {
          require(false);
        }
      case _ata:
        // Create-idempotent of a USDC account, paid by this wallet. Moves no
        // USDC; costs only that account's rent.
        require(
          ++ata <= 3 &&
              data.length == 1 &&
              data[0] == 1 &&
              accounts.length == 6 &&
              accounts[0] == owner &&
              accounts[3] == _usdc &&
              accounts[4] == _system &&
              accounts[5] == _token,
        );
        final expected =
            (await findAssociatedTokenAddress(
              owner: Ed25519HDPublicKey.fromBase58(accounts[2]!),
              mint: Ed25519HDPublicKey.fromBase58(_usdc),
            )).toBase58();
        require(accounts[1] == expected);
      case _memo:
        require(++memo <= 1 && data.length <= 566);
      default:
        // System, Token or anything else at the top level: never.
        require(false);
    }
  }
  require(panta >= 1 && panta <= 2 && eventWritten);
  return messageBytes;
}

int _le(List<int> data, int offset, int length) {
  var value = 0;
  for (var i = length - 1; i >= 0; i--) {
    value = (value << 8) | data[offset + i];
  }
  return value;
}
