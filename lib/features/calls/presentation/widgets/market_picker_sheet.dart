/// Select an existing eligible market before opening the free-call composer.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

Future<CallFeedEntry?> showMarketPickerSheet({required BuildContext context}) =>
    showChumbucketWavySheet<CallFeedEntry>(
      context: context,
      builder: (_) => const MarketPickerSheet(),
    );

class MarketPickerSheet extends StatefulWidget {
  const MarketPickerSheet({super.key});

  @override
  State<MarketPickerSheet> createState() => _MarketPickerSheetState();
}

class _MarketPickerSheetState extends State<MarketPickerSheet> {
  String _query = '';
  String? _picking;
  MarketDiscoveryWindow _window = MarketDiscoveryWindow.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadOpenMarkets();
    });
  }

  Future<void> _pick(VenueMarket market) async {
    if (_picking != null) return;
    setState(() => _picking = market.id);
    try {
      final provider = context.read<CallsProvider>();
      final detail = await provider.loadMarketDetail(market.id, force: true);
      if (!mounted) return;
      // Preserve the existing composer eligibility/error contract, including
      // a failed refresh or missing snapshot. Selection never places a trade.
      final entry = await showCallComposer(
        context: context,
        market: detail?.market ?? market,
        snapshot: detail?.snapshot,
        sharePrice: detail?.sharePrice,
      );
      if (entry != null && mounted) Navigator.of(context).pop(entry);
    } finally {
      if (mounted) setState(() => _picking = null);
    }
  }

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Choose a market',
    body: Consumer<CallsProvider>(
      builder: (context, provider, _) {
        final rows = discoveryMarkets(
          provider.openMarkets,
          window: _window,
          query: _query,
        );
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Your opinion. No money involved.',
              style: AppTextStyles.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              style: AppTextStyles.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Search predictions',
                hintStyle: AppTextStyles.textTheme.bodyMedium,
                filled: true,
                fillColor: AppColors.background,
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(14),
                  child: BasilIcon(
                    'search-outline',
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            MarketWindowFilters(
              selected: _window,
              onChanged: (value) => setState(() => _window = value),
            ),
            const SizedBox(height: 8),
            Text(switch (_window) {
              MarketDiscoveryWindow.all => 'All open Panta markets',
              MarketDiscoveryWindow.endingSoon => 'Closing within 48 hours',
              MarketDiscoveryWindow.thisWeek => 'Closing within 7 days',
            }, style: AppTextStyles.textTheme.bodySmall),
            if (rows.any((market) => market.venue == MarketVenue.panta)) ...[
              const SizedBox(height: 8),
              const MarketCatalogLegend(),
            ],
            const SizedBox(height: 16),
            if (!provider.isSignedIn)
              const CallsSignedOutView()
            else if (provider.isLoadingOpenMarkets &&
                provider.openMarkets.isEmpty)
              const SizedBox(height: 300, child: CallsLoadingView(rows: 2))
            else if (provider.openMarkets.isEmpty && provider.isOffline)
              CallsOfflineView(
                onRetry: () => provider.loadOpenMarkets(force: true),
              )
            else if (provider.openMarkets.isEmpty &&
                provider.openMarketsError != null)
              CallsErrorView(
                message: provider.openMarketsError!,
                onRetry: () => provider.loadOpenMarkets(force: true),
              )
            else ...[
              if (provider.isOffline || provider.openMarketsError != null) ...[
                Text(
                  provider.isOffline
                      ? 'Offline · showing cached markets.'
                      : provider.openMarketsError!,
                  style: AppTextStyles.textTheme.bodySmall?.copyWith(
                    color: AppColors.onWarningContainer,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => provider.loadOpenMarkets(force: true),
                  child: const Text('Retry'),
                ),
              ],
              if (rows.isEmpty)
                CallsEmptyView(
                  artwork: ChumbucketStateArtwork.search,
                  title: 'Nothing open in this window',
                  message: 'Try another search or time filter.',
                  actionLabel:
                      _window == MarketDiscoveryWindow.endingSoon
                          ? 'Show this week'
                          : 'Refresh',
                  onAction:
                      _window == MarketDiscoveryWindow.endingSoon
                          ? () => setState(
                            () => _window = MarketDiscoveryWindow.thisWeek,
                          )
                          : () => provider.loadOpenMarkets(force: true),
                ),
              for (final market in rows) ...[
                if (_picking == market.id)
                  const LinearProgressIndicator(
                    semanticsLabel: 'Loading market',
                  ),
                AbsorbPointer(
                  absorbing: _picking != null,
                  child: CallMarketCard(
                    market: market,
                    sharePrice: provider.marketDetail(market.id)?.sharePrice,
                    onTap: () => _pick(market),
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
              ],
            ],
          ],
        );
      },
    ),
  );
}
