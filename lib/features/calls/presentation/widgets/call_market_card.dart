import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Presentation windows only. Server eligibility still governs every write.
enum MarketDiscoveryWindow {
  all('Any time', null, 'clock-outline'),
  endingSoon('Ending soon', Duration(hours: 48), 'sand-watch-outline'),
  thisWeek('This week', Duration(days: 7), 'calendar-outline');

  const MarketDiscoveryWindow(this.label, this.horizon, this.icon);
  final String label;
  final Duration? horizon;

  /// The Basil icon drawn beside [label] in the filter sheet and its pill.
  final String icon;
}

/// Discovery order. "Most active" uses only the venue's own reported volume
/// ([VenueMarket.volumeUsdc]); a market without one sorts after those with
/// one, soonest-closing first, rather than being treated as zero.
enum MarketDiscoverySort {
  closingSoon('Closing soon', 'timer-outline'),
  mostActive('Most active', 'pulse-outline');

  const MarketDiscoverySort(this.label, this.icon);
  final String label;
  final String icon;
}

const _farFuture = 9223372036854775807;

/// Lowercase, hyphens as spaces: "pop culture" finds `pop-culture`.
String _fold(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[-_\s]+'), ' ').trim();

/// The markets discovery may offer right now: open, inside their window, and
/// from the live venue (or visibly-demo fixtures). Shared by every filter so
/// counts and chips describe exactly what the list can show.
bool _discoverable(VenueMarket market, DateTime reference) {
  final close = market.closesAtUtc;
  return market.status.acceptsNewCalls &&
      (market.venue == MarketVenue.panta || market.venue.isDemo) &&
      (market.opensAt == null ||
          market.opensAt! <= reference.millisecondsSinceEpoch) &&
      (close == null || close.isAfter(reference));
}

List<VenueMarket> discoveryMarkets(
  Iterable<VenueMarket> markets, {
  required MarketDiscoveryWindow window,
  String query = '',
  String? category,
  MarketDiscoverySort sort = MarketDiscoverySort.closingSoon,
  DateTime? now,
}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final term = _fold(query);
  final rows =
      markets.where((market) {
        if (!_discoverable(market, reference) ||
            (category != null &&
                market.category.toLowerCase() != category.toLowerCase()) ||
            (term.isNotEmpty &&
                !_fold(market.question).contains(term) &&
                !_fold(market.category).contains(term))) {
          return false;
        }
        final close = market.closesAtUtc;
        if (close == null) return window == MarketDiscoveryWindow.all;
        return window.horizon == null ||
            close.difference(reference) <= window.horizon!;
      }).toList();
  int closing(VenueMarket a, VenueMarket b) {
    final byClose = (a.closesAt ?? _farFuture).compareTo(
      b.closesAt ?? _farFuture,
    );
    return byClose != 0 ? byClose : a.id.compareTo(b.id);
  }

  return rows..sort(switch (sort) {
    MarketDiscoverySort.closingSoon => closing,
    MarketDiscoverySort.mostActive => (a, b) {
      final av = reportedVolume(a), bv = reportedVolume(b);
      if (av != null && bv != null && av != bv) return bv.compareTo(av);
      if ((av == null) != (bv == null)) return av == null ? 1 : -1;
      return closing(a, b);
    },
  });
}

/// The venue's reported volume as a number for ordering, or null.
double? reportedVolume(VenueMarket market) =>
    market.volumeUsdc == null ? null : double.tryParse(market.volumeUsdc!);

/// Whether "Most active" can mean anything: some discoverable market carries
/// a venue-reported volume above zero. Otherwise the option is not offered.
bool discoveryHasActivity(Iterable<VenueMarket> markets, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toUtc();
  return markets.any(
    (market) =>
        _discoverable(market, reference) && (reportedVolume(market) ?? 0) > 0,
  );
}

/// One category the venue actually has open, with how many markets it holds.
typedef MarketCategoryCount = ({String category, int count});

/// Topic choices come from the open markets themselves — never a fixed
/// list — so every choice leads somewhere and no live category is missing.
List<MarketCategoryCount> discoveryCategories(
  Iterable<VenueMarket> markets, {
  DateTime? now,
}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final counts = <String, int>{};
  for (final market in markets) {
    if (!_discoverable(market, reference)) continue;
    final key = market.category.toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return [
    for (final entry in counts.entries)
      (category: entry.key, count: entry.value),
  ]..sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.category.compareTo(b.category);
  });
}

