/// The check every signer runs on a USDC transfer before it signs — the
/// Chumbucket wallet, the wallet on this phone, and a wallet app over Mobile
/// Wallet Adapter alike (a wallet app shows its own simulation too, but the
/// phone refuses a bad transfer before it ever opens one).
///
/// The money contract, section (c): one v0 transaction, no address lookup
/// tables, signatures empty, exactly one signer — `from`, also the fee payer.
/// Instructions, in this order and nothing else:
///
///  1. 0–2 Compute Budget: `SetComputeUnitLimit` (≤ 200 000) and/or
///     `SetComputeUnitPrice` (≤ 1 000 000 micro-lamports), each at most once;
///  2. only when the review says it creates the account: one Associated
///     Token Account `CreateIdempotent` (data `[1]`), accounts exactly
///     `[from, ata(to), to, USDC, System, Token]`;
///  3. exactly one SPL Token `TransferChecked` (data `[12, amount u64 LE, 6]`),
///     accounts exactly `[ata(from), USDC, ata(to), from]`.
///
/// No System transfer, no other program. `ata(x)` is x's canonical mainnet
/// USDC account. The web's twin is `checkUsdcTransfer` in
/// `web/lib/webapp/transferCheck.ts`.
library;

import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;
import 'package:solana/solana.dart'
    show Ed25519HDPublicKey, findAssociatedTokenAddress;

import '../data/money_models.dart' show TransferReview;

const usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const _computeBudget = 'ComputeBudget111111111111111111111111111111';
const _associatedToken = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _system = '11111111111111111111111111111111';

const maxTransferComputeUnits = 200000;
const maxTransferComputePrice = 1000000;

/// The transfer did not match what was reviewed. Nothing was signed.
class TransferCheckException implements Exception {
  const TransferCheckException(this.reason);
  final String reason;
  @override
  String toString() => 'TransferCheckException($reason)';
}

/// What the person reviewed: who pays, who receives, how much, and whether
/// the receiver's USDC account is made on the way.
class ExpectedUsdcTransfer {
  const ExpectedUsdcTransfer({
    required this.from,
    required this.to,
    required this.amountBaseUnits,
    required this.createsAccount,
  });

  final String from;
  final String to;
  final BigInt amountBaseUnits;
  final bool createsAccount;

  /// The server's review, held to what the person asked for: the same
  /// payer, receiver and amount, or nothing is signed.
  factory ExpectedUsdcTransfer.fromReview(
    TransferReview review, {
    required String from,
    required String to,
    required BigInt amountBaseUnits,
  }) {
    if (review.from != from ||
        review.to != to ||
        review.amountBaseUnits != amountBaseUnits) {
      throw const TransferCheckException('review differs from the request');
    }
    return ExpectedUsdcTransfer(
      from: from,
      to: to,
      amountBaseUnits: amountBaseUnits,
      createsAccount: review.createsAccount,
    );
  }
}

