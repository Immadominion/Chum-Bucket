import 'dart:async';
import 'dart:typed_data';

/// A snapshot from the existing canonical Supabase session. The account ID is
/// only compared locally. Only the access token enters the Authorization header.
class PantaSession {
  const PantaSession({required this.accountId, required this.accessToken});
  final String accountId;
  final String accessToken;
}

typedef PantaSessionProvider = FutureOr<PantaSession?> Function();
typedef PantaSelectedWalletProvider = FutureOr<String?> Function();

/// Main wraps MwaAuthProvider.createSigningSession + signTransactions here.
/// The implementation MUST check that the MWA-authorized selected address is
/// the reviewed wallet, including after authorization. It must return signed
/// serialized bytes and must never broadcast. Throw PantaWalletCancelled when
/// the user declines; other SDK errors are reduced to fixed local copy.
abstract interface class PantaWalletPort {
  Future<Uint8List> signTransaction(Uint8List unsigned);
}

class PantaWalletCancelled implements Exception {
  const PantaWalletCancelled();
}
