/// The Chumbucket wallet on Privy: an embedded Solana wallet, non-custodial,
/// whose key Privy rebuilds in its secure enclave for this account only.
///
/// Privy signs the person in with the BFF's own account token (JWT-based
/// custom auth: Privy verifies it against the BFF's JWKS, `sub` = the
/// account), so every sign-in of one account reaches the same wallet on any
/// device, with no prompt. The token provider is `ChumbucketPrivyTokens`,
/// which fetches a fresh one before it expires; Privy asks again whenever it
/// needs one.
///
/// Every read of the Privy user checks it is the account this backend signed
/// in as: a session left over from another account (an earlier run, a
/// sign-out that never reached Privy) is never used to sign.
///
/// Signing is sign-only: [signTransaction] returns bytes, and the BFF checks
/// and broadcasts them. Nothing here sends a transaction.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:privy_flutter/privy_flutter.dart';

import 'chumbucket_wallet_backend.dart';

class PrivyChumbucketWalletBackend implements ChumbucketWalletBackend {
  PrivyChumbucketWalletBackend({
    required String appId,
    required String clientId,
    required Future<String?> Function() accountToken,
  }) : _appId = appId,
       _clientId = clientId,
       _accountToken = accountToken;

  final String _appId;
  final String _clientId;
  final Future<String?> Function() _accountToken;

  /// Made on first use: an account that never needs its wallet never starts
  /// a Privy session (Privy prices by monthly active users).
  late final Privy _privy = Privy.init(
    config: PrivyConfig(
      appId: _appId,
      appClientId: _clientId,
      logLevel: PrivyLogLevel.none,
      customAuthConfig: LoginWithCustomAuthConfig(tokenProvider: _accountToken),
    ),
  );

  /// Which account the provider is signed in as (generation-guarded).
  final _gate = ProviderAccountGate();

  static bool _isFor(PrivyUser user, String account) =>
      privyUserIsAccount(user.linkedAccounts, account);

  /// The signed-in Privy user, only while it is exactly [account].
  Future<PrivyUser> _user(String account) async {
    if (!_gate.holds(account)) throw ChumbucketWalletException.signedOut;
    final AuthState state;
    try {
      state = await _privy.getAuthState();
    } catch (_) {
      throw ChumbucketWalletException.unavailable;
    }
    if (_gate.holds(account) &&
        state is Authenticated &&
        _isFor(state.user, account)) {
      return state.user;
    }
    _gate.forget();
    throw ChumbucketWalletException.signedOut;
  }

  Future<EmbeddedSolanaWallet> _walletAt(String account, String address) async {
    for (final wallet in (await _user(account)).embeddedSolanaWallets) {
      if (wallet.address == address) return wallet;
    }
    throw ChumbucketWalletException.signedOut;
  }

  @override
  Future<void> signIn(String account) async {
    final generation = _gate.begin();
    final AuthState state;
    try {
      state = await _privy.getAuthState();
    } catch (_) {
      throw ChumbucketWalletException.unavailable;
    }
    if (state is Authenticated && _isFor(state.user, account)) {
      if (!_gate.settle(generation, account)) {
        throw ChumbucketWalletException.signedOut;
      }
      return;
    }
    if (state is Authenticated || state is AuthenticatedUnverified) {
      await _privy.logout();
    }
    final Result<PrivyUser> result;
    try {
      result = await _privy.customAuth.loginWithCustomAccessToken();
    } catch (_) {
      throw ChumbucketWalletException.unavailable;
    }
    switch (result) {
      case Success<PrivyUser>(:final value):
        if (!_isFor(value, account)) {
          await _privy.logout();
          throw ChumbucketWalletException.signedOut;
        }
        // A sign-out or another sign-in that began meanwhile wins.
        if (!_gate.settle(generation, account)) {
          throw ChumbucketWalletException.signedOut;
        }
      case Failure<PrivyUser>():
        throw ChumbucketWalletException.unavailable;
    }
  }

  @override
  Future<String?> wallet(String account) async {
    final wallets = (await _user(account)).embeddedSolanaWallets;
    return wallets.isEmpty ? null : wallets.first.address;
  }

  @override
  Future<String> createWallet(String account) async {
    final result = await (await _user(account)).createSolanaWallet();
    return switch (result) {
      Success<EmbeddedSolanaWallet>(:final value) => value.address,
      Failure<EmbeddedSolanaWallet>() =>
        throw ChumbucketWalletException.unavailable,
    };
  }

  @override
  Future<Uint8List> signMessage(
    String account,
    String address,
    Uint8List message,
  ) async {
    final wallet = await _walletAt(account, address);
    // Privy takes the message and answers the signature, both base64.
    final result = await wallet.provider.signMessage(base64Encode(message));
    return _bytes(result);
  }

  @override
  Future<Uint8List> signTransaction(
    String account,
    String address,
    Uint8List unsigned,
  ) async {
    final wallet = await _walletAt(account, address);
    return _bytes(await wallet.provider.signTransaction(unsigned));
  }

  @override
  Future<void> signOut() async {
    _gate.begin();
    try {
      await _privy.logout();
    } catch (_) {
      // Nothing to end.
    }
  }

  static Uint8List _bytes(Result<String> result) => switch (result) {
    Success<String>(:final value) => _decode(value),
    Failure<String>() => throw ChumbucketWalletException.refused,
  };

  static Uint8List _decode(String value) {
    try {
      return base64Decode(value);
    } catch (_) {
      throw ChumbucketWalletException.refused;
    }
  }
}

/// Whether a Privy user's linked accounts name exactly [account] as the
/// custom-auth user (the BFF token's `sub`).
bool privyUserIsAccount(Iterable<LinkedAccounts> linked, String account) =>
    linked.any((a) => a is CustomAuthAccount && a.customUserId == account);
