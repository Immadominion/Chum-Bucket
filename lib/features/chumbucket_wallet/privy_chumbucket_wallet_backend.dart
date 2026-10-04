/// The Chumbucket wallet on Privy: an embedded Solana wallet, non-custodial,
/// whose key Privy rebuilds in its secure enclave for this account only.
///
/// Privy signs the person in with our own Supabase session (JWT-based custom
/// auth: Privy verifies the access token against Supabase's JWKS), so the
/// same `sub` reaches the same wallet on any device with no prompt. The token
/// provider is the session's `bffAuthToken`, which refreshes a token that is
/// about to expire; Privy asks for it again whenever it needs one.
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
    required Future<String?> Function() accessToken,
  }) : _appId = appId,
       _clientId = clientId,
       _accessToken = accessToken;

  final String _appId;
  final String _clientId;
  final Future<String?> Function() _accessToken;

  /// Made on first use: an account that never needs its wallet never starts
  /// a Privy session (Privy prices by monthly active users).
  late final Privy _privy = Privy.init(
    config: PrivyConfig(
      appId: _appId,
      appClientId: _clientId,
      logLevel: PrivyLogLevel.none,
      customAuthConfig: LoginWithCustomAuthConfig(tokenProvider: _accessToken),
    ),
  );

  static bool _isFor(PrivyUser user, String authUserId) => user.linkedAccounts
      .any((a) => a is CustomAuthAccount && a.customUserId == authUserId);

  Future<PrivyUser> _user() async {
    final AuthState state;
    try {
      state = await _privy.getAuthState();
    } catch (_) {
      throw ChumbucketWalletException.unavailable;
    }
    if (state is Authenticated) return state.user;
    throw ChumbucketWalletException.signedOut;
  }

  Future<EmbeddedSolanaWallet> _walletAt(String address) async {
    for (final wallet in (await _user()).embeddedSolanaWallets) {
      if (wallet.address == address) return wallet;
    }
    throw ChumbucketWalletException.signedOut;
  }

  @override
  Future<void> signIn(String authUserId) async {
    final AuthState state;
    try {
      state = await _privy.getAuthState();
    } catch (_) {
      throw ChumbucketWalletException.unavailable;
    }
    if (state is Authenticated && _isFor(state.user, authUserId)) return;
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
        if (!_isFor(value, authUserId)) {
          await _privy.logout();
          throw ChumbucketWalletException.signedOut;
        }
      case Failure<PrivyUser>():
        throw ChumbucketWalletException.unavailable;
    }
  }

  @override
  Future<String?> wallet() async {
    final wallets = (await _user()).embeddedSolanaWallets;
    return wallets.isEmpty ? null : wallets.first.address;
  }

  @override
  Future<String> createWallet() async {
    final result = await (await _user()).createSolanaWallet();
    return switch (result) {
      Success<EmbeddedSolanaWallet>(:final value) => value.address,
      Failure<EmbeddedSolanaWallet>() =>
        throw ChumbucketWalletException.unavailable,
    };
  }

  @override
  Future<Uint8List> signMessage(String address, Uint8List message) async {
    final wallet = await _walletAt(address);
    // Privy takes the message and answers the signature, both base64.
    final result = await wallet.provider.signMessage(base64Encode(message));
    return _bytes(result);
  }

  @override
  Future<Uint8List> signTransaction(String address, Uint8List unsigned) async {
    final wallet = await _walletAt(address);
    return _bytes(await wallet.provider.signTransaction(unsigned));
  }

  @override
  Future<void> signOut() async {
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
