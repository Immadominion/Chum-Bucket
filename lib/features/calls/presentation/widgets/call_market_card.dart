import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:google_fonts/google_fonts.dart';

/// Presentation windows only. Server eligibility still governs every write.
enum MarketDiscoveryWindow {
  all('All dates', null),
  endingSoon('Ending soon', Duration(hours: 48)),
  thisWeek('This week', Duration(days: 7));

  const MarketDiscoveryWindow(this.label, this.horizon);
  final String label;
  final Duration? horizon;
}

List<VenueMarket> discoveryMarkets(
  Iterable<VenueMarket> markets, {
  required MarketDiscoveryWindow window,
  String query = '',
  String? category,
  DateTime? now,
}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final term = query.trim().toLowerCase();
  return markets.where((market) {
      final close = market.closesAtUtc;
      if (!market.status.acceptsNewCalls ||
          (category != null &&
              market.category.toLowerCase() != category.toLowerCase()) ||
          (market.venue != MarketVenue.panta && !market.venue.isDemo) ||
          (market.opensAt != null &&
              market.opensAt! > reference.millisecondsSinceEpoch)) {
        return false;
      }
      if (close == null) {
        return window == MarketDiscoveryWindow.all &&
            market.question.toLowerCase().contains(term);
      }
      final remaining = close.difference(reference);
      return remaining > Duration.zero &&
          (window.horizon == null || remaining <= window.horizon!) &&
          market.question.toLowerCase().contains(term);
    }).toList()
    ..sort(
      (a, b) => (a.closesAt ?? 9223372036854775807).compareTo(
        b.closesAt ?? 9223372036854775807,
      ),
    );
}

class MarketWindowFilters extends StatelessWidget {
  const MarketWindowFilters({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final MarketDiscoveryWindow selected;
  final ValueChanged<MarketDiscoveryWindow> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final window in MarketDiscoveryWindow.values)
        Semantics(
          selected: selected == window,
          child: MarketFilterChip(
            label: window.label,
            selected: selected == window,
            onPressed: () => onChanged(window),
          ),
        ),
    ],
  );
}

/// The prototype's filter chip: an outline on the page, 40dp drawn, a 48dp
/// touch target. Its label is 12sp — one up from the prototype's 11px, the
/// smallest size Android recommends for a control.
class MarketFilterChip extends StatelessWidget {
  const MarketFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.dense = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  /// Drawn at 32dp, for a toggle beside a section title rather than in the
  /// chip row. Same 48dp touch target.
  final bool dense;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: Size(48, dense ? 32 : 40),
      // Drawn smaller; the padded tap target keeps it at 48dp to touch.
      tapTargetSize: MaterialTapTargetSize.padded,
      padding:
          dense
              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      backgroundColor: selected ? AppColors.textPrimary : Colors.transparent,
      foregroundColor: selected ? AppColors.surface : AppColors.textPrimary,
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
    child: Text(label),
  );
}

/// One attribution/unit legend for the catalog, rather than one per row.
/// Panta's API terms §6 allow attribution on the relevant market module.
class MarketCatalogLegend extends StatelessWidget {
  const MarketCatalogLegend({super.key});

  @override
  Widget build(BuildContext context) => Text(
    '${SharePriceSnapshot.attribution} · Prices in USDC/share',
    style: AppTextStyles.textTheme.bodySmall?.copyWith(
      color: AppColors.textSecondary,
    ),
  );
}

/// A flat catalog row, laid out as Codex's prototype draws it: a tinted glyph
/// beside the complete question and its close time, then the venue's two
/// prices as aligned cells. Only an actual Panta snapshot supplies prices; the
/// parent catalog supplies [MarketCatalogLegend]; detail keeps full units.
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
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
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
                      const SizedBox(height: 5),
                      Text(
                        market.closesAtUtc == null
                            ? 'Close time unavailable'
                            : 'Closes ${CallsFormat.timestampShortUtc(market.closesAtUtc!)}',
                        // 12, not the prototype's 11px: the metadata floor
                        // in docs/design-audit-2026-10-01.md.
                        style: GoogleFonts.montserrat(
                          fontSize: 12,
                          height: 1.45,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (market.venue == MarketVenue.panta)
              MarketSharePrices(
                snapshot: sharePrice?.marketId == market.id ? sharePrice : null,
              )
            else
              Text(
                market.venue.isDemo
                    ? 'DEMO DATA · ${market.status.label} · No live share prices'
                    : '${market.venue.label} · ${market.status.label}',
                style: AppTextStyles.textTheme.bodySmall?.copyWith(
                  color: AppColors.onWarningContainer,
                ),
              ),
          ],
        ),
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
      _ => (null, _categoryIcon(market.category), _neutralFill, _neutralInk),
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

  static String _categoryIcon(String category) => switch (category
      .toLowerCase()) {
    'crypto' => 'lightning-outline',
    'sports' => 'award-outline',
    'finance' => 'chart-pie-outline',
    'politics' => 'bank-outline',
    'entertainment' => 'play-outline',
    'science' => 'flask-outline',
    'world' => 'globe-outline',
    _ => 'lightbulb-outline',
  };
}

