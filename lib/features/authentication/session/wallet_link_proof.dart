/// The server-issued Sign-in-with-Solana challenge that links a wallet to the
/// signed-in account (`auth.requestWalletNonce`, purpose `link_wallet`).
///
/// Checked line by line before anything signs it, exactly as
/// [ExistingAccountProof] is: the domain, URI, statement and purpose are pinned
/// here, never taken from the server's answer, and the address must be the one
/// asked about. We sign the server's original bytes, never a reconstruction.
library;

import 'existing_account_proof.dart' show accountClaimDomain, accountClaimUri;
import 'session_bff_client.dart';
import 'session_state.dart';

/// `STATEMENTS.link_wallet` in the BFF's `src/auth/SiwsMessage.ts`.
const walletLinkStatement =
    'Link this Solana wallet to your Chumbucket account. This request does '
    'not authorise any transaction, transfer or spend.';

const walletLinkUnreadable = SessionException(
  SessionError.refused(
    'The wallet link request could not be verified. Nothing was signed.',
    code: 'WALLET_LINK_PROOF_INVALID',
  ),
);

const walletLinkExpired = SessionException(
  SessionError.refused(
    'The wallet link request expired. Try again.',
    code: 'NONCE_EXPIRED',
  ),
);

/// CAIP-2 ids, as the BFF's `CHAIN_IDS`.
String? siwsChainId(String network) => switch (network) {
  'devnet' => 'solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1',
  'mainnet-beta' => 'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp',
  _ => null,
};

class WalletLinkProof {
  const WalletLinkProof._(this.message, this.expiresAt);

  /// The exact text to sign.
  final String message;
  final DateTime expiresAt;

  factory WalletLinkProof.parse(
    Object? value, {
    required String address,
    DateTime? now,
  }) {
    if (value is! Map) throw walletLinkUnreadable;
    final message = value['message'];
    final network = value['network'];
    final chainId = network is String ? siwsChainId(network) : null;
    if (chainId == null ||
        message is! String ||
        message.length > 4096 ||
        value['domain'] != accountClaimDomain ||
        value['uri'] != accountClaimUri ||
        value['purpose'] != 'link_wallet' ||
        value['proofVersion'] != 1) {
      throw walletLinkUnreadable;
    }
    final lines = message.split('\n');
    final issued = _utcDate(value['issuedAt']);
    final expiry = _utcDate(value['expiresAt']);
    final instant = (now ?? DateTime.now()).toUtc();
    if (lines.length != 13 ||
        lines[0] !=
            '$accountClaimDomain wants you to sign in with your Solana account:' ||
        lines[1] != address ||
        lines[2] != '' ||
        lines[3] != walletLinkStatement ||
        lines[4] != '' ||
        lines[5] != 'URI: $accountClaimUri' ||
        lines[6] != 'Version: 1' ||
        lines[7] != 'Chain ID: $chainId' ||
        !RegExp(r'^Nonce: [0-9a-f]{64}$').hasMatch(lines[8]) ||
        lines[9] != 'Issued At: ${value['issuedAt']}' ||
        lines[10] != 'Expiration Time: ${value['expiresAt']}' ||
        lines[11] != 'Resources:' ||
        lines[12] != '- chumbucket:purpose:link_wallet' ||
        !expiry.isAfter(issued) ||
        expiry.difference(issued) > const Duration(minutes: 15) ||
        issued.isAfter(instant.add(const Duration(seconds: 30)))) {
      throw walletLinkUnreadable;
    }
    final proof = WalletLinkProof._(message, expiry);
    proof.checkFresh(now: instant);
    return proof;
  }

  void checkFresh({DateTime? now}) {
    if (!expiresAt.isAfter(now ?? DateTime.now())) throw walletLinkExpired;
  }

  static DateTime _utcDate(Object? value) {
    if (value is! String ||
        !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
      throw walletLinkUnreadable;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String() != value) {
      throw walletLinkUnreadable;
    }
    return parsed;
  }

  @override
  String toString() => 'WalletLinkProof(<redacted>)';
}
