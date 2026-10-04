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

  /// A share price in its market's own unit: `0.52 USDC/share`,
  /// `0.67 SOL/share`. Never converted to USD.
  static String sharePrice(
    String? value, {
    ShareCurrency currency = ShareCurrency.usdc,
  }) => value == null ? 'Unavailable' : '$value ${currency.perShare}';

  /// A venue share price for reading, at two decimals: `0.500096044` reads
  /// `0.50`. Rounded half-up on the DECIMAL STRING, never through a double, so
  /// a venue value is never altered by float conversion; `1.25` stays above
  /// one; a positive price under a cent reads `<0.01`, never `0.00`.
  ///
  /// Display only. The exact venue string stays on the market's detail, and
  /// anything executable (quotes, trade review) keeps its full precision.
  /// A value this cannot parse is returned unchanged rather than guessed at.
  static String displayPrice(String value) {
    final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(value.trim());
    if (match == null) return value;
    final whole = match.group(1)!;
    final fraction = (match.group(2) ?? '').padRight(3, '0');
    var cents = BigInt.parse('$whole${fraction.substring(0, 2)}');
    if (int.parse(fraction[2]) >= 5) cents += BigInt.one;
    if (cents == BigInt.zero) {
      final positive = RegExp(
        r'[1-9]',
      ).hasMatch('$whole${match.group(2) ?? ''}');
      return positive ? '<0.01' : '0.00';
    }
    final digits = cents.toString().padLeft(3, '0');
    return '${digits.substring(0, digits.length - 2)}.'
        '${digits.substring(digits.length - 2)}';
  }

  /// True when [displayPrice] shows less than the venue supplied, so the exact
  /// figure needs to be shown alongside it.
  static bool priceWasRounded(String value) {
    final shown = displayPrice(value);
    // Unparseable values come back unchanged: nothing was rounded.
    if (shown == value) return false;
    String trimZeros(String v) {
      final s = v.trim();
      if (!s.contains('.')) return s;
      return s
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
    }

    // `0.5` -> `0.50` and `1` -> `1.00` add zeros; they do not round.
    return trimZeros(shown) != trimZeros(value);
  }

  static String nativePrices(SharePriceSnapshot? value) =>
      value == null
          ? 'Panta prices unavailable. Refresh before calling.'
          : 'YES ${sharePrice(value.yesPrice, currency: value.currency)} · '
              'NO ${sharePrice(value.noPrice, currency: value.currency)}';

  /// Both sides at reading precision, named once in the market's own unit:
  /// `YES 0.67 · NO 0.33 SOL/share`. A side Panta did not publish reads `—`.
  static String quietPrices(SharePriceSnapshot value) {
    String side(String? price) => price == null ? '—' : displayPrice(price);
    return 'YES ${side(value.yesPrice)} · NO ${side(value.noPrice)} '
        '${value.currency.perShare}';
  }

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

  static final DateFormat _dayMonth = DateFormat('d MMM');

  /// A day for a compact fact tile: "3h ago" within a week, then "22 Sep".
  /// The exact UTC instant stays on the receipt and the "on record" banner.
  static String shortWhen(DateTime value, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    final delta = reference.difference(value.toUtc());
    if (!delta.isNegative && delta.inDays < 7) {
      return relative(value, now: reference);
    }
    return _dayMonth.format(value.toUtc());
  }

  /// The time left before a market closes, as a short tag beside a clock
  /// icon: "39d", "5h", "22m". Null once it has closed (or has no close).
  static String? timeLeft(DateTime? closesAt, {DateTime? now}) {
    if (closesAt == null) return null;
    final delta = closesAt.toUtc().difference((now ?? DateTime.now()).toUtc());
    if (delta.isNegative) return null;
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    if (delta.inHours < 48) return '${delta.inHours}h';
    return '${delta.inDays}d';
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
