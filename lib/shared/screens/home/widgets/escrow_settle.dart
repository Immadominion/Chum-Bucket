/// What happens before a witness's wallet opens to settle an earlier SOL
/// escrow challenge (Settings → History).
///
/// Creating an escrow is retired; settling one that still holds SOL is not,
/// because that SOL belongs to the two people in it. Only the witness can
/// settle (chumbucket-pinocchio `process_resolve_challenge`), and the program
/// checks the resolve against what it stored on Solana, not against the
/// database row. So the app reads the escrow account first and stops, with
/// plain copy, whenever the transaction could only fail.
library;

import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/utils/challenge_status_utils.dart';

/// Either a reason to stop before the wallet opens, or what it will be asked
/// to sign.
sealed class EscrowSettleDecision {
  const EscrowSettleDecision();
}

/// Stop: nothing is signed or sent. [settled] is not an error: someone
/// already settled it.
final class EscrowSettleStop extends EscrowSettleDecision {
  const EscrowSettleStop(this.title, this.subtitle, {this.settled = false});

  final String title;
  final String subtitle;
  final bool settled;
}

/// Go: the resolve the witness's wallet is asked to approve.
final class EscrowSettlePlan extends EscrowSettleDecision {
  const EscrowSettlePlan({
    required this.escrow,
    required this.initiator,
    required this.payout,
  });

  /// The escrow account.
  final String escrow;

  /// The challenger's wallet: the one the program stored when it can be
  /// read, which is the one the program checks.
  final String initiator;

  /// What the winner receives, as text (e.g. `0.04875 SOL`).
  final String payout;
}

String _field(Map<String, dynamic> challenge, List<String> keys) {
  for (final key in keys) {
    final value = challenge[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

/// The escrow account of a History row (the keys differ by source).
String escrowAddressOf(Map<String, dynamic> challenge) => _field(
  challenge,
  const ['escrowAddress', 'escrow_address', 'multisig_address'],
);

/// Before reading Solana: is there anything this wallet could sign for?
/// Null when the chain should be asked.
EscrowSettleStop? escrowSettlePreflight(
  Map<String, dynamic> challenge, {
  required String? connectedWallet,
}) {
  if (connectedWallet == null || connectedWallet.isEmpty) {
    return const EscrowSettleStop(
      'Can’t settle this challenge',
      'Connect the witness wallet to settle it.',
    );
  }
  if (escrowAddressOf(challenge).isEmpty) {
    return const EscrowSettleStop(
      'Can’t settle this challenge',
      'It has no escrow account on record, so there is nothing to sign.',
    );
  }
  return null;
}

/// After reading the escrow account ([check]): stop, or the resolve to sign.
EscrowSettleDecision planEscrowSettle(
  Map<String, dynamic> challenge, {
  required String connectedWallet,
  required EscrowAccountCheck check,
}) {
  switch (check.state) {
    case EscrowAccountState.settled:
      return const EscrowSettleStop(
        'Already settled',
        'This escrow is already closed on Solana, so there is nothing left '
            'in it to settle.',
        settled: true,
      );
    case EscrowAccountState.notThisProgram:
      return const EscrowSettleStop(
        'Can’t settle this one here',
        'Its SOL isn’t held by the Chumbucket escrow program, so there is '
            'nothing this app can sign. Nothing was sent.',
      );
    case EscrowAccountState.open:
    case EscrowAccountState.unknown:
      break;
  }
  final witness = check.witness;
  if (witness != null && witness != connectedWallet) {
    return const EscrowSettleStop(
      'Not the witness wallet',
      'On Solana, this escrow’s witness is a different wallet. Connect that '
          'wallet to settle it.',
    );
  }
  final initiator =
      check.initiator ??
      _field(challenge, const [
        'initiator_address',
        'member1_address',
        'creator_wallet_address',
      ]);
  if (initiator.isEmpty) {
    return const EscrowSettleStop(
      'Can’t settle this challenge',
      'The challenger’s wallet isn’t on record, so there is nothing to sign.',
    );
  }
  final lamports = check.payoutLamports;
  return EscrowSettlePlan(
    escrow: escrowAddressOf(challenge),
    initiator: initiator,
    payout:
        lamports != null
            ? '${formatSol(lamports / 1e9)} SOL'
            : escrowPayoutText(challenge),
  );
}
