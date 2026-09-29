import 'dart:typed_data';

import 'package:chumbucket/core/config/network_config.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';

/// Reuses the existing wallet connection. Signs only; the BFF owns broadcast.
class PantaMwaWallet implements PantaWalletPort {
  PantaMwaWallet(this._auth)
    : _address = _auth.walletAddress,
      _revision = _auth.authRevision;

  final MwaAuthProvider _auth;
  final String? _address;
  final int _revision;

  void _check() {
    if (!_auth.isAuthenticated ||
        _address == null ||
        _auth.walletAddress != _address ||
        _auth.authRevision != _revision) {
      throw const PantaException(PantaErrorCode.walletChanged);
    }
  }

  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    _check();
    final signing = await _auth.createSigningSession(
      cluster: NetworkConfig.mainnetBeta,
    );
    if (signing == null) throw const PantaWalletCancelled();
    try {
      _check();
      final result = await signing.signTransactions(transactions: [unsigned]);
      _check();
      if (result.signedPayloads.length != 1) {
        throw const PantaException(PantaErrorCode.signingFailed);
      }
      return result.signedPayloads.single;
    } on PantaException {
      rethrow;
    } catch (_) {
      // SDK errors can contain transaction/session material; fixed local copy only.
      throw const PantaWalletCancelled();
    } finally {
      try {
        await signing.close();
      } catch (_) {
        /* Never log session errors. */
      }
    }
  }
}
