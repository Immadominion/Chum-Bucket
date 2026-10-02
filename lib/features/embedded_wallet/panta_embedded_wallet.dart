/// Signs a reviewed Panta buy with the wallet that lives on this phone.
///
/// A wallet app (Phantom, Seeker) shows its own simulation of every
/// transaction before the person approves it. An on-phone key has no such
/// second screen: the person's approval is the review sheet's "Sign" button,
/// and this class is the only thing between that tap and a signature. So it
/// refuses anything that is not exactly the buy that was reviewed:
///
///  * one v0 transaction, no address lookup tables, exactly one signer — this
///    wallet — which is also the fee payer;
///  * only the instructions a Panta primary buy is made of, in their order:
///    compute budget (bounded), the wallet's own USDC account (create-if-
///    missing), ONE buy on Panta's mainnet program for the reviewed market,
///    side and USDC amount, and the attribution memo;
///  * no other program, and no System/Token instruction at the top level, so
///    nothing can transfer SOL or USDC anywhere else.
///
/// The BFF validates the same shape server-side (`PantaExecution`); this is
/// the independent check on the phone. It signs only; the BFF broadcasts.
library;

import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;
import 'package:solana/solana.dart'
    show Ed25519HDPublicKey, findAssociatedTokenAddress;

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'embedded_wallet_key.dart';

/// Panta's mainnet program (`PANTA_MAINNET_PROGRAM_ID` in the BFF).
const pantaMainnetProgramId = '6gM5afTQBq5VZCfgpGqcsqzfWd5maLSCKWtGjbEobZMp';
const _computeBudgetProgram = 'ComputeBudget111111111111111111111111111111';
const _associatedTokenProgram = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _memoProgram = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
const _tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _systemProgram = '11111111111111111111111111111111';

/// Mainnet USDC (`USDC_MINT` in the BFF): the only token a buy may spend.
const _usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

/// sha256("global:primary_order_usdc")[0..8] — the Anchor discriminator the
/// BFF builds the buy with (`PRIMARY_BUY_DISCRIMINATOR`).
const pantaPrimaryBuyDiscriminator = [46, 137, 68, 116, 49, 89, 13, 247];

/// The BFF's own ceilings (`MAX_COMPUTE_UNITS`, `MAX_COMPUTE_PRICE`), so a
/// priority fee can never be inflated past what the server would build.
const _maxComputeUnits = 1400000;
const _maxComputePriceMicroLamports = 1000000;

/// What the person reviewed. [amountBaseUnits] is read at signing time from
/// the quote they approved.
class PantaReviewedBuy {
  const PantaReviewedBuy({
    required this.venueMarketId,
    required this.side,
    required this.amountBaseUnits,
  });
  final String venueMarketId;
  final Side side;
  final String? Function() amountBaseUnits;
}

class PantaEmbeddedWallet implements PantaWalletPort {
  PantaEmbeddedWallet({
    required EmbeddedWalletKey Function() signer,
    required String address,
    required this.reviewed,
  }) : _signer = signer,
       _address = address;

  /// Re-read at signing time: an account change between review and signing
  /// yields a different (or no) key, and the address check below refuses it.
  final EmbeddedWalletKey Function() _signer;
  final String _address;
  final PantaReviewedBuy reviewed;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    final EmbeddedWalletKey key;
    try {
      key = _signer();
    } catch (_) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
    if (key.address != _address) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
    final amount = reviewed.amountBaseUnits();
    if (amount == null) {
      throw const PantaException(PantaErrorCode.signingFailed);
    }
    final message = await checkPantaBuyForEmbeddedSigning(
      unsigned,
      owner: _address,
      venueMarketId: reviewed.venueMarketId,
      side: reviewed.side,
      amountBaseUnits: amount,
    );
    final signature = await key.sign(message);
    if (signature.length != 64) {
      throw const PantaException(PantaErrorCode.signingFailed);
    }
    // The single signature slot sits right after its one-byte count.
    final signed = Uint8List.fromList(unsigned);
    signed.setRange(1, 65, signature);
    return signed;
  }
}

