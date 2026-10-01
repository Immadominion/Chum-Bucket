import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';

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
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final window in MarketDiscoveryWindow.values)
        Semantics(
          selected: selected == window,
          child: OutlinedButton(
            onPressed: () => onChanged(window),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              backgroundColor:
                  selected == window
                      ? AppColors.textPrimary
                      : Colors.transparent,
              foregroundColor:
                  selected == window
                      ? AppColors.surface
                      : AppColors.textPrimary,
              side: BorderSide(
                color:
                    selected == window
                        ? AppColors.textPrimary
                        : AppColors.outline,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: AppTextStyles.textTheme.labelLarge,
            ),
            child: Text(window.label),
          ),
        ),
    ],
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

/// A flat catalog row. Only an actual Panta snapshot supplies share prices.
/// The parent catalog supplies [MarketCatalogLegend]; detail retains full units.
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(market.question, style: AppTextStyles.questionTitle),
            const SizedBox(height: 4),
            Text(
              market.closesAtUtc == null
                  ? 'Close time unavailable'
                  : 'Closes ${CallsFormat.timestampShortUtc(market.closesAtUtc!)}',
              style: AppTextStyles.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
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

/// Independent decimal strings are preserved, including prices above one.
/// Catalog prices are indicative, never executable quotes.
class MarketSharePrices extends StatelessWidget {
  const MarketSharePrices({super.key, this.snapshot, this.expanded = false});
  final SharePriceSnapshot? snapshot;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      final fresh = snapshot?.isUsableAt(DateTime.now()) ?? false;
      return LayoutBuilder(
        builder:
            (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final side in Side.values)
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color:
                              side == Side.yes
                                  ? AppColors.successContainer.withValues(
                                    alpha: .4,
                                  )
                                  : AppColors.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              side.wire,
                              style: AppTextStyles.textTheme.labelMedium
                                  ?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              snapshot?.priceFor(side) ?? 'Price unavailable',
                              semanticsLabel:
                                  snapshot?.priceFor(side) == null
                                      ? 'Price unavailable'
                                      : '${snapshot!.priceFor(side)} USDC per share, indicative',
                              style: AppTextStyles.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
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
            ),
      );
    }
    Widget price(Side side) {
      final value = snapshot?.priceFor(side);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              side == Side.yes
                  ? AppColors.successContainer.withValues(alpha: 0.4)
                  : AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              side.wire,
              style: AppTextStyles.textTheme.labelMedium?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color:
                    side == Side.yes
                        ? AppColors.onSuccessContainer
                        : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value ?? 'Price unavailable',
              style:
                  value == null
                      ? AppTextStyles.textTheme.bodySmall
                      : AppTextStyles.textTheme.titleMedium?.copyWith(
                        fontSize: expanded ? 26 : 18,
                        fontWeight: FontWeight.w800,
                      ),
            ),
          ],
        ),
      );
    }

    final observed = snapshot?.observedAtUtc;
    final fresh = snapshot?.isUsableAt(DateTime.now()) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stack =
                MediaQuery.textScalerOf(context).scale(18) > 27 ||
                constraints.maxWidth < 250;
            return stack
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    price(Side.yes),
                    const SizedBox(height: 8),
                    price(Side.no),
                  ],
                )
                : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: price(Side.yes)),
                    const SizedBox(width: 8),
                    Expanded(child: price(Side.no)),
                  ],
                );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '${SharePriceSnapshot.attribution} · USDC per share',
          style: AppTextStyles.textTheme.bodySmall,
        ),
        if (observed != null)
          Text(
            '${fresh ? 'Updated' : 'Last updated'} ${CallsFormat.timestampUtc(observed)}${fresh ? '' : ' · stale or incomplete'}',
            style: AppTextStyles.textTheme.bodySmall?.copyWith(
              color:
                  fresh
                      ? AppColors.textSecondary
                      : AppColors.onWarningContainer,
            ),
          ),
        if (expanded)
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
