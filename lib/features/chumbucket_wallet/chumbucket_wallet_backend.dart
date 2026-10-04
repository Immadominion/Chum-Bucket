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
  /// Signs in to the wallet provider as [account] (`public.users.id`, the
  /// `sub` of the BFF's account token). A provider session that belongs to
  /// anyone else is ended first; a sign-in that answers for anyone else is
  /// refused. Every later call refuses with [ChumbucketWalletException.signedOut]
  /// once the provider is no longer signed in as [account].
  Future<void> signIn(String account);

  // Every call below names the account it expects and refuses with
  // [ChumbucketWalletException.signedOut] unless the provider is signed in as
  // exactly that account right now.

  /// The account's Solana wallet at the provider, or null when it has none.
  Future<String?> wallet(String account);

  /// Makes the account's Solana wallet and returns its address.
  Future<String> createWallet(String account);

  /// The 64-byte ed25519 signature of [address] over exactly [message].
  Future<Uint8List> signMessage(
    String account,
    String address,
    Uint8List message,
  );

  /// [address]'s answer to signing [unsigned]: the whole signed transaction,
  /// or the bare 64-byte signature. Never sent anywhere.
  Future<Uint8List> signTransaction(
    String account,
    String address,
    Uint8List unsigned,
  );

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

/// Which account the provider is signed in as, safe against interleaving: a
/// sign-in that finishes after a later sign-in or sign-out began can never
/// settle. Every sign-in and sign-out [begin]s a new generation; only the
/// newest may [settle].
class ProviderAccountGate {
  int _generation = 0;
  String? _account;

  String? get account => _account;

  /// A sign-in or sign-out begins: nothing started before it may settle.
  int begin() {
    _account = null;
    return ++_generation;
  }

  /// The sign-in that began as [generation] finished for [account]; kept only
  /// when nothing began since. False when it came too late.
  bool settle(int generation, String account) {
    if (generation != _generation) return false;
    _account = account;
    return true;
  }

  bool holds(String account) => _account != null && _account == account;

  /// The provider answered for someone else, or not at all.
  void forget() => _account = null;
}
