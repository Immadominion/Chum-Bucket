import 'package:flutter/material.dart';

/// Shared utility for challenge status display across the app.
/// Centralizes status logic to avoid duplication and ensure consistency.
class ChallengeStatusUtils {
  /// Whether a challenge can be resolved (tapped to open resolve sheet)
  static bool isResolvable(String status) {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'active';
  }

  /// Get color for challenge status badge/indicator
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
      case 'active':
        return const Color.fromARGB(255, 241, 155, 79); // Orange for ongoing
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'cancelled':
      case 'expired':
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
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      case 'expired':
        return 'Expired';
      default:
        return status;
    }
  }
}
