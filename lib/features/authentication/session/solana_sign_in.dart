/// Sign in with a Solana wallet: Supabase Auth's Web3 sign-in.
///
/// The wallet signs one plain-text message — no transaction, no fee, nothing
/// moves — and Supabase Auth verifies the signature and issues the same kind of
/// session a Google sign-in gets. The BFF then reads the verified address from
/// that session server-side; the app never asserts who it is.
///
/// The message is Sign-In-With-Solana (EIP-4361 style), built line for line as
/// Supabase's own client builds it (`auth-js` `signInWithWeb3`), because the
/// server re-parses exactly this text. Supabase validates that the URI is on
/// the project's redirect allow-list, that the domain matches the URI's host,
/// and that "Issued At" is recent.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';

/// The app's own identity, as it presents itself to the wallet over Mobile
/// Wallet Adapter (`MwaAuthProvider` identityUri) and as Supabase's site URL,
/// so the wallet sees one consistent name. Must be on Supabase Auth's
/// redirect allow-list.
const String kSolanaSignInDomain = 'chumbucket.fun';
const String kSolanaSignInUri = 'https://chumbucket.fun';
const String kSolanaSignInStatement =
    'Sign in to Chumbucket. This is a signature, not a transaction: it costs '
    'nothing and moves nothing.';

/// The exact text the wallet signs.
String solanaSignInMessage({
  required String address,
  required DateTime issuedAt,
  String domain = kSolanaSignInDomain,
  String uri = kSolanaSignInUri,
  String statement = kSolanaSignInStatement,
}) => [
  '$domain wants you to sign in with your Solana account:',
  address,
  '',
  statement,
  '',
  'Version: 1',
  'URI: $uri',
  'Issued At: ${issuedAt.toUtc().toIso8601String()}',
].join('\n');

/// A wallet that can sign the sign-in message.
abstract class SolanaSignInWallet {
  /// Connects if needed and returns the address that will sign.
  Future<String> connect();

  /// The 64-byte ed25519 signature over [message], base64url-encoded — the
  /// encoding Supabase's Web3 grant accepts.
  Future<String> sign(String message);
}

const _walletDeclined = SessionException(
  SessionError.refused(
    'The wallet didn’t sign. Nothing was changed.',
    code: 'WALLET_SIGN_IN_CANCELLED',
  ),
);

/// The Seeker wallet, through Mobile Wallet Adapter.
class MwaSolanaSignInWallet implements SolanaSignInWallet {
  MwaSolanaSignInWallet(this._auth);
  final MwaAuthProvider _auth;
  String? _address;

  @override
  Future<String> connect() async {
    if (!_auth.isAuthenticated) {
      final connected = await _auth.authorize();
      if (!connected) throw _walletDeclined;
    }
    final address = _auth.walletAddress;
    final key = _auth.publicKeyBytes;
    if (address == null ||
        key == null ||
        key.length != 32 ||
        base58encode(key) != address) {
      throw _walletDeclined;
    }
    return _address = address;
  }

  @override
  Future<String> sign(String message) async {
    final key = _auth.publicKeyBytes;
    if (_address == null || key == null || _auth.walletAddress != _address) {
      throw _walletDeclined;
    }
    final bytes = Uint8List.fromList(utf8.encode(message));
    final result = await _auth.signInMessage(bytes);
    if (result == null) throw _walletDeclined;
    final signer = _auth.publicKeyBytes;
    if (signer == null) throw _walletDeclined;
    return signInSignature(result, message: bytes, address: signer);
  }
}

/// The one signature over exactly [message] by exactly [address], base64url.
@visibleForTesting
String signInSignature(
  SignMessagesResult result, {
  required Uint8List message,
  required Uint8List address,
}) {
  if (result.signedMessages.length != 1) throw _walletDeclined;
  final signed = result.signedMessages.single;
  if (!listEquals(signed.message, message) ||
      signed.addresses.length != 1 ||
      !listEquals(signed.addresses.single, address) ||
      signed.signatures.length != 1 ||
      signed.signatures.single.length != 64) {
    throw _walletDeclined;
  }
  return base64Url.encode(signed.signatures.single);
}