/// How long a market has left, as a row shows it: "45m left", "6h left",
/// "3d left", then the date once it is more than two weeks out. Null without
/// a published close. The exact UTC time is the row's spoken label and
/// market detail's fact.
String? marketTimeLeft(DateTime? closesAt, {DateTime? now}) {
  if (closesAt == null) return null;
  final reference = (now ?? DateTime.now()).toUtc();
  final left = closesAt.toUtc().difference(reference);
  if (left <= Duration.zero) return 'Closed';
  if (left.inMinutes < 60) {
    return '${left.inMinutes < 1 ? 1 : left.inMinutes}m left';
  }
  if (left.inHours < 48) return '${left.inHours}h left';
  if (left.inDays <= 14) return '${left.inDays}d left';
  return 'Ends ${DateFormat('d MMM').format(closesAt.toUtc())}';
}

/// Under a day to go: the row's time reads in the brand's ink.
bool marketEndingSoon(DateTime? closesAt, {DateTime? now}) {
  if (closesAt == null) return false;
  final left = closesAt.toUtc().difference((now ?? DateTime.now()).toUtc());
  return left > Duration.zero && left < const Duration(hours: 24);
}

/// How long a list keeps showing a market's last good price while newer ones
/// are fetched in the background. Older than this it reads "—": a quiet
/// absence, never a warning, and never an old number passed off as current.
/// Anything that acts on a price (the composer, a trade) still checks its own
/// ten-minute validity.
const marketPriceShownFor = Duration(hours: 1);

/// "pop-culture" → "Pop culture". The venue's slug, made readable; never a
/// renamed or merged category.
String marketCategoryLabel(String category) {
  final words = category.trim().replaceAll(RegExp(r'[-_\s]+'), ' ');
  if (words.isEmpty) return 'Other';
  return words[0].toUpperCase() + words.substring(1).toLowerCase();
}

/// The app's filter chip: an outline on the page, 40dp drawn, a 48dp touch
/// target, dark when selected. Its label is 12sp — the smallest size Android
/// recommends for a control. [icon] leads the label and [count] trails it, so
/// a choice reads at a glance without a sentence around it.
class MarketFilterChip extends StatelessWidget {
  const MarketFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.dense = false,
    this.icon,
    this.count,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  /// Drawn at 32dp, for a toggle beside a section title rather than in the
  /// chip row. Same 48dp touch target.
  final bool dense;

  /// A Basil icon slug drawn before the label.
  final String? icon;

  /// A quiet figure after the label: how many markets the choice holds.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? AppColors.surface : AppColors.textPrimary;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: Size(48, dense ? 32 : 40),
          // Drawn smaller; the padded tap target keeps it at 48dp to touch.
          tapTargetSize: MaterialTapTargetSize.padded,
          padding:
              dense
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          backgroundColor:
              selected ? AppColors.textPrimary : Colors.transparent,
          foregroundColor: ink,
          side: BorderSide(
            color: selected ? AppColors.textPrimary : const Color(0xFFD8DADD),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(dense ? 10 : 12),
          ),
          textStyle: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        child:
            icon == null && count == null
                ? Text(label)
                : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      BasilIcon(icon!, size: 16, color: ink),
                      const SizedBox(width: 6),
                    ],
                    Flexible(child: Text(label)),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color:
                              selected
                                  ? AppColors.surface.withValues(alpha: .7)
                                  : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
      ),
    );
  }
}

/// A flat catalog row: a tinted glyph beside the complete question and the
/// time it has left, then the venue's two prices as aligned cells. No
/// attribution, units or freshness text per row — the list carries none, and
/// market detail names the venue once. A missing or long-outdated price reads
/// "—"; prices refresh in the background ([CallsProvider.refreshPriceIfStale]).
class CallMarketCard extends StatelessWidget {
  const CallMarketCard({
    super.key,
    required this.market,
    required this.onTap,
    this.sharePrice,
  });

