import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';

import '../domain/deposit_wallet_source.dart';

/// The connected Mobile Wallet Adapter wallet. Captured once: if the person
/// switches or disconnects wallets afterwards, [isCurrent] turns false and
/// signing is refused rather than signing with a different key.
class MwaDepositWalletSource implements DepositWalletSource {
  MwaDepositWalletSource(this._auth)
    : address = _auth.walletAddress,
      _revision = _auth.authRevision;

  final MwaAuthProvider _auth;
  final int _revision;

  @override
  final String? address;

  @override
  DepositWalletKind get kind => DepositWalletKind.mwa;

  @override
  bool get isCurrent =>
      _auth.isAuthenticated &&
      address != null &&
      _auth.walletAddress == address &&
      _auth.authRevision == _revision;

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    final publicKey = _auth.publicKeyBytes;
    if (!isCurrent ||
        publicKey == null ||
        publicKey.length != 32 ||
        base58encode(publicKey) != address) {
      throw const DepositWalletDeclined();
    }
    final signing = await _auth.createSigningSession();
    if (signing == null) throw const DepositWalletDeclined();
    try {
      if (!isCurrent) throw const DepositWalletDeclined();
      final result = await signing.signMessages(
        messages: [message],
        addresses: [publicKey],
      );
      if (!isCurrent || result.signedMessages.length != 1) {
        throw const DepositWalletDeclined();
      }
      final signed = result.signedMessages.single;
      // A wallet that altered the bytes, signed with another key or returned
      // extra signatures is treated as a refusal, never forwarded.
      if (!listEquals(signed.message, message) ||
          signed.addresses.length != 1 ||
          !listEquals(signed.addresses.single, publicKey) ||
          signed.signatures.length != 1 ||
          signed.signatures.single.length != 64) {
        throw const DepositWalletDeclined();
      }
      return Uint8List.fromList(signed.signatures.single);
    } on DepositWalletDeclined {
      rethrow;
    } catch (_) {
      // Platform errors can embed session material; fixed outcome only.
      throw const DepositWalletDeclined();
    } finally {
      try {
        await signing.close();
      } catch (_) {
        /* Never log session errors. */
      }
    }
  }
}
