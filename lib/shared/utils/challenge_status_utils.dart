import 'package:flutter/material.dart';

/// Shared utility for challenge status display across the app.
/// Centralizes status logic to avoid duplication and ensure consistency.
class ChallengeStatusUtils {
  /// Whether an earlier escrow challenge is still open, so its witness can
  /// settle it. `expired` counts: the deadline is the challenge's own, and the
  /// escrow program does not enforce it, so the SOL stays locked until the
  /// witness settles (or the challenger cancels).
  static bool isResolvable(String status) {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'active' || s == 'expired';
  }

  /// Get color for challenge status badge/indicator
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'active':
      case 'expired': // past due, but still open (see isResolvable)
        return const Color.fromARGB(255, 241, 155, 79); // Orange for ongoing
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return const Color(0xFFFF5A76); // Default pink
    }
  }

  /// Get the Basil icon slug (see lib/shared/widgets/icons/basil_icon.dart)
  /// for a challenge status.
  static String getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'check-outline';
      case 'failed':
        return 'cancel-outline';
      case 'expired':
        return 'timer-outline';
      case 'cancelled':
        return 'trash-outline'; // discarded — distinct from "failed"
      case 'pending':
      case 'active':
      default:
        return 'sand-watch-outline'; // ongoing/in-progress
    }
  }

  /// Get human-readable status label
  static String getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'active':
        return 'Active';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Not completed';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Past due';
      default:
        return status;
    }
  }
}

/// What settling an earlier escrow pays out, as text: the stake less the
/// program's fee (2.5%, at most 0.1 SOL), e.g. `0.0975 SOL`. The fee is
/// taken from the stake, and the escrow account holds exactly the stake, so
/// this is what lands in the winner's wallet. `the SOL` when the row carries
/// no amount.
String escrowPayoutText(Map<String, dynamic> challenge) {
  double? number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
  var payout = number(challenge['winner_amount_sol']) ?? 0;
  if (payout <= 0) {
    final stake = number(challenge['amount']) ?? 0;
    final fee = (stake * 0.025).clamp(0.0, 0.1);
    payout = stake - fee;
  }
  if (payout <= 0) return 'the SOL';
  return '${formatSol(payout)} SOL';
}

/// A SOL amount with up to six decimals and no trailing zeros: a payout is
/// shown exactly (0.24375, not 0.2437).
String formatSol(double value) {
  if (value == value.truncateToDouble()) return value.truncate().toString();
  return value
      .toStringAsFixed(6)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}
