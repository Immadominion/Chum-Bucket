/// Plain-language times and prices for onboarding (onboarding spec §4.5):
/// "Closes in 2 days", "YES 0.50 · NO 0.50 USDC/share". Never a percent,
/// never odds, never "chance".
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';

abstract final class OnbFormat {
  /// "in 22 minutes", "in 5 hours", "in 2 days". Null closesAt → null.
  static String? until(DateTime? closesAt, {DateTime? now}) {
    if (closesAt == null) return null;
    final reference = (now ?? DateTime.now()).toUtc();
    final delta = closesAt.toUtc().difference(reference);
    if (delta.isNegative) return null;
    if (delta.inMinutes < 60) {
      final m = delta.inMinutes < 1 ? 1 : delta.inMinutes;
      return 'in $m ${m == 1 ? 'minute' : 'minutes'}';
    }
    if (delta.inHours < 48) {
      final h = delta.inHours;
      return 'in $h ${h == 1 ? 'hour' : 'hours'}';
    }
    final d = delta.inDays;
    return 'in $d ${d == 1 ? 'day' : 'days'}';
  }

  /// "Closes in 2 days · Panta", or "Panta" when no close is published.
  static String closesLine(VenueMarket market, {DateTime? now}) {
    final until = OnbFormat.until(market.closesAtUtc, now: now);
    return until == null ? 'Panta' : 'Closes $until · Panta';
  }

  /// The price a call locked at, on its own side: "0.50".
  static String? lockedPrice(Call call) {
    final value = call.entryPrice?.priceFor(call.side);
    return value == null ? null : CallsFormat.displayPrice(value);
  }

  /// "14:05 UTC, 2 Oct" — the server's lock time, exactly.
  static String lockedAt(Call call) =>
      CallsFormat.timestampShortUtc(call.lockedAtUtc);
}
