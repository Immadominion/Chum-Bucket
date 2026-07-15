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
}
