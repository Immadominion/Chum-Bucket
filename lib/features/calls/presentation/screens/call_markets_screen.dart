import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/market_creation/market_creation.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
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

  /// A category slug from the catalog itself, or null for all of them.
  String? _category;
  MarketDiscoverySort _sort = MarketDiscoverySort.closingSoon;
  final _requestedPrices = <String>{};
  String? _priceViewer;

  /// "For you": the topics chosen in onboarding (or Settings) first, then the
  /// rest under "More on Panta". On by default the first time after topics
  /// were chosen; afterwards it is whatever was last picked here.
  bool _forYou = false;
  bool _forYouDecided = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadOpenMarkets();
    });
  }

  void _decideForYou(OnboardingController? app) {
    if (_forYouDecided || app == null || !app.loaded) return;
    _forYouDecided = true;
    if (app.record.forYouPending && app.topics.isNotEmpty) {
      _forYou = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) app.consumeForYou();
      });
    }
  }

  Future<void> _refresh() async {
    _requestedPrices.clear();
    await context.read<CallsProvider>().loadOpenMarkets(force: true);
  }

  /// Proposing needs an account; reading the catalog never does.
  void _openMarketCreation({required bool create}) {
    if (!context.read<CallsProvider>().isSignedIn) {
      requestCallSignIn(context);
      return;
    }
    openMarketCreation(context, create: create);
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
    final app = context.watch<OnboardingController?>();
    _decideForYou(app);
    final topics = app?.topics ?? const <String>{};
    if (app != null && app.record.forYouPending && topics.isNotEmpty) {
      // Topics were (re)chosen while this tab was alive: show them first.
      if (!_forYou) _forYou = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) app.consumeForYou();
      });
    }
    final forYou = _forYou && topics.isNotEmpty;
    if (_priceViewer != provider.viewerUserId) {
      _priceViewer = provider.viewerUserId;
      _requestedPrices.clear();
    }
    final open = provider.openMarkets;
    final categories = discoveryCategories(open);
    // A category that closed out since it was picked is not a silent filter.
    final category =
        categories.any((entry) => entry.category == _category)
            ? _category
            : null;
    final hasActivity = discoveryHasActivity(open);
    final sort = hasActivity ? _sort : MarketDiscoverySort.closingSoon;
    final openCount = categories.fold(0, (sum, entry) => sum + entry.count);
    final filtered = _window != MarketDiscoveryWindow.all || category != null;
    final listed = discoveryMarkets(
      open,
      window: _window,
      query: _query,
      category: forYou ? null : category,
      sort: sort,
    );
    final split = forYou ? forYouOrder(listed, topics) : null;
    final rows = split == null ? listed : [...split.chosen, ...split.more];
    // Where "More on Panta" begins, when For you splits the list.
    final moreAt =
        split != null && split.chosen.isNotEmpty && split.more.isNotEmpty
            ? split.chosen.length
            : null;
    final bottomPadding = widget.embedded ? 128.0 : 24.0;
    final content = RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const PageStorageKey('markets-discovery'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                ],
              ),
            ),
          ),
          // Edge to edge: the row scrolls under the screen edge rather than
          // clipping at the gutter, while its first chip keeps the gutter.
          if (categories.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(top: 8),
              sliver: SliverToBoxAdapter(
                child: MarketCategoryFilters(
                  categories: categories,
                  selected: category,
                  onChanged:
                      (value) => setState(() {
                        _category = value;
                        _forYou = false;
                      }),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  forYouSelected: topics.isEmpty ? null : forYou,
                  onForYou: () => setState(() => _forYou = !_forYou),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The prototype's section header. The sort toggle sits where
                  // it puts "Crypto", and only when the venue reports volume:
                  // "Most active" over all-zero figures would be a coin flip.
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
                      if (hasActivity)
                        Semantics(
                          toggled: sort == MarketDiscoverySort.mostActive,
                          child: MarketFilterChip(
                            label: MarketDiscoverySort.mostActive.label,
                            dense: true,
                            selected: sort == MarketDiscoverySort.mostActive,
                            onPressed:
                                () => setState(
                                  () =>
                                      _sort =
                                          sort == MarketDiscoverySort.mostActive
                                              ? MarketDiscoverySort.closingSoon
                                              : MarketDiscoverySort.mostActive,
                                ),
                          ),
                        ),
                    ],
                  ),
                  if (openCount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      discoveryCountLabel(
                        shown: rows.length,
                        open: openCount,
                        sort: sort,
                      ),
                      style: AppTextStyles.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (rows.any(
                    (market) => market.venue == MarketVenue.panta,
                  )) ...[
                    const SizedBox(height: 2),
                    const MarketCatalogLegend(),
                  ],
                  // Shown only while the server takes proposals.
                  CreateMarketEntry(
                    onCreate: () => _openMarketCreation(create: true),
                    onOpenMine: () => _openMarketCreation(create: false),
                  ),
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
                actionLabel: filtered ? 'Show all markets' : 'Refresh',
                onAction:
                    filtered
                        ? () => setState(() {
                          _window = MarketDiscoveryWindow.all;
                          _category = null;
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
                  final row = ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top:
                          index == 0 || index == moreAt
                              ? const Radius.circular(22)
                              : Radius.zero,
                      bottom:
                          index == rows.length - 1 ||
                                  (moreAt != null && index == moreAt - 1)
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
                        if (index < rows.length - 1 &&
                            (moreAt == null || index != moreAt - 1))
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
                  if (index != moreAt) return row;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
                        child: Semantics(
                          header: true,
                          child: Text(
                            'More on Panta',
                            style: AppTextStyles.questionTitle.copyWith(
                              fontSize: 15,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ),
                      row,
                    ],
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
