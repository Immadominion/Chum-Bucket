/// Wallet apps may rewrite a single-signer transaction before they sign it.
///
/// Solflare and Phantom put their own ComputeBudget limit/price in front and
/// append Lighthouse assertion instructions (checks that fail the transaction
/// if an account ends up different from the wallet's own simulation). The
/// person still approved the reviewed transaction, so the wallet's answer is
/// kept only when nothing reviewed changed:
///
///  - same message version, no address lookup tables, same recent blockhash;
///  - still exactly one signer, the reviewed fee payer;
///  - with ComputeBudget and Lighthouse instructions set aside, the
///    instruction list is the reviewed one: same programs, same accounts with
///    the same signer/writable privileges, same data, same order;
///  - ComputeBudget: no accounts, at most one unit limit (<= 1.4M) and one
///    unit price, nothing else, and a priority fee of at most 0.001 SOL;
///  - Lighthouse: assertion instructions only (never MemoryWrite or
///    MemoryClose, the two that write state), at most two accounts each, at
///    most four of them.
///
/// The server applies the same rule before it broadcasts
/// (chumbucket-social-calls-api `src/prediction/walletAmendment.ts`) and
/// verifies the signature. Both sides are tested against the same vectors,
/// `test/fixtures/wallet_amendment_vectors.json`.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;

const lighthouseProgram = 'L2TExMFKdjpN9kozasaurPirfHy9P8sbXoAN1qA3S95';
const _computeBudgetProgram = 'ComputeBudget111111111111111111111111111111';
const _maxComputeUnits = 1400000;
const _defaultUnitsPerInstruction = 200000;

/// Ceiling on the wallet's priority fee: 0.001 SOL (wallets add ~0.00002-0.0001).
final maxWalletPriorityFeeLamports = BigInt.from(1000000);

/// Lighthouse instruction tags: 0 MemoryWrite, 1 MemoryClose, 2..17 assertions.
const _lighthouseFirstAssertion = 2;
const _lighthouseLastAssertion = 17;
const _maxLighthouseInstructions = 4;

typedef _Account = ({String key, bool signer, bool writable});

class _Instruction {
  const _Instruction(this.program, this.accounts, this.data);
  final String program;
  final List<_Account> accounts;
  final List<int> data;

  bool get isWalletAddition =>
      program == _computeBudgetProgram || program == lighthouseProgram;

  bool sameAs(_Instruction other) {
    if (program != other.program ||
        !_sameBytes(data, other.data) ||
        accounts.length != other.accounts.length) {
      return false;
    }
    for (var i = 0; i < accounts.length; i++) {
      if (accounts[i] != other.accounts[i]) return false;
    }
    return true;
  }
}

List<_Instruction> _decompile(encoder.CompiledMessage message) {
  final keys = message.accountKeys.map((key) => key.toBase58()).toList();
  final header = message.header;
  final signers = header.numRequiredSignatures;
  bool writable(int i) =>
      i < signers
          ? i < signers - header.numReadonlySignedAccounts
          : i < keys.length - header.numReadonlyUnsignedAccounts;
  return [
    for (final ix in message.instructions)
      _Instruction(keys[ix.programIdIndex], [
        for (final i in ix.accountKeyIndexes)
          (key: keys[i], signer: i < signers, writable: writable(i)),
      ], ix.data.toList()),
  ];
}

bool _hasLookups(encoder.CompiledMessage message) => message.map(
  legacy: (_) => false,
  v0: (v0) => v0.addressTableLookups.isNotEmpty,
);

int _u32(List<int> data, int offset) =>
    ByteData.sublistView(
      Uint8List.fromList(data),
    ).getUint32(offset, Endian.little);

