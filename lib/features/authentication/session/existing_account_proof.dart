import 'session_bff_client.dart';
import 'session_state.dart';

/// Pinned app identity, never chosen from an untrusted server response.
///
/// The owner's live domain, the same one Supabase's Sign in with Solana uses
/// (`kSolanaSignInDomain`). It was `chumbucket.app`, which was never
/// registered; the BFF's allowlist (`FIXTURE_AUTH_IDENTITY_POLICY`) moved with
/// it, and this app refuses to sign when the server does not list it.
const accountClaimDomain = 'chumbucket.fun';
const accountClaimUri = 'https://chumbucket.fun';
const accountClaimStatement =
    'Connect your signed-in account to your existing Chumbucket profile. '
    'This request does not create a profile or authorise any transaction, transfer or spend.';

/// Only message signing is exposed. No transaction or profile-write capability.
abstract interface class ExistingAccountWallet {
  String get address;
  String get network;
  bool get isCurrent;

  /// A continuity check, NOT ownership evidence. Only the server's reviewed
  /// historical anchor may authorize binding the existing person.
  Future<String?> expectedUserId();
  Future<String> signClaim(String message);
}

const accountChangedError = SessionException(
  SessionError.refused(
    'Your account changed. Reopen Settings to start again.',
    code: 'ACCOUNT_CHANGED',
  ),
);
const accountClaimUnreadable = SessionException(
  SessionError.refused(
    'The account proof could not be verified. Nothing was signed.',
    code: 'ACCOUNT_PROOF_INVALID',
  ),
);
const accountClaimExpired = SessionException(
  SessionError.refused(
    'The wallet proof expired. Try linking Google again.',
    code: 'NONCE_EXPIRED',
  ),
);

/// Validates the server-owned SIWS v1 layout before a wallet can see it. We
/// sign the original bytes, never a client reconstruction or arbitrary payload.
class ExistingAccountProof {
  const ExistingAccountProof._(this.message, this.expiresAt);
  final String message;
  final DateTime expiresAt;

  factory ExistingAccountProof.parse(
    Object? value, {
    required String address,
    required String network,
    DateTime? now,
  }) {
    if (value is! Map) throw accountClaimUnreadable;
    final message = value['message'];
    final chainId = switch (network) {
      'devnet' => 'solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1',
      'mainnet-beta' => 'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp',
      _ => throw accountClaimUnreadable,
    };
    if (message is! String ||
        message.length > 4096 ||
        value['domain'] != accountClaimDomain ||
        value['uri'] != accountClaimUri ||
        value['network'] != network ||
        value['purpose'] != 'claim_account' ||
        value['proofVersion'] != 1) {
      throw accountClaimUnreadable;
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
        lines[3] != accountClaimStatement ||
        lines[4] != '' ||
        lines[5] != 'URI: $accountClaimUri' ||
        lines[6] != 'Version: 1' ||
        lines[7] != 'Chain ID: $chainId' ||
        !RegExp(r'^Nonce: [0-9a-f]{64}$').hasMatch(lines[8]) ||
        lines[9] != 'Issued At: ${value['issuedAt']}' ||
        lines[10] != 'Expiration Time: ${value['expiresAt']}' ||
        lines[11] != 'Resources:' ||
        lines[12] != '- chumbucket:purpose:claim_account' ||
        !expiry.isAfter(issued) ||
        expiry.difference(issued) > const Duration(minutes: 15) ||
        issued.isAfter(instant.add(const Duration(seconds: 30)))) {
      throw accountClaimUnreadable;
    }
    final proof = ExistingAccountProof._(message, expiry);
    proof.checkFresh(now: instant);
    return proof;
  }

  void checkFresh({DateTime? now}) {
    if (!expiresAt.isAfter(now ?? DateTime.now())) throw accountClaimExpired;
  }

  static DateTime _utcDate(Object? value) {
    if (value is! String ||
        !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
      throw accountClaimUnreadable;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String() != value) {
      throw accountClaimUnreadable;
    }
    return parsed;
  }

  @override
  String toString() => 'ExistingAccountProof(<redacted>)';
}
