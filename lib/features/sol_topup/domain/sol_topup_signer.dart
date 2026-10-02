/// Who signs a gasless swap: the person's own wallet, and only after
/// [checkGaslessSwap] passed. Two kinds, the same two as Panta trades:
///
///  * a wallet app over Mobile Wallet Adapter, which shows its own approval
///    and simulation; the returned transaction must carry the identical
///    message with a valid signature from the reviewed wallet in its slot and
///    every other slot untouched;
///  * the wallet that lives on this phone, whose approval is the review
///    sheet's button — it signs exactly the checked message bytes, nothing
///    else.
///
/// Neither ever broadcasts: the BFF forwards the signed bytes to Jupiter.
library;

import 'dart:typed_data';

import 'package:solana/solana.dart' show Ed25519HDPublicKey, verifySignature;

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';

import 'gasless_swap_check.dart';

enum TopUpSignerKind { walletApp, thisPhone }

/// The person said no in their wallet app. Nothing was signed.
class TopUpSignCancelled implements Exception {
  const TopUpSignCancelled();
}

/// The wallet changed, or returned something other than the reviewed swap.
class TopUpSignRefused implements Exception {
  const TopUpSignRefused();
}

abstract interface class SolTopUpSigner {
  String get address;
  TopUpSignerKind get kind;

  /// The full signed transaction: [unsigned] with the person's signature in
  /// [CheckedSwap.ownerSignatureIndex], nothing else changed.
  Future<Uint8List> sign(Uint8List unsigned, CheckedSwap checked);
}

int _slot(int index) => 1 + 64 * index;

/// The message of [tx], after its signature slots.
Uint8List _messageOf(Uint8List tx) {
  final count = tx.isEmpty ? 0 : tx[0];
  if (count < 1 || count > 3 || tx.length <= _slot(count)) {
    throw const TopUpSignRefused();
  }
  return Uint8List.sublistView(tx, _slot(count));
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The checks on a signed swap, whoever produced it.
Future<Uint8List> acceptSignedSwap({
  required Uint8List unsigned,
  required Uint8List signed,
  required CheckedSwap checked,
  required String address,
}) async {
  final message = _messageOf(unsigned);
  if (!_same(message, checked.messageBytes) ||
      signed.length != unsigned.length ||
      signed[0] != unsigned[0] ||
      !_same(_messageOf(signed), message)) {
    throw const TopUpSignRefused();
  }
  for (var i = 0; i < unsigned[0]; i++) {
    final before = Uint8List.sublistView(unsigned, _slot(i), _slot(i) + 64);
    final after = Uint8List.sublistView(signed, _slot(i), _slot(i) + 64);
    if (i == checked.ownerSignatureIndex) {
      if (after.every((b) => b == 0)) throw const TopUpSignRefused();
      final valid = await verifySignature(
        message: message,
        signature: after,
        publicKey: Ed25519HDPublicKey.fromBase58(address),
      );
      if (!valid) throw const TopUpSignRefused();
    } else if (!_same(before, after)) {
      throw const TopUpSignRefused();
    }
  }
  return Uint8List.fromList(signed);
}

class EmbeddedSolTopUpSigner implements SolTopUpSigner {
  EmbeddedSolTopUpSigner({
    required EmbeddedWalletKey? Function() signer,
    required this.address,
  }) : _signer = signer;

  /// Re-read at signing: a different account or wallet yields another key.
  final EmbeddedWalletKey? Function() _signer;

  @override
  final String address;

  @override
  TopUpSignerKind get kind => TopUpSignerKind.thisPhone;

  @override
  Future<Uint8List> sign(Uint8List unsigned, CheckedSwap checked) async {
    final key = _signer();
    if (key == null || key.address != address) throw const TopUpSignRefused();
    if (!_same(_messageOf(unsigned), checked.messageBytes)) {
      throw const TopUpSignRefused();
    }
    final signature = await key.sign(checked.messageBytes);
    if (signature.length != 64) throw const TopUpSignRefused();
    final signed = Uint8List.fromList(unsigned);
    signed.setRange(
      _slot(checked.ownerSignatureIndex),
      _slot(checked.ownerSignatureIndex) + 64,
      signature,
    );
    return acceptSignedSwap(
      unsigned: unsigned,
      signed: signed,
      checked: checked,
      address: address,
    );
  }
}

class MwaSolTopUpSigner implements SolTopUpSigner {
  MwaSolTopUpSigner(this._auth)
    : address = _auth.walletAddress ?? '',
      _revision = _auth.authRevision;

  final MwaAuthProvider _auth;
  final int _revision;

  @override
  final String address;

  @override
  TopUpSignerKind get kind => TopUpSignerKind.walletApp;

  bool get _current =>
      _auth.isAuthenticated &&
      address.isNotEmpty &&
      _auth.walletAddress == address &&
      _auth.authRevision == _revision;

  @override
  Future<Uint8List> sign(Uint8List unsigned, CheckedSwap checked) async {
    if (!_current) throw const TopUpSignRefused();
    final signing = await _auth.createSigningSession(
      cluster: NetworkConfig.mainnetBeta,
    );
    if (signing == null) throw const TopUpSignCancelled();
    try {
      if (!_current) throw const TopUpSignRefused();
      final result = await signing.signTransactions(transactions: [unsigned]);
      if (!_current || result.signedPayloads.length != 1) {
        throw const TopUpSignRefused();
      }
      return await acceptSignedSwap(
        unsigned: unsigned,
        signed: result.signedPayloads.single,
        checked: checked,
        address: address,
      );
    } on TopUpSignRefused {
      rethrow;
    } catch (_) {
      // SDK errors can carry session material; a fixed outcome only.
      throw const TopUpSignCancelled();
    } finally {
      try {
        await signing.close();
      } catch (_) {
        /* Never log session errors. */
      }
    }
  }
}
