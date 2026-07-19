import 'package:intl/intl.dart';

import 'package:chumbucket/features/arena/data/match_arena_service.dart';

/// Small, consistent number-display helpers for the arena feature.
/// Display-only - all math elsewhere uses raw BigInt base units / doubles.
class ArenaFormat {
  static final NumberFormat _amount = NumberFormat('#,##0.##');

  /// Format a whole-USDC double amount, e.g. 12500.5 -> "12,500.5 USDC".
  static String usdc(double amountUsdc) {
    if (amountUsdc.isNaN || !amountUsdc.isFinite) return '-- USDC';
    if (amountUsdc == 0) return '0 USDC';
    return '${_amount.format(amountUsdc)} USDC';
  }

  /// Format a raw base-unit (6-decimal) amount straight from the backend or
  /// on-chain account.
  static String usdcFromBaseUnits(BigInt baseUnits) =>
      usdc(MatchArenaService.baseUnitsToUsdc(baseUnits));

  /// Whole-number percent, e.g. 0.6 -> "60%".
  static String percent(double value) {
    if (value.isNaN || !value.isFinite) return '--';
    return '${(value * 100).round()}%';
  }

  static String bucketLabel(int bucket) {
    switch (bucket) {
      case MatchArenaService.bucketHome:
        return 'HOME';
      case MatchArenaService.bucketDraw:
        return 'DRAW';
      case MatchArenaService.bucketAway:
        return 'AWAY';
      default:
        return '?';
    }
  }

  /// Map a raw outcome code ("HOME"/"DRAW"/"AWAY"/"OVER"/"UNDER") to a plain,
  /// user-facing name. HOME/AWAY become the actual team names; DRAW becomes
  /// "Draw"; line-market codes are shown in title case. Newcomers must never
  /// see the raw codes.
  static String outcomeName(
    String code, {
    required String home,
    required String away,
  }) {
    switch (code.toUpperCase()) {
      case 'HOME':
        return home;
      case 'AWAY':
        return away;
      case 'DRAW':
        return 'Draw';
      case 'OVER':
        return 'Over';
      case 'UNDER':
        return 'Under';
      default:
        return code;
    }
  }

  /// Same as [outcomeName] but from the on-chain bucket index (0/1/2).
  static String outcomeNameFromIndex(
    int bucket, {
    required String home,
    required String away,
  }) {
    switch (bucket) {
      case MatchArenaService.bucketHome:
        return home;
      case MatchArenaService.bucketAway:
        return away;
      case MatchArenaService.bucketDraw:
        return 'Draw';
      default:
        return 'this pick';
    }
  }
}
