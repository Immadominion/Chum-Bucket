/// Display-only formatting for the call slice.
///
/// Mirrors `ArenaFormat`'s job (`arena_format.dart`) for the new vocabulary:
/// all arithmetic stays on doubles/ints elsewhere, and nothing here invents a
/// value it was not given — a missing probability renders as "—", never 0%.
library;

import 'package:intl/intl.dart';

import 'package:chumbucket/features/calls/data/call_models.dart';

class CallsFormat {
  CallsFormat._();
  static String sharePrice(String? value) =>
      value == null ? 'Unavailable' : '$value USDC/share';
  static String nativePrices(SharePriceSnapshot? value) =>
      value == null
          ? 'Panta prices unavailable. Refresh before calling.'
          : 'YES ${sharePrice(value.yesPrice)} · NO ${sharePrice(value.noPrice)}';

  static final DateFormat _absolute = DateFormat('d MMM yyyy, HH:mm');
  static final DateFormat _absoluteShort = DateFormat('d MMM, HH:mm');

  /// Whole-number percent. Null renders as an em dash, never as 0%.
  static String probability(double? value) {
    if (value == null || value.isNaN || !value.isFinite) return '—';
    return '${(value * 100).round()}%';
  }

  /// Exact UTC timestamp for receipts and rules — the thing a receipt has to
  /// be able to prove.
  static String timestampUtc(DateTime value) =>
      '${_absolute.format(value.toUtc())} UTC';

  static String timestampShortUtc(DateTime value) =>
      '${_absoluteShort.format(value.toUtc())} UTC';

  /// "3h ago", "just now". For the feed, where exactness is noise.
  static String relative(DateTime value, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    final delta = reference.difference(value.toUtc());
    if (delta.isNegative) return 'just now';
    if (delta.inSeconds < 45) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return timestampShortUtc(value);
  }

  /// "in 4d", "closes in 22m", "closed".
  static String untilClose(DateTime? closesAt, {DateTime? now}) {
    if (closesAt == null) return 'No close time published';
    final reference = (now ?? DateTime.now()).toUtc();
    final delta = closesAt.toUtc().difference(reference);
    if (delta.isNegative) return 'Closed ${relative(closesAt, now: reference)}';
    if (delta.inMinutes < 60) return 'Closes in ${delta.inMinutes}m';
    if (delta.inHours < 48) return 'Closes in ${delta.inHours}h';
    return 'Closes in ${delta.inDays}d';
  }

  /// How old a price is. The market detail must always show this next to the
  /// price so nobody mistakes a five-hour-old number for live.
  static String dataAge(Duration? age) {
    if (age == null) return 'No price published yet';
    if (age.inSeconds < 60) return 'Price updated just now';
    if (age.inMinutes < 60) return 'Price ${age.inMinutes}m old';
    if (age.inHours < 48) return 'Price ${age.inHours}h old';
    return 'Price ${age.inDays}d old';
  }

  /// Attribution line for a market: which venue, and whether it is demo data.
  static String venueAttribution(VenueMarket market) =>
      market.venue == MarketVenue.panta
          ? SharePriceSnapshot.attribution
          : market.venue.isDemo
          ? 'Demo catalog · not a live market'
          : 'Priced by ${market.venue.label}';

  /// Self-reported confidence, worded so it can never read as a crowd number.
  static String confidence(double? value) =>
      value == null
          ? 'No confidence stated'
          : 'Called it ${probability(value)} likely';

  /// One-line, non-confusable status for a person's call.
  static String outcomeSentence(CallOutcome outcome) => switch (outcome) {
    CallOutcome.pending => 'Pending — the venue has not published a result',
    CallOutcome.correct => 'Correct',
    CallOutcome.incorrect => 'Incorrect',
    CallOutcome.voided =>
      'Void — the market was cancelled. Not a win, not a loss',
  };
}
