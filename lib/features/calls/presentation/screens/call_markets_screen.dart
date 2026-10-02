import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

/// Public discovery; the root shell owns navigation and the floating tab bar.
class CallMarketsScreen extends StatefulWidget {
  const CallMarketsScreen({
    super.key,
    this.embedded = false,
    this.onActivityTap,
  });

  final bool embedded;
  final VoidCallback? onActivityTap;

  @override
  State<CallMarketsScreen> createState() => _CallMarketsScreenState();
}

class _CallMarketsScreenState extends State<CallMarketsScreen> {
  // The prototype sets its search field at 12px; 13 keeps typed text legible.
  static final _searchText = GoogleFonts.montserrat(
    fontSize: 13,
    color: AppColors.textPrimary,
  );

  String _query = '';
  MarketDiscoveryWindow _window = MarketDiscoveryWindow.all;
  bool _cryptoOnly = false;
  final _requestedPrices = <String>{};
  String? _priceViewer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadOpenMarkets();
    });
  }

  Future<void> _refresh() async {
    _requestedPrices.clear();
    await context.read<CallsProvider>().loadOpenMarkets(force: true);
  }

  void _requestPrice(String marketId) {
    if (!_requestedPrices.add(marketId)) return;
    // Only visible/cache-extent rows are requested. The existing provider owns
    // caching, account isolation and in-flight deduplication.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = context.read<CallsProvider>();
        if (!provider.isLoadingMarket(marketId)) {
          provider.loadMarketDetail(marketId, force: true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallsProvider>();
    if (_priceViewer != provider.viewerUserId) {
      _priceViewer = provider.viewerUserId;
      _requestedPrices.clear();
    }
    final rows = discoveryMarkets(
      provider.openMarkets,
      window: _window,
      query: _query,
      category: _cryptoOnly ? 'crypto' : null,
    );
    final bottomPadding = widget.embedded ? 128.0 : 24.0;
    final content = RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const PageStorageKey('markets-discovery'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.embedded)
                    ChumbucketAppHeader(
                      title: 'Markets',
                      showAccountActions: false,
                      onActivityTap: widget.onActivityTap,
                    )
                  else
                    const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    style: _searchText,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search predictions',
                      hintStyle: _searchText.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      prefixIcon: const Padding(
                        padding: EdgeInsets.fromLTRB(14, 0, 9, 0),
                        child: BasilIcon(
                          'search-outline',
                          size: 19,
                          color: Color(0xFF7B8290),
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 42,
                        minHeight: 48,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.fromLTRB(0, 15, 14, 15),
                      // Borderless white field, as in the prototype. The
                      // theme's enabledBorder would otherwise outline it; the
                      // focus ring stays for keyboard and screen-reader users.
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  MarketWindowFilters(
                    selected: _window,
                    onChanged: (value) => setState(() => _window = value),
                  ),
                  const SizedBox(height: 15),
                  // The prototype's section header; the category toggle sits
                  // where it puts "Crypto", keeping the date chips one row.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Make your next call',
                          style: AppTextStyles.questionTitle.copyWith(
                            fontSize: 17,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Semantics(
                        toggled: _cryptoOnly,
                        child: MarketFilterChip(
                          label: 'Crypto only',
                          dense: true,
                          selected: _cryptoOnly,
                          onPressed:
                              () => setState(() => _cryptoOnly = !_cryptoOnly),
                        ),
                      ),
                    ],
                  ),
                  if (rows.any(
                    (market) => market.venue == MarketVenue.panta,
                  )) ...[
                    const SizedBox(height: 2),
                    const MarketCatalogLegend(),
                  ],
                ],
              ),
            ),
          ),
          if (provider.openMarkets.isNotEmpty &&
              (provider.isOffline || provider.openMarketsError != null))
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.isOffline
                          ? 'Offline · showing the last loaded markets.'
                          : provider.openMarketsError!,
                      style: AppTextStyles.textTheme.bodySmall?.copyWith(
                        color: AppColors.onWarningContainer,
                      ),
                    ),
                    TextButton(
                      onPressed: _refresh,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: AppColors.onPrimaryContainer,
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          if (provider.isLoadingOpenMarkets && provider.openMarkets.isEmpty)
            const SliverToBoxAdapter(
              child: SizedBox(height: 360, child: CallsLoadingView(rows: 2)),
            )
          else if (provider.openMarkets.isEmpty && provider.isOffline)
            SliverToBoxAdapter(child: CallsOfflineView(onRetry: _refresh))
          else if (provider.openMarkets.isEmpty &&
              provider.openMarketsError != null)
            SliverToBoxAdapter(
              child: CallsErrorView(
                message: provider.openMarketsError!,
                onRetry: _refresh,
              ),
            )
          else if (rows.isEmpty)
            SliverToBoxAdapter(
              child: CallsEmptyView(
                artwork: ChumbucketStateArtwork.search,
                title:
                    _query.trim().isEmpty
                        ? 'No open markets match these filters'
                        : 'No matching questions',
                message:
                    'Try all categories and dates, or refresh the Panta catalog.',
                actionLabel:
                    _window != MarketDiscoveryWindow.all || _cryptoOnly
                        ? 'Show all markets'
                        : 'Refresh',
                onAction:
                    _window != MarketDiscoveryWindow.all || _cryptoOnly
                        ? () => setState(() {
                          _window = MarketDiscoveryWindow.all;
                          _cryptoOnly = false;
                        })
                        : _refresh,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final market = rows[index];
                  _requestPrice(market.id);
                  return ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: index == 0 ? const Radius.circular(22) : Radius.zero,
                      bottom:
                          index == rows.length - 1
                              ? const Radius.circular(22)
                              : Radius.zero,
                    ),
                    child: Column(
                      children: [
                        CallMarketCard(
                          market: market,
                          sharePrice:
                              provider.marketDetail(market.id)?.sharePrice,
                          onTap:
                              () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder:
                                      (_) => MarketDetailScreen(
                                        marketId: market.id,
                                      ),
                                ),
                              ),
                        ),
                        if (index < rows.length - 1)
                          const ColoredBox(
                            color: AppColors.surface,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Divider(
                                height: 1,
                                color: AppColors.divider,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              bottomPadding + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverToBoxAdapter(
              child: Text(
                'Venue prices, not crowd probabilities. Read the rules before making your call.',
                style: AppTextStyles.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return ColoredBox(
      color: AppColors.background,
      child:
          widget.embedded ? SafeArea(bottom: false, child: content) : content,
    );
  }
}