BigInt _u64(List<int> data, int offset) {
  var value = BigInt.zero;
  for (var i = 7; i >= 0; i--) {
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

/// Null when [signed] is [reviewed] as a wallet app may amend it; otherwise
/// why not. Looks at the messages only: the signature is the server's check.
String? walletAmendmentRefusal(Uint8List reviewed, Uint8List signed) {
  try {
    final before = encoder.SignedTx.fromBytes(reviewed).compiledMessage;
    final after = encoder.SignedTx.fromBytes(signed).compiledMessage;
    if (before.version != after.version) return 'message version changed';
    if (_hasLookups(before) || _hasLookups(after)) {
      return 'address lookup tables';
    }
    if (before.recentBlockhash != after.recentBlockhash) {
      return 'recent blockhash changed';
    }
    if (before.header.numRequiredSignatures != 1 ||
        after.header.numRequiredSignatures != 1) {
      return 'signer set changed';
    }
    if (before.accountKeys.isEmpty ||
        after.accountKeys.isEmpty ||
        before.accountKeys.first.toBase58() !=
            after.accountKeys.first.toBase58()) {
      return 'fee payer changed';
    }

    final signedInstructions = _decompile(after);
    final kept = signedInstructions.where((ix) => !ix.isWalletAddition).toList();
    final core =
        _decompile(before).where((ix) => !ix.isWalletAddition).toList();
    if (kept.length != core.length) return 'reviewed instructions changed';
    for (var i = 0; i < kept.length; i++) {
      if (!kept[i].sameAs(core[i])) return 'reviewed instructions changed';
    }

    int? units;
    BigInt? price;
    var lighthouse = 0;
    for (final ix in signedInstructions) {
      if (ix.program == _computeBudgetProgram) {
        if (ix.accounts.isNotEmpty) return 'ComputeBudget with accounts';
        if (ix.data.length == 5 && ix.data[0] == 2 && units == null) {
          final limit = _u32(ix.data, 1);
          if (limit <= 0 || limit > _maxComputeUnits) {
            return 'compute unit limit out of range';
          }
          units = limit;
        } else if (ix.data.length == 9 && ix.data[0] == 3 && price == null) {
          price = _u64(ix.data, 1);
        } else {
          return 'unsupported or repeated ComputeBudget instruction';
        }
      } else if (ix.program == lighthouseProgram) {
        if (ix.data.isEmpty ||
            ix.data[0] < _lighthouseFirstAssertion ||
            ix.data[0] > _lighthouseLastAssertion) {
          return 'Lighthouse instruction is not an assertion';
        }
        if (ix.accounts.length > 2) {
          return 'Lighthouse assertion with too many accounts';
        }
        if (++lighthouse > _maxLighthouseInstructions) {
          return 'too many Lighthouse assertions';
        }
      }
    }
    if (price != null && price > BigInt.zero) {
      final nonBudget =
          signedInstructions
              .where((ix) => ix.program != _computeBudgetProgram)
              .length;
      final limit = BigInt.from(
        units ??
            math.min(_maxComputeUnits, _defaultUnitsPerInstruction * nonBudget),
      );
      final fee =
          (limit * price + BigInt.from(999999)) ~/ BigInt.from(1000000);
      if (fee > maxWalletPriorityFeeLamports) {
        return 'wallet priority fee above the ceiling';
      }
    }
    return null;
  } catch (_) {
    return 'unreadable transaction';
  }
}

/// The wallet app's whole signed transaction, kept when it is [unsigned] as a
/// wallet may amend it ([walletAmendmentRefusal]) with the one signature slot
/// filled. A bare 64-byte signature can only sign the exact reviewed bytes, so
/// it is never an amendment. Null otherwise.
Uint8List? adoptWalletAmendment(Uint8List unsigned, Uint8List answer) {
  if (answer.length == 64) return null;
  try {
    final tx = encoder.SignedTx.fromBytes(answer);
    if (tx.signatures.length != 1 ||
        tx.signatures.single.bytes.every((byte) => byte == 0) ||
        !_sameBytes(tx.toByteArray().toList(), answer)) {
      return null;
    }
    if (walletAmendmentRefusal(unsigned, answer) != null) return null;
    return Uint8List.fromList(answer);
  } catch (_) {
    return null;
  }
}