/// The venue's two independent prices. Each side is its own decimal string —
/// NO is never derived from YES, and a missing side reads "Price unavailable",
/// never zero. Rows show them rounded to two decimals for reading
/// ([CallsFormat.displayPrice]); the expanded detail also states the exact
/// venue figures whenever rounding changed them. Catalog prices are
/// indicative, never executable quotes.
class MarketSharePrices extends StatelessWidget {
  const MarketSharePrices({super.key, this.snapshot, this.expanded = false});
  final SharePriceSnapshot? snapshot;
  final bool expanded;

  // Codex's prototype: a quiet tinted cell per side, the side's ink on both
  // its label and its figure. Both inks clear 6:1 on their fills.
  static const _yesFill = Color(0xFFF4F6F5);
  static const _yesInk = Color(0xFF07644C);
  static const _noFill = Color(0xFFF0F1F4);
  static const _noInk = Color(0xFF34404F);

  String? _shown(Side side) {
    final value = snapshot?.priceFor(side);
    return value == null ? null : CallsFormat.displayPrice(value);
  }

  Widget _cell(Side side, {required bool large}) {
    final yes = side == Side.yes;
    final ink = yes ? _yesInk : _noInk;
    final shown = _shown(side);
    final label = Text(
      side.wire,
      style: GoogleFonts.montserrat(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: ink,
      ),
    );
    final figure = Text(
      shown ?? 'Price unavailable',
      textAlign: large ? TextAlign.start : TextAlign.end,
      semanticsLabel:
          shown == null
              ? 'Price unavailable'
              : '$shown USDC per share, indicative',
      style:
          shown == null
              ? AppTextStyles.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              )
              : TextStyle(
                fontFamily: 'PPNeueMachina',
                fontSize: large ? 26 : 14,
                fontWeight: FontWeight.w800,
                height: large ? 1.15 : 1.2,
                color: ink,
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

  Widget _pair(BuildContext context, {required bool large}) => LayoutBuilder(
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
              _cell(Side.yes, large: large),
              const SizedBox(height: 8),
              _cell(Side.no, large: large),
            ],
          )
          : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _cell(Side.yes, large: large)),
              const SizedBox(width: 8),
              Expanded(child: _cell(Side.no, large: large)),
            ],
          );
    },
  );

  @override
  Widget build(BuildContext context) {
    final observed = snapshot?.observedAtUtc;
    final fresh = snapshot?.isUsableAt(DateTime.now()) ?? false;
    if (!expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pair(context, large: false),
          if (snapshot != null && !fresh) ...[
            const SizedBox(height: 6),
            Text(
              'Last updated ${CallsFormat.timestampShortUtc(snapshot!.observedAtUtc)} · stale or incomplete',
              style: AppTextStyles.textTheme.bodySmall?.copyWith(
                color: AppColors.onWarningContainer,
              ),
            ),
          ],
        ],
      );
    }
    final yes = snapshot?.yesPrice;
    final no = snapshot?.noPrice;
    final rounded =
        (yes != null && CallsFormat.priceWasRounded(yes)) ||
        (no != null && CallsFormat.priceWasRounded(no));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pair(context, large: true),
        const SizedBox(height: 8),
        // One caption, as the prototype has it: who, the unit, how fresh.
        Text(
          '${SharePriceSnapshot.attribution} · USDC per share'
          '${observed != null && fresh ? ' · updated ${CallsFormat.relative(observed)}' : ''}',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (rounded)
          // The figures above are rounded for reading; the venue's own values
          // stay one glance away, unaltered.
          Text(
            'Exact: YES ${yes ?? 'unavailable'} · NO ${no ?? 'unavailable'}',
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        if (observed != null && !fresh)
          Text(
            'Last updated ${CallsFormat.timestampUtc(observed)} · stale or incomplete',
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color: AppColors.onWarningContainer,
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Divider(height: 1, color: AppColors.outlineVariant),
        ),
        Text(
          'Independent venue prices. Indicative, not a trade quote.',
          style: AppTextStyles.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
