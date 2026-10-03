/// Signs a reviewed Panta win claim with the wallet that lives on this phone.
///
/// A wallet app shows its own simulation before approving; an on-phone key
/// has none, so — like the buy signer (`panta_embedded_wallet.dart`) — this
/// refuses anything but the claim that was reviewed
/// ([PantaClaimSigningIntent]):
///
///  * one v0 transaction, no lookup tables, exactly one signer — this wallet,
///    the intent's owner, also the fee payer — with an empty signature slot;
///  * only what the BFF lets a claim contain (`PantaClaimExecution`), in its
///    order: bounded ComputeBudget, the owner's own USDC account
///    (create-if-missing, paid by the owner), ONE `claim_win_usdc` on Panta's
///    mainnet program, and at most one owner-signed text memo;
///  * the claim in the layout Panta's program uses on mainnet (read from real
///    `ClaimWinUsdc` transactions on 3 October 2026): the owner first and as
///    its only argument, Panta's config, the REVIEWED market, the vault, and
///    the owner's own canonical USDC account as the account paid;
///  * no System or Token instruction at the top level, so nothing can move SOL
///    or USDC anywhere else.
///
/// The transaction does not carry the outcome or the shares — the program
/// pays what the position holds — so those are checked as the review the
/// person approved: a YES/NO win of a positive number of shares. The BFF
/// broadcasts and confirms the USDC credit on-chain; this only signs.
library;

import 'dart:typed_data';

import 'package:solana/encoder.dart' as encoder;
import 'package:solana/solana.dart'
    show Ed25519HDPublicKey, findAssociatedTokenAddress;

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

import 'embedded_wallet_key.dart';
import 'panta_embedded_wallet.dart' show pantaMainnetProgramId;

const _computeBudget = 'ComputeBudget111111111111111111111111111111';
const _ata = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _memo = 'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _system = '11111111111111111111111111111111';
const _usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

/// sha256("global:claim_win_usdc")[0..8] (`CLAIM_WIN_DISCRIMINATOR` in the
/// BFF), the instruction mainnet logs as `ClaimWinUsdc`.
const pantaClaimWinDiscriminator = [
  0x2b,
  0xa0,
  0x6a,
  0x33,
  0xa7,
  0x4c,
  0x14,
  0x1f,
];

/// The BFF's ceilings for a claim (`PantaClaimExecution`).
const _maxComputeUnits = 1400000;
const _maxComputePrice = 1000000;

/// `winningShares` as the BFF sends it: a positive decimal.
final _shares = RegExp(r'^(0|[1-9][0-9]{0,30})(\.[0-9]{1,18})?$');

class PantaEmbeddedClaimWallet implements PantaWalletPort {
  PantaEmbeddedClaimWallet({
    required EmbeddedWalletKey? Function() signer,
    required this.intent,
  }) : _signer = signer;

