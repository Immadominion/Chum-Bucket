import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:chumbucket/core/config/network_config.dart';
import '../providers/mwa_auth_provider.dart';
import 'existing_account_proof.dart';
import 'session_bff_client.dart';
import 'session_state.dart';

const _walletRefused = SessionException(
  SessionError.refused(
    'The wallet did not sign the account proof. Your existing profile is unchanged.',
    code: 'WALLET_PROOF_CANCELLED',
  ),
);

/// Captures the existing wallet connection; never calls authorize(), updates a
/// profile, links a public arena label, or sends a transaction.
class MwaExistingAccountWallet implements ExistingAccountWallet {
  MwaExistingAccountWallet(this._auth)
    : address = _auth.walletAddress ?? '',
      network = NetworkConfig.currentNetwork,
      _revision = _auth.authRevision;
  final MwaAuthProvider _auth;
  final int _revision;
  @override
  final String address;
  @override
  final String network;
  @override
  bool get isCurrent =>
      _auth.isAuthenticated &&
      _auth.authRevision == _revision &&
      _auth.walletAddress == address &&
      NetworkConfig.currentNetwork == network;

  @override
  Future<String?> expectedUserId() async {
    if (!isCurrent) throw accountChangedError;
    final profile = await _auth.getUserProfile();
    if (!isCurrent) throw accountChangedError;
    final id = profile?['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  @override
  Future<String> signClaim(String message) async {
    if (!isCurrent) throw accountChangedError;
    final publicKey = _auth.publicKeyBytes;
    if (publicKey == null ||
        publicKey.length != 32 ||
        base58encode(publicKey) != address) {
      throw accountChangedError;
    }
    final bytes = Uint8List.fromList(utf8.encode(message));
    final signing = await _auth.createSigningSession();
    if (signing == null) throw _walletRefused;
    try {
      if (!isCurrent) throw accountChangedError;
      final response = await signing.signMessages(
        messages: [bytes],
        addresses: [publicKey],
      );
      if (!isCurrent) throw accountChangedError;
      return claimSignature(response, message: bytes, address: publicKey);
    } on SessionException {
      rethrow;
    } catch (_) {
      throw _walletRefused; // Platform errors may embed message/auth material.
    } finally {
      try {
        await signing.close();
      } catch (_) {
        /* No provider error body. */
      }
    }
  }
}

/// MWA returns signed-message metadata as well as signatures. A different
/// address, modified payload, or extra signature is never silently accepted.
String claimSignature(
  SignMessagesResult result, {
  required Uint8List message,
  required Uint8List address,
}) {
  if (result.signedMessages.length != 1) throw _walletRefused;
  final signed = result.signedMessages.single;
  if (!listEquals(signed.message, message) ||
      signed.addresses.length != 1 ||
      !listEquals(signed.addresses.single, address) ||
      signed.signatures.length != 1 ||
      signed.signatures.single.length != 64) {
    throw _walletRefused;
  }
  return base58encode(signed.signatures.single);
}
