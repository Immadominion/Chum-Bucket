import 'package:flutter/material.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Presentation windows only. Server eligibility still governs every write.
enum MarketDiscoveryWindow {
  endingSoon('Ending soon', Duration(hours: 48)),
  thisWeek('This week', Duration(days: 7));

  const MarketDiscoveryWindow(this.label, this.horizon);
  final String label;
  final Duration horizon;
}

List<VenueMarket> discoveryMarkets(
  Iterable<VenueMarket> markets, {
  required MarketDiscoveryWindow window,
  String query = '',
  DateTime? now,
}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final term = query.trim().toLowerCase();
  return markets.where((market) {
      final close = market.closesAtUtc;
      if (close == null ||
          !market.status.acceptsNewCalls ||
          market.category.toLowerCase() != 'crypto' ||
          (market.venue != MarketVenue.panta && !market.venue.isDemo) ||
          (market.opensAt != null &&
              market.opensAt! > reference.millisecondsSinceEpoch)) {
        return false;
      }
      final remaining = close.difference(reference);
      return remaining >= const Duration(hours: 4) &&
          remaining <= window.horizon &&
          market.question.toLowerCase().contains(term);
    }).toList()
    ..sort((a, b) => a.closesAt!.compareTo(b.closesAt!));
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

/// A flat catalog row. Only an actual Panta snapshot supplies share prices.
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Center(
                    child: BasilIcon(
                      'chart-pie-alt-outline',
                      size: 22,
                      color: AppColors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        market.question,
                        style: AppTextStyles.textTheme.titleMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        market.closesAtUtc == null
                            ? 'Close time unavailable'
                            : 'Closes ${CallsFormat.timestampShortUtc(market.closesAtUtc!)}',
                        style: AppTextStyles.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
