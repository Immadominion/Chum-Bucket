import 'dart:async';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart'
    show CallsLoadingView;
import 'package:chumbucket/features/calls/presentation/widgets/market_filters.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_state_view.dart';
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
///
/// Stateful by design: the catalog and prices already loaded show at once,
/// and stay current in the background — on a timer while this screen is the
/// one in front, when it comes back into view and when the app returns to the
/// foreground. There is no refresh button and no "updated" line; pull to
/// refresh remains for anyone who wants it now.
class CallMarketsScreen extends StatefulWidget {
  const CallMarketsScreen({
    super.key,
    this.embedded = false,
    this.onActivityTap,
  });

  final bool embedded;
  final VoidCallback? onActivityTap;

  /// How often a visible screen checks for prices and a catalog due a
  /// re-read. Each check is free unless something is actually due.
  static const tick = Duration(seconds: 30);

  @override
  State<CallMarketsScreen> createState() => _CallMarketsScreenState();
}

class _CallMarketsScreenState extends State<CallMarketsScreen>
    with WidgetsBindingObserver {
  String _query = '';
  MarketFilters _filters = MarketFilters.none;

  /// "For you" (the topics chosen in onboarding or Settings first, then the
  /// rest) is on by default the first time after topics were chosen;
  /// afterwards it is whatever was last picked here.
  bool _forYouDecided = false;

  Timer? _ticker;
  bool _foreground = true;

  /// On screen, its route on top, and the app in the foreground.
  bool _active = false;

  /// Market ids whose rows were built this frame; their prices are checked
  /// once, after the frame.
  final _shown = <String>{};
  bool _priceCheckScheduled = false;

  /// After a pull to refresh, the rows on screen are read again once,
  /// however new their prices. Consumed by the next price check.
  bool _pulled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CallsProvider>().loadOpenMarkets();
    });
    _ticker = Timer.periodic(CallMarketsScreen.tick, (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!mounted) return;
    // Rebuilding re-checks the visible rows' prices; the catalog is re-read
    // if it went stale while the app was away.
    setState(() {});
    if (foreground) context.read<CallsProvider>().refreshOpenMarketsIfStale();
  }

  void _onTick() {
    if (!mounted || !_active) return;
    final provider = context.read<CallsProvider>();
    // An empty catalog's state screen keeps its own "Try again"; retrying it
    // on a timer would flicker it into a skeleton and back.
    if (provider.openMarkets.isNotEmpty) provider.refreshOpenMarketsIfStale();
    setState(() {});
  }

  Future<void> _refresh() async {
    _pulled = true;
    await context.read<CallsProvider>().loadOpenMarkets(force: true);
  }

  void _decideForYou(OnboardingController? app) {
    if (_forYouDecided || app == null || !app.loaded) return;
    _forYouDecided = true;
    if (app.record.forYouPending && app.topics.isNotEmpty) {
      _filters = _filters.withTopic(forYou: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) app.consumeForYou();
      });
    }
  }

  /// Proposing needs an account; reading the catalog never does.
  void _openMarketCreation({required bool create}) {
    if (!context.read<CallsProvider>().isSignedIn) {
      requestCallSignIn(context);
      return;
    }
    openMarketCreation(context, create: create);
  }

  /// Keeps a shown row's price current: the provider re-reads it only when
  /// it is missing or getting old. While this screen is not in front, only a
  /// price never read is fetched, so the tab is ready when it is opened.
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
      final pulled = _pulled;
      _pulled = false;
      for (final id in ids) {
        if (pulled) {
          if (!provider.isLoadingMarket(id)) {
            provider.loadMarketDetail(id, force: true);
          }
        } else if (_active || provider.marketDetail(id) == null) {
          provider.refreshPriceIfStale(id);
        }
      }
    });
  }

  void _openFilters({
    required MarketFilters value,
    required List<MarketCategoryCount> categories,
    required bool offerForYou,
    required bool offerMostActive,
  }) {
    showMarketFilterSheet(
      context: context,
      value: value,
      categories: categories,
      offerForYou: offerForYou,
      offerMostActive: offerMostActive,
      onChanged: (next) {
        if (mounted) setState(() => _filters = next);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallsProvider>();
    final app = context.watch<OnboardingController?>();
    final active =
        _foreground &&
        Visibility.of(context) &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (active && !_active) {
      // Back in view: a catalog that went stale meanwhile is re-read.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<CallsProvider>().refreshOpenMarketsIfStale();
      });
    }
    _active = active;

    _decideForYou(app);
    final topics = app?.topics ?? const <String>{};
    if (app != null && app.record.forYouPending && topics.isNotEmpty) {
      // Topics were (re)chosen while this tab was alive: show them first.
      if (!_filters.forYou) _filters = _filters.withTopic(forYou: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) app.consumeForYou();
      });
    }
    final open = provider.openMarkets;
    final categories = discoveryCategories(open);
    final hasActivity = discoveryHasActivity(open);
    // A category that closed out, "For you" without topics, or "Most active"
    // over no reported volume is never a silent filter.
    var filters = _filters;
    if (filters.category != null &&
        !categories.any((entry) => entry.category == filters.category)) {
      filters = filters.withTopic();
    }
    if (filters.forYou && topics.isEmpty) filters = filters.withTopic();
    if (!hasActivity && filters.sort != MarketDiscoverySort.closingSoon) {
      filters = filters.withSort(MarketDiscoverySort.closingSoon);
    }
    final listed = discoveryMarkets(
      open,
      window: filters.window,
      query: _query,
      category: filters.forYou ? null : filters.category,
      sort: filters.sort,
    );
    final split = filters.forYou ? forYouOrder(listed, topics) : null;
    final rows = split == null ? listed : [...split.chosen, ...split.more];
    // Where "More markets" begins, when For you splits the list.
    final moreAt =
        split != null && split.chosen.isNotEmpty && split.more.isNotEmpty
            ? split.chosen.length
            : null;
    final bottomPadding =
        (widget.embedded ? 128.0 : 24.0) + MediaQuery.paddingOf(context).bottom;
    final loading = provider.isLoadingOpenMarkets && open.isEmpty;

    Widget? state;
    if (loading) {
      state = null;
    } else if (open.isEmpty && provider.isOffline) {
      state = MarketStateView(
        artwork: ChumbucketStateArtwork.offline,
        line: 'You\'re offline',
        actionLabel: 'Try again',
        onAction: _refresh,
      );
    } else if (open.isEmpty && provider.openMarketsError != null) {
      state = MarketStateView(
        artwork: ChumbucketStateArtwork.error,
        line: 'Markets didn\'t load',
        actionLabel: 'Try again',
        onAction: _refresh,
      );
    } else if (rows.isEmpty) {
      final narrowed = !filters.isEmpty;
      state = MarketStateView(
        artwork: ChumbucketStateArtwork.search,
        line:
            open.isEmpty
                ? 'No open markets right now'
                : narrowed
                ? 'Nothing matches these filters'
                : 'No matches',
        actionLabel: narrowed ? 'Clear filters' : null,
        onAction:
            narrowed
                ? () => setState(() => _filters = MarketFilters.none)
                : null,
      );
    }

    final content = RefreshIndicator(
      color: AppColors.primary,
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
                  MarketSearchBar(
                    activeFilters: filters.activeCount,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onFilters:
                        () => _openFilters(
                          value: filters,
                          categories: categories,
                          offerForYou: topics.isNotEmpty,
                          offerMostActive: hasActivity,
                        ),
                  ),
                ],
              ),
            ),
          ),
          // Edge to edge: the pills scroll under the screen edge rather than
          // clipping at the gutter, while the first keeps the gutter.
          if (!filters.isEmpty)
            SliverToBoxAdapter(
              child: MarketActiveFilters(
                filters: filters,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                onChanged: (next) => setState(() => _filters = next),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, filters.isEmpty ? 4 : 0, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (provider.isOffline && open.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _OfflinePill(),
                      ),
                    ),
                  // Shown only while the server takes proposals.
                  CreateMarketEntry(
                    onCreate: () => _openMarketCreation(create: true),
                    onOpenMine: () => _openMarketCreation(create: false),
                  ),
                ],
              ),
            ),
          ),
          if (loading)
            const SliverToBoxAdapter(
              child: SizedBox(height: 360, child: CallsLoadingView(rows: 2)),
            )
          else if (state != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: state,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final market = rows[index];
                  _notePriceShown(market.id);
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
                            'More markets',
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
          if (state == null)
            SliverPadding(padding: EdgeInsets.only(bottom: bottomPadding)),
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

/// Cached rows are on screen but the app cannot reach the server. Says so
/// in a word; pull to refresh and the background checks retry.
class _OfflinePill extends StatelessWidget {
  const _OfflinePill();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: 'Offline, showing saved markets',
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warningContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BasilIcon(
            'cloud-off-outline',
            size: 15,
            color: AppColors.onWarningContainer,
          ),
          const SizedBox(width: 6),
          Text(
            'Offline',
            style: GoogleFonts.montserrat(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.onWarningContainer,
            ),
          ),
        ],
      ),
    ),
  );
}
