import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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

  /// Get icon for challenge status
  static IconData getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return PhosphorIconsRegular.checkCircle;
      case 'failed':
        return PhosphorIconsRegular.xCircle;
      case 'expired':
        return PhosphorIconsRegular.clockCountdown;
      case 'cancelled':
        return PhosphorIconsRegular.prohibit;
      case 'pending':
      case 'active':
      default:
        return PhosphorIconsRegular.circle; // Ongoing/unfilled circle
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