/// Returns the exact message bytes to sign, or throws
/// [TransferCheckException] for anything but [expected].
Future<Uint8List> checkUsdcTransfer(
  Uint8List bytes,
  ExpectedUsdcTransfer expected,
) async {
  void require(bool condition, String reason) {
    if (!condition) throw TransferCheckException(reason);
  }

  final encoder.SignedTx tx;
  try {
    require(bytes.length > 65 && bytes.length <= 1232, 'size');
    tx = encoder.SignedTx.fromBytes(bytes);
  } on TransferCheckException {
    rethrow;
  } catch (_) {
    throw const TransferCheckException('not a transaction');
  }
  require(tx.version == encoder.TransactionVersion.v0, 'not v0');
  final message = tx.compiledMessage;
  require(message is encoder.CompiledMessageV0, 'not v0');
  final v0 = message as encoder.CompiledMessageV0;
  final keys = v0.accountKeys.map((key) => key.toBase58()).toList();
  require(
    bytes[0] == 1 &&
        tx.signatures.length == 1 &&
        tx.signatures.single.bytes.every((byte) => byte == 0),
    'signatures',
  );
  require(
    v0.header.numRequiredSignatures == 1 &&
        v0.header.numReadonlySignedAccounts == 0,
    'one signer',
  );
  require(v0.addressTableLookups.isEmpty, 'lookup tables');
  require(keys.isNotEmpty && keys.first == expected.from, 'fee payer');
  require(keys.toSet().length == keys.length, 'duplicate keys');
  require(expected.from != expected.to, 'same wallet');
  final messageBytes = Uint8List.fromList(v0.toByteArray().toList());
  require(_same(messageBytes, bytes.sublist(65)), 'message');

  final String fromUsdc;
  final String toUsdc;
  try {
    fromUsdc = await _usdcAccount(expected.from);
    toUsdc = await _usdcAccount(expected.to);
  } catch (_) {
    throw const TransferCheckException('address');
  }

  final amount = expected.amountBaseUnits;
  require(amount > BigInt.zero, 'amount');
  final transferData = [12, ..._u64le(amount), 6];

  var stage = 0; // 0 compute, 1 account made, 2 transferred
  var sawLimit = false;
  var sawPrice = false;
  var creates = 0;
  var transfers = 0;
  require(v0.instructions.isNotEmpty && v0.instructions.length <= 4, 'count');
  for (final ix in v0.instructions) {
    require(
      ix.programIdIndex > 0 && ix.programIdIndex < keys.length,
      'program index',
    );
    final program = keys[ix.programIdIndex];
    final data = ix.data.toList();
    final accounts = <String>[];
    for (final index in ix.accountKeyIndexes) {
      require(index < keys.length, 'account index');
      accounts.add(keys[index]);
    }
    switch (program) {
      case _computeBudget:
        require(stage == 0 && accounts.isEmpty, 'compute budget');
        if (data.length == 5 && data[0] == 2 && !sawLimit) {
          sawLimit = true;
          require(
            _readLe(data, 1, 4) <= BigInt.from(maxTransferComputeUnits),
            'compute limit',
          );
        } else if (data.length == 9 && data[0] == 3 && !sawPrice) {
          sawPrice = true;
          require(
            _readLe(data, 1, 8) <= BigInt.from(maxTransferComputePrice),
            'compute price',
          );
        } else {
          require(false, 'compute budget');
        }
      case _associatedToken:
        require(expected.createsAccount && creates == 0, 'account creation');
        require(
          stage == 0 &&
              data.length == 1 &&
              data[0] == 1 &&
              accounts.length == 6 &&
              accounts[0] == expected.from &&
              accounts[1] == toUsdc &&
              accounts[2] == expected.to &&
              accounts[3] == usdcMint &&
              accounts[4] == _system &&
              accounts[5] == _token,
          'account creation',
        );
        creates++;
        stage = 1;
      case _token:
        require(
          transfers == 0 &&
              stage <= 1 &&
              _same(data, transferData) &&
              accounts.length == 4 &&
              accounts[0] == fromUsdc &&
              accounts[1] == usdcMint &&
              accounts[2] == toUsdc &&
              accounts[3] == expected.from,
          'transfer',
        );
        transfers++;
        stage = 2;
      default:
        // System, Token-2022, a memo, or anything else: never.
        require(false, 'program');
    }
  }
  require(transfers == 1, 'transfer');
  require(creates == (expected.createsAccount ? 1 : 0), 'account creation');
  return messageBytes;
}

Future<String> _usdcAccount(String owner) async =>
    (await findAssociatedTokenAddress(
      owner: Ed25519HDPublicKey.fromBase58(owner),
      mint: Ed25519HDPublicKey.fromBase58(usdcMint),
    )).toBase58();

List<int> _u64le(BigInt value) {
  final out = List<int>.filled(8, 0);
  var rest = value;
  for (var i = 0; i < 8; i++) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  if (rest != BigInt.zero) throw const TransferCheckException('amount');
  return out;
}

BigInt _readLe(List<int> data, int offset, int length) {
  var value = BigInt.zero;
  for (var i = length - 1; i >= 0; i--) {
    value = (value << 8) | BigInt.from(data[offset + i]);
  }
  return value;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