  final VenueMarket market;
  final VoidCallback onTap;
  final SharePriceSnapshot? sharePrice;

  @override
  Widget build(BuildContext context) {
    final close = market.closesAtUtc;
    final left = marketTimeLeft(close);
    final soon = marketEndingSoon(close);
    final timeInk = soon ? AppColors.pinkInk : AppColors.textSecondary;
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarketGlyph(market: market),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          market.question,
                          style: AppTextStyles.marketRowQuestion,
                        ),
                        if (left != null) ...[
                          const SizedBox(height: 6),
                          Semantics(
                            label:
                                'Closes ${CallsFormat.timestampShortUtc(close!)}',
                            excludeSemantics: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BasilIcon(
                                  'clock-outline',
                                  size: 14,
                                  color: timeInk,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    left,
                                    style: GoogleFonts.montserrat(
                                      fontSize: 12,
                                      height: 1.3,
                                      fontWeight:
                                          soon
                                              ? FontWeight.w500
                                              : FontWeight.w400,
                                      color: timeInk,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (market.venue == MarketVenue.panta)
                MarketSharePrices(
                  snapshot:
                      sharePrice?.marketId == market.id ? sharePrice : null,
                )
              else
                MarketDemoTag(
                  label:
                      market.venue.isDemo
                          ? 'Demo data · no live prices'
                          : market.venue.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small tag that keeps sample data visibly sample — never a live market.
class MarketDemoTag extends StatelessWidget {
  const MarketDemoTag({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warningContainer,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BasilIcon(
            'info-circle-outline',
            size: 14,
            color: AppColors.onWarningContainer,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.onWarningContainer,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The prototype's 36dp tinted mark at the head of each row. Decoration only,
/// derived from the market's own question and category — it names nothing the
/// market does not already say.
class MarketGlyph extends StatelessWidget {
  const MarketGlyph({super.key, required this.market});
  final VenueMarket market;

  static const double size = 36;

  static final _btc = RegExp(r'\b(btc|bitcoin)\b', caseSensitive: false);
  static final _eth = RegExp(r'\b(eth|ether|ethereum)\b', caseSensitive: false);
  static final _sol = RegExp(r'\b(sol|solana)\b', caseSensitive: false);
  static final _ticker = RegExp(r'\$([A-Za-z]{2,10})\b');

  static const _neutralFill = Color(0xFFF1F2F4);
  static const _neutralInk = Color(0xFF4B5563);

  @override
  Widget build(BuildContext context) {
    final q = market.question;
    final (String? glyph, String icon, Color fill, Color ink) = switch (q) {
      _ when _btc.hasMatch(q) => (
        '₿',
        '',
        const Color(0xFFFFF2DB),
        const Color(0xFF915A00),
      ),
      _ when _eth.hasMatch(q) => (
        'Ξ',
        '',
        const Color(0xFFEEF0F8),
        const Color(0xFF48547A),
      ),
      _ when _sol.hasMatch(q) => (
        'S',
        '',
        const Color(0xFFEDF3F0),
        const Color(0xFF324E40),
      ),
      _ when _ticker.hasMatch(q) => (
        _ticker.firstMatch(q)!.group(1)!.substring(0, 1).toUpperCase(),
        '',
        _neutralFill,
        _neutralInk,
      ),
      _ => (null, categoryIcon(market.category), _neutralFill, _neutralInk),
    };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(11),
        ),
        child:
            glyph != null
                ? Text(
                  glyph,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontFamily: 'PPNeueMachina',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: ink,
                  ),
                )
                : BasilIcon(icon, size: 20, color: ink),
      ),
    );
  }

  /// The Basil icon for a venue category slug — shared with onboarding's
  /// topic chips so a category looks the same everywhere. Panta's catalog
  /// carries categories beyond its documented create list (pop-culture,
  /// gaming, commodities, …); each gets a fitting mark.
  static String categoryIcon(String category) => switch (category
      .toLowerCase()) {
    'crypto' => 'lightning-outline',
    'meme-coins' => 'fire-outline',
    'sports' => 'award-outline',
    'finance' || 'macroeconomics' || 'business' => 'chart-pie-outline',
    'stocks' => 'chart-pie-alt-outline',
    'commodities' => 'box-outline',
    'politics' => 'bank-outline',
    'entertainment' || 'pop-culture' => 'star-outline',
    'gaming' => 'gamepad-outline',
    'science' || 'space-universe' => 'flask-outline',
    'tech' || 'technology' => 'processor-outline',
    'weather' => 'sun-outline',
    'world' => 'globe-outline',
    _ => 'lightbulb-outline',
  };
}

/// The venue's two independent prices. Each side is its own decimal string —
/// NO is never derived from YES, and a side the venue did not publish (or a
/// price older than [marketPriceShownFor]) reads "—", never zero and never a
/// warning. Prices read rounded to two decimals ([CallsFormat.displayPrice]);
/// market detail keeps the venue's exact figures behind its details.
/// Catalog prices are indicative, never executable quotes.
class MarketSharePrices extends StatelessWidget {
  const MarketSharePrices({super.key, this.snapshot, this.expanded = false});
  final SharePriceSnapshot? snapshot;
  final bool expanded;

  // A quiet tinted cell per side, the side's ink on both its label and its
  // figure. Both inks clear 6:1 on their fills.
  static const _yesFill = Color(0xFFE6F6EF);
  static const _yesInk = Color(0xFF07644C);
  static const _noFill = Color(0xFFEEF0F4);
  static const _noInk = Color(0xFF334155);

  String? _shown(Side side, DateTime now) {
    final snap = snapshot;
    final value = snap?.priceFor(side);
    if (snap == null || value == null) return null;
    // Stamped a little ahead of this device's clock still counts as new.
    if (now.toUtc().difference(snap.observedAtUtc) > marketPriceShownFor) {
      return null;
    }
    return CallsFormat.displayPrice(value);
  }

  Widget _cell(Side side, DateTime now, {required bool large}) {
    final yes = side == Side.yes;
    final ink = yes ? _yesInk : _noInk;
    final shown = _shown(side, now);
    final label = Text(
      side.wire,
      style: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
    );
    final figure = Text(
      shown ?? '—',
      textAlign: large ? TextAlign.start : TextAlign.end,
      semanticsLabel:
          shown == null
              ? 'Price unavailable'
              : '$shown USDC per share, indicative',
      style: TextStyle(
        fontFamily: 'PPNeueMachina',
        fontSize: large ? 26 : 14,
        fontWeight: FontWeight.w800,
        height: large ? 1.15 : 1.2,
        color: shown == null ? ink.withValues(alpha: .45) : ink,
      ),
    );
    return Container(
      padding: EdgeInsets.all(large ? 12 : 10),
      decoration: BoxDecoration(
        color: yes ? _yesFill : _noFill,
        borderRadius: BorderRadius.circular(large ? 12 : 11),
      ),
      child:
          large
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 6), figure],
              )
              : Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  label,
                  const SizedBox(width: 8),
                  Expanded(child: figure),
                ],
              ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final large = expanded;
    final pair = LayoutBuilder(
      builder: (context, constraints) {
        // Side by side until large text or a narrow column would squeeze a
        // figure; then stacked, never ellipsised.
        final stack =
            MediaQuery.textScalerOf(context).scale(large ? 18 : 14) >
                (large ? 27 : 21) ||
            constraints.maxWidth < 250;
        return stack
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cell(Side.yes, now, large: large),
                const SizedBox(height: 8),
                _cell(Side.no, now, large: large),
              ],
            )
            : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _cell(Side.yes, now, large: large)),
                const SizedBox(width: 8),
                Expanded(child: _cell(Side.no, now, large: large)),
              ],
            );
      },
    );
    if (!expanded) return pair;
    // Detail names the venue once, with what the figures are: indicative
    // venue prices in USDC per share. Panta's API terms (§6) ask for the
    // attribution on the market module.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pair,
        const SizedBox(height: 8),
        Text(
          '${SharePriceSnapshot.attribution} · indicative USDC per share',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
