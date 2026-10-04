/// What the app needs from whoever holds the Chumbucket wallet's key.
///
/// The one implementation in the app is [PrivyChumbucketWalletBackend]
/// (`privy_chumbucket_wallet_backend.dart`): a Privy embedded Solana wallet,
/// non-custodial, signed in with the account's own Supabase session, so the
/// same wallet opens on iPhone, Android and the web. Everything above this
/// seam (linking, the Panta signer, deposits) is provider-neutral.
library;

import 'dart:typed_data';

abstract interface class ChumbucketWalletBackend {
  /// Signs in to the wallet provider as [authUserId] (the Supabase `sub`)
  /// with the session's own access token. A provider session that belongs to
  /// anyone else is ended first; a sign-in that answers for anyone else is
  /// refused.
  Future<void> signIn(String authUserId);

  /// The account's Solana wallet at the provider, or null when it has none.
  Future<String?> wallet();

  /// Makes the account's Solana wallet and returns its address.
  Future<String> createWallet();

  /// The 64-byte ed25519 signature of [address] over exactly [message].
  Future<Uint8List> signMessage(String address, Uint8List message);

  /// [address]'s answer to signing [unsigned]: the whole signed transaction,
  /// or the bare 64-byte signature. Never sent anywhere.
  Future<Uint8List> signTransaction(String address, Uint8List unsigned);

  /// Ends the provider session on this device. The wallet stays the account's.
  Future<void> signOut();
}

/// Fixed copy only: provider errors can name keys, users or endpoints.
class ChumbucketWalletException implements Exception {
  const ChumbucketWalletException(this.message);
  final String message;

  static const signedOut = ChumbucketWalletException(
    'Sign in again to use your wallet.',
  );
  static const unavailable = ChumbucketWalletException(
    'Your wallet isn’t reachable right now. Try again in a moment.',
  );
  static const refused = ChumbucketWalletException(
    'Your wallet didn’t sign that.',
  );

  @override
  String toString() => 'ChumbucketWalletException';
}