  /// Re-read at signing: a different account or wallet yields another key.
  final EmbeddedWalletKey? Function() _signer;
  final PantaClaimSigningIntent intent;

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    final key = _signer();
    if (key == null || key.address != intent.owner) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
    final message = await checkPantaClaimForEmbeddedSigning(unsigned, intent);
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

/// The exact message bytes to sign, or [PantaErrorCode.invalidResponse] for
/// anything but the claim in [intent].
Future<Uint8List> checkPantaClaimForEmbeddedSigning(
  Uint8List bytes,
  PantaClaimSigningIntent intent,
) async {
  void require(bool condition) {
    if (!condition) throw const PantaException(PantaErrorCode.invalidResponse);
  }

  // The review: a win, for a positive number of shares.
  require(intent.outcome == Side.yes || intent.outcome == Side.no);
  require(
    _shares.hasMatch(intent.winningShares) &&
        RegExp('[1-9]').hasMatch(intent.winningShares),
  );

  final encoder.SignedTx tx;
  final String ownerUsdc;
  final List<int> ownerBytes;
  try {
    require(bytes.length > 65 && bytes.length <= 1232);
    tx = encoder.SignedTx.fromBytes(bytes);
    final owner = Ed25519HDPublicKey.fromBase58(intent.owner);
    ownerBytes = owner.bytes;
    ownerUsdc =
        (await findAssociatedTokenAddress(
          owner: owner,
          mint: Ed25519HDPublicKey.fromBase58(_usdc),
        )).toBase58();
    Ed25519HDPublicKey.fromBase58(intent.venueMarketId);
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
  final header = v0.header;
  require(
    bytes[0] == 1 &&
        tx.signatures.length == 1 &&
        tx.signatures.single.bytes.every((byte) => byte == 0) &&
        header.numRequiredSignatures == 1 &&
        header.numReadonlySignedAccounts == 0 &&
        v0.addressTableLookups.isEmpty &&
        keys.isNotEmpty &&
        keys.first == intent.owner &&
        keys.toSet().length == keys.length &&
        intent.venueMarketId != intent.owner,
  );
  final messageBytes = Uint8List.fromList(v0.toByteArray().toList());
  require(_same(messageBytes, bytes.sublist(65)));
  final readonlyFrom = keys.length - header.numReadonlyUnsignedAccounts;

  final claimData = [...pantaClaimWinDiscriminator, ...ownerBytes];

  // ComputeBudget* -> ATA? -> one claim -> Memo?, as the BFF allows it.
  var stage = 0;
  var sawLimit = false, sawPrice = false, claims = 0, memos = 0;
  require(v0.instructions.isNotEmpty && v0.instructions.length <= 6);
  for (final ix in v0.instructions) {
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
    require(accounts.every((account) => account != null));
    switch (program) {
      case _computeBudget:
        require(stage == 0 && accounts.isEmpty);
        if (data.length == 5 && data[0] == 2 && !sawLimit) {
          sawLimit = true;
          final units = _le(data, 1, 4);
          require(
            units > BigInt.zero && units <= BigInt.from(_maxComputeUnits),
          );
        } else if (data.length == 9 && data[0] == 3 && !sawPrice) {
          sawPrice = true;
          require(_le(data, 1, 8) <= BigInt.from(_maxComputePrice));
        } else {
          require(false);
        }
      case _ata:
        // CreateIdempotent of the owner's own USDC account, paid by the owner.
        require(
          stage == 0 &&
              data.length == 1 &&
              data[0] == 1 &&
              accounts.length == 6 &&
              accounts[0] == intent.owner &&
              accounts[1] == ownerUsdc &&
              accounts[2] == intent.owner &&
              accounts[3] == _usdc &&
              accounts[4] == _system &&
              accounts[5] == _token,
        );
        stage = 1;
      case pantaMainnetProgramId:
        require(
          claims == 0 &&
              stage <= 1 &&
              _same(data, claimData) &&
              accounts.length == 12 &&
              accounts.toSet().length == 12 &&
              accounts[0] == intent.owner &&
              accounts[2] == intent.venueMarketId &&
              // Paid into the owner's own canonical USDC account, through the
              // real Token / ATA / System programs. Panta's config, vault and
              // PDAs (1, 3–6) are the program's to check.
              accounts[7] == ownerUsdc &&
              accounts[8] == _usdc &&
              accounts[9] == _token &&
              accounts[10] == _ata &&
              accounts[11] == _system,
        );
        claims++;
        stage = 2;
      case _memo:
        require(
          memos == 0 &&
              stage == 2 &&
              accounts.length == 1 &&
              accounts[0] == intent.owner &&
              data.length <= 566 &&
              data.every((byte) => byte >= 0x20 && byte < 0x7f),
        );
        memos++;
        stage = 3;
      default:
        // System, Token or anything else at the top level: never.
        require(false);
    }
  }
  require(claims == 1);
  return messageBytes;
}

/// Unsigned little-endian, as a BigInt: a u64 never wraps negative.
BigInt _le(List<int> data, int offset, int length) {
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