/// Returns the exact message bytes to sign, or throws
/// [PantaErrorCode.invalidResponse] for anything but the reviewed buy.
Future<Uint8List> checkPantaBuyForEmbeddedSigning(
  Uint8List bytes, {
  required String owner,
  required String venueMarketId,
  required Side side,
  required String amountBaseUnits,
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
  require(tx.version == encoder.TransactionVersion.v0);
  final message = tx.compiledMessage;
  require(message is encoder.CompiledMessageV0);
  final v0 = message as encoder.CompiledMessageV0;
  final keys = v0.accountKeys.map((key) => key.toBase58()).toList();
  require(
    bytes[0] == 1 &&
        tx.signatures.length == 1 &&
        tx.signatures.single.bytes.every((byte) => byte == 0) &&
        v0.header.numRequiredSignatures == 1 &&
        v0.header.numReadonlySignedAccounts == 0 &&
        v0.addressTableLookups.isEmpty &&
        keys.isNotEmpty &&
        keys.first == owner &&
        keys.toSet().length == keys.length,
  );
  final messageBytes = Uint8List.fromList(v0.toByteArray().toList());
  require(_sameBytes(messageBytes, bytes.sublist(65)));

  // The wallet's own canonical USDC account: the only token account the buy
  // may debit, and the only one the create-idempotent may make.
  final String ownerUsdc;
  try {
    ownerUsdc =
        (await findAssociatedTokenAddress(
          owner: Ed25519HDPublicKey.fromBase58(owner),
          mint: Ed25519HDPublicKey.fromBase58(_usdcMint),
        )).toBase58();
  } catch (_) {
    throw const PantaException(PantaErrorCode.invalidResponse);
  }

  final amount = BigInt.tryParse(amountBaseUnits);
  require(amount != null && amount > BigInt.zero);
  final buyData = [
    ...pantaPrimaryBuyDiscriminator,
    side == Side.yes ? 0 : 1,
    ..._u64le(amount!),
  ];

  // ComputeBudget* -> ATA? -> one buy -> one memo, as the BFF builds it.
  var stage = 0;
  var buys = 0;
  var memos = 0;
  var sawLimit = false;
  var sawPrice = false;
  require(v0.instructions.length >= 2 && v0.instructions.length <= 5);
  for (final ix in v0.instructions) {
    require(ix.programIdIndex > 0 && ix.programIdIndex < keys.length);
    final program = keys[ix.programIdIndex];
    final data = ix.data.toList();
    final accounts = [
      for (final index in ix.accountKeyIndexes)
        index < keys.length ? keys[index] : null,
    ];
    require(accounts.every((account) => account != null));
    switch (program) {
      case _computeBudgetProgram:
        require(stage == 0 && accounts.isEmpty);
        if (data.length == 5 && data[0] == 2 && !sawLimit) {
          sawLimit = true;
          require(_readLe(data, 1, 4) <= BigInt.from(_maxComputeUnits));
        } else if (data.length == 9 && data[0] == 3 && !sawPrice) {
          sawPrice = true;
          require(
            _readLe(data, 1, 8) <= BigInt.from(_maxComputePriceMicroLamports),
          );
        } else {
          require(false);
        }
      case _associatedTokenProgram:
        // CreateIdempotent for the wallet's own USDC account, paid by the
        // wallet — the BFF's exact account list.
        require(
          stage == 0 &&
              data.length == 1 &&
              data[0] == 1 &&
              accounts.length == 6 &&
              accounts[0] == owner &&
              accounts[1] == ownerUsdc &&
              accounts[2] == owner &&
              accounts[3] == _usdcMint &&
              accounts[4] == _systemProgram &&
              accounts[5] == _tokenProgram,
        );
        stage = 1;
      case pantaMainnetProgramId:
        require(
          buys == 0 &&
              stage <= 1 &&
              _sameBytes(data, buyData) &&
              accounts.length == 12 &&
              accounts[0] == owner &&
              accounts[1] == venueMarketId &&
              // USDC, debited from the wallet's own USDC account, through
              // the real Token / ATA / System programs. The market's own
              // PDAs (2–5, 8) are Panta's program's to check.
              accounts[6] == _usdcMint &&
              accounts[7] == ownerUsdc &&
              accounts[9] == _tokenProgram &&
              accounts[10] == _associatedTokenProgram &&
              accounts[11] == _systemProgram,
        );
        buys++;
        stage = 2;
      case _memoProgram:
        require(
          memos == 0 &&
              stage == 2 &&
              accounts.length == 1 &&
              accounts[0] == owner &&
              _isPantaAttribution(data),
        );
        memos++;
        stage = 3;
      default:
        // System, Token, Token-2022 or anything else at the top level: never.
        require(false);
    }
  }
  require(buys == 1 && memos == 1);
  return messageBytes;
}

bool _isPantaAttribution(List<int> data) {
  try {
    final text = String.fromCharCodes(data);
    return text.startsWith('panta:v1:') &&
        text.length <= 256 &&
        RegExp(r'^[ -~]+$').hasMatch(text);
  } catch (_) {
    return false;
  }
}

List<int> _u64le(BigInt value) {
  final out = List<int>.filled(8, 0);
  var rest = value;
  for (var i = 0; i < 8; i++) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  if (rest != BigInt.zero) {
    throw const PantaException(PantaErrorCode.invalidResponse);
  }
  return out;
}

BigInt _readLe(List<int> data, int offset, int length) {
  var value = BigInt.zero;
  for (var i = length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(data[offset + i]);
  }
  return value;
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
