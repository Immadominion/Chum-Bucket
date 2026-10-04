/// Select an existing eligible market before opening the free-call composer.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart'
    show CallsLoadingView, CallsSignedOutView;
import 'package:chumbucket/features/calls/presentation/widgets/market_filters.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_state_view.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

Future<CallFeedEntry?> showMarketPickerSheet({required BuildContext context}) =>
    showChumbucketWavySheet<CallFeedEntry>(
      context: context,
      builder: (_) => const MarketPickerSheet(),
    );

/// The same list, returning the chosen market instead of composing — for a
/// caller that opens its own composer (onboarding, which also lets a
/// signed-out person pick and sign in at Lock).
Future<VenueMarket?> showMarketChooser({required BuildContext context}) =>
    showChumbucketWavySheet<VenueMarket>(
      context: context,
      builder: (_) => const MarketPickerSheet(pickOnly: true),
    );

class MarketPickerSheet extends StatefulWidget {
  const MarketPickerSheet({super.key, this.pickOnly = false});

  /// Return the market rather than open the composer; reading needs no
  /// account.
  final bool pickOnly;

  @override
  State<MarketPickerSheet> createState() => _MarketPickerSheetState();
}

class _MarketPickerSheetState extends State<MarketPickerSheet> {
  String _query = '';
  String? _picking;
  MarketFilters _filters = MarketFilters.none;

  /// Rows built this frame; their prices are checked once, after it.
  final _shown = <String>{};
  bool _priceCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().refreshOpenMarketsIfStale();
    });
  }

  void _notePriceShown(String marketId) {
    _shown.add(marketId);
    if (_priceCheckScheduled) return;
    _priceCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _priceCheckScheduled = false;
      final ids = _shown.toList();
      _shown.clear();
      if (!mounted) return;
      final provider = context.read<CallsProvider>();
      for (final id in ids) {
        provider.refreshPriceIfStale(id);
      }
    });
  }

  Future<void> _pick(VenueMarket market) async {
    if (_picking != null) return;
    if (widget.pickOnly) {
      Navigator.of(context).pop(market);
      return;
    }
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
        final open = provider.openMarkets;
        final categories = discoveryCategories(open);
        final hasActivity = discoveryHasActivity(open);
        var filters = _filters;
        if (filters.category != null &&
            !categories.any((entry) => entry.category == filters.category)) {
          filters = filters.withTopic();
        }
        if (!hasActivity && filters.sort != MarketDiscoverySort.closingSoon) {
          filters = filters.withSort(MarketDiscoverySort.closingSoon);
        }
        final rows = discoveryMarkets(
          open,
          window: filters.window,
          query: _query,
          category: filters.category,
          sort: filters.sort,
        );
        void retry() => provider.loadOpenMarkets(force: true);
        final Widget? state =
            !provider.isSignedIn && !widget.pickOnly
                ? const CallsSignedOutView()
                : provider.isLoadingOpenMarkets && open.isEmpty
                ? const SizedBox(height: 300, child: CallsLoadingView(rows: 2))
                : open.isEmpty && provider.isOffline
                ? MarketStateView(
                  artwork: ChumbucketStateArtwork.offline,
                  line: 'You\'re offline',
                  actionLabel: 'Try again',
                  onAction: retry,
                  compact: true,
                )
                : open.isEmpty && provider.openMarketsError != null
                ? MarketStateView(
                  artwork: ChumbucketStateArtwork.error,
                  line: 'Markets didn\'t load',
                  actionLabel: 'Try again',
                  onAction: retry,
                  compact: true,
                )
                : rows.isEmpty
                ? MarketStateView(
                  artwork: ChumbucketStateArtwork.search,
                  line:
                      open.isEmpty
                          ? 'No open markets right now'
                          : filters.isEmpty
                          ? 'No matches'
                          : 'Nothing matches these filters',
                  actionLabel: filters.isEmpty ? null : 'Clear filters',
                  onAction: () => setState(() => _filters = MarketFilters.none),
                  compact: true,
                )
                : null;
        final controls = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MarketSearchBar(
              fill: AppColors.background,
              activeFilters: filters.activeCount,
              onQueryChanged: (value) => setState(() => _query = value),
              onFilters:
                  () => showMarketFilterSheet(
                    context: context,
                    value: filters,
                    categories: categories,
                    offerMostActive: hasActivity,
                    onChanged: (next) {
                      if (mounted) setState(() => _filters = next);
                    },
                  ),
            ),
            if (!filters.isEmpty)
              MarketActiveFilters(
                filters: filters,
                onChanged: (next) => setState(() => _filters = next),
              ),
            const SizedBox(height: 12),
            if (state != null) state,
          ],
        );
        return ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          itemCount: state != null ? 1 : rows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) return controls;
            final market = rows[index - 1];
            _notePriceShown(market.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
            );
          },
        );
      },
    ),
  );
}
