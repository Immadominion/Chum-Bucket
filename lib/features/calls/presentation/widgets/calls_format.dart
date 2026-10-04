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

  /// One side's price read alone as odds: `0.62` reads `62%`. Only for a
  /// price with no other side to weigh it against (a position's fill, a
  /// trade's average, a side whose pair Panta did not publish); a market's
  /// two sides go through [pairOdds], so they always add up.
  ///
  /// Rounded half-up on the DECIMAL STRING, never through a double; a
  /// positive price under half a percent reads `<1%` and one just short of a
  /// whole share `>99%`, never `0%` / `100%`. Null when there is nothing
  /// honest to show (no price, an unparseable one, or one above a share).
  ///
  /// Display only: the venue string itself is never altered or re-sent.
  static String? odds(String? price) {
    if (price == null) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(price.trim());
    if (match == null) return null;
    final whole = BigInt.parse(match.group(1)!);
    final digits = match.group(2) ?? '';
    final anyFraction = RegExp(r'[1-9]').hasMatch(digits);
    if (whole > BigInt.one || (whole == BigInt.one && anyFraction)) {
      return null;
    }
    if (whole == BigInt.one) return '100%';
    if (!anyFraction) return '0%';
    final fraction = digits.padRight(3, '0');
    var percent = int.parse(fraction.substring(0, 2));
    if (int.parse(fraction[2]) >= 5) percent += 1;
    if (percent == 0) return '<1%';
    if (percent >= 100) return '>99%';
    return '$percent%';
  }

  /// A market's two sides as odds that always add up to 100.
  ///
  /// Panta's USDC prices are independent venue prices: they need not sum to
  /// one, and either can exceed one (YES 1.25 / NO 0.35). So YES reads
  /// yes / (yes + no) and NO reads 100 minus that rounded YES; a SOL market's
  /// complementary pair reads exactly as its own figures. Rounded half-up
  /// with exact integer arithmetic. A side alone (the other unpublished)
  /// falls back to [odds]; both missing, or both zero, read null.
  static ({String? yes, String? no}) pairOdds(String? yes, String? no) {
    final y = _decimal(yes);
    final n = _decimal(no);
    if (y == null || n == null) {
      return (
        yes: y == null ? null : odds(yes),
        no: n == null ? null : odds(no),
      );
    }
    // Both on one scale: as many decimals as the longer has.
    final places = y.$2 > n.$2 ? y.$2 : n.$2;
    BigInt scaled((BigInt, int) v) => v.$1 * BigInt.from(10).pow(places - v.$2);
    final yes0 = scaled(y);
    final no0 = scaled(n);
    final sum = yes0 + no0;
    if (sum == BigInt.zero) return (yes: null, no: null);
    // round(100 · yes / sum), half-up: floor((200 · yes + sum) / (2 · sum)).
    final percent =
        ((yes0 * BigInt.from(200) + sum) ~/ (sum * BigInt.two)).toInt();
    if (percent == 0 && yes0 > BigInt.zero) return (yes: '<1%', no: '>99%');
    if (percent == 100 && no0 > BigInt.zero) return (yes: '>99%', no: '<1%');
    return (yes: '$percent%', no: '${100 - percent}%');
  }

  /// One side's odds out of a market's price, weighed against the other.
  static String? sideOdds(SharePriceSnapshot? value, Side side) {
    if (value == null) return null;
    final pair = pairOdds(value.yesPrice, value.noPrice);
    return side == Side.yes ? pair.yes : pair.no;
  }

  /// Both sides as odds: `YES 59% · NO 41%`. A side Panta did not publish
  /// reads `—`.
  static String sidesOdds(SharePriceSnapshot value) {
    final pair = pairOdds(value.yesPrice, value.noPrice);
    return 'YES ${pair.yes ?? '—'} · NO ${pair.no ?? '—'}';
  }

  /// A plain decimal as (digits, decimal places); null if it is not one.
  static (BigInt, int)? _decimal(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(value.trim());
    if (match == null) return null;
    final fraction = match.group(2) ?? '';
    return (BigInt.parse('${match.group(1)}$fraction'), fraction.length);
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
