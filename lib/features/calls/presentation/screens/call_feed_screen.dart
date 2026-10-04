/// The call feed — Global / Following.
///
/// Built to drop straight into the shell's `IndexedStack`
/// (`home.dart:224`) as a fifth/replacement slot; it owns no navigation of its
/// own beyond pushing its detail screens, and it takes its header from
/// `ChumbucketAppHeader` so it reads as the same app.
///
/// Reused verbatim: [ChumbucketTabs] for the mode switch and
/// [ChumbucketAppHeader] for the top bar. Only the row itself is new.
library;

import 'package:flutter/material.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_picker_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/search_screen.dart';
import 'package:chumbucket/features/people/presentation/widgets/top_calls_strip.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class CallFeedScreen extends StatefulWidget {
  /// The shell's header needs auth/profile/arena providers. Tests and embedded
  /// previews turn it off; the app leaves it on.
  final bool showHeader;

  /// Invoked when a signed-out person taps something that needs an account.
  /// The shell owns what "sign in" means — this slice never does it itself.
  final VoidCallback? onSignInRequested;
  final VoidCallback? onBrowseMarkets;

  /// Onboarding's "Make Home yours" card, at the top of the feed. It is laid
  /// out only while onboarding offers it ([OnboardingController
  /// .homeCardEligible]), so for everyone else the feed starts exactly where
  /// it always did — no empty slot, no extra gap.
  final Widget? topBanner;

  const CallFeedScreen({
    super.key,
    this.showHeader = true,
    this.onSignInRequested,
    this.onBrowseMarkets,
    this.topBanner,
  });

  @override
  State<CallFeedScreen> createState() => _CallFeedScreenState();
}

class _CallFeedScreenState extends State<CallFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  /// The viewer the current reads were made for. A sign-in, sign-out or
  /// account switch clears the provider's viewer-scoped caches, so Home reads
  /// again for the new viewer instead of waiting on a skeleton nobody fills.
  Object? _loadedForViewer = _notLoaded;
  static const Object _notLoaded = Object();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _loadFor(CallsProvider provider) {
    if (_loadedForViewer == provider.viewerUserId) return;
    _loadedForViewer = provider.viewerUserId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.loadFeed();
      provider.loadInvitations();
      provider.loadTopCalls();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 320) {
      context.read<CallsProvider>().loadMore();
    }
  }

  Future<void> _refresh() async {
    final provider = context.read<CallsProvider>();
    await Future.wait([
      provider.loadFeed(force: true),
      provider.loadTopCalls(force: true),
    ]);
  }

  void _openSearch() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const PeopleSearchScreen()));

  /// The strip, or nothing: shown only with real entries, never a skeleton
  /// that could read as activity.
  /// [CallFeedScreen.topBanner], while onboarding offers it; else nothing.
  Widget? _shownBanner() {
    final banner = widget.topBanner;
    if (banner == null) return null;
    final offered =
        context.watch<OnboardingController?>()?.homeCardEligible ?? false;
    return offered ? banner : null;
  }

  Widget? _topCallsStrip(CallsProvider provider) {
    final calls = provider.topCalls;
    if (calls == null || calls.isEmpty) return null;
    // Chosen topics first, otherwise the server's order (a stable sort).
    final topics = context.watch<OnboardingController?>()?.topics ?? const {};
    return TopCallsStrip(
      calls: topCallsForTopics(calls, topics),
      onOpen: (TopCall call) => _openCall(call.call.id),
    );
  }

  void _openCall(String callId) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CallDetailScreen(callId: callId)));
  }

  void _openPerson(String personRef) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CallPersonScreen(personRef: personRef)),
    );
  }

  Future<void> _respond(CallFeedEntry entry, CallResponseKind kind) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final result = await showCallResponseSheet(
      context: context,
      entry: entry,
      initialKind: kind,
    );
    if (mounted && result?.resultingCall != null) {
      _openCall(result!.resultingCall!.call.id);
    }
  }

  Future<void> _shareReceipt(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      entry: entry,
      receipt: CallReceipt.fromEntry(
        entry,
        shareUrl: provider.shareLinkForCall(entry.call.id),
      ),
    );
  }

  Future<void> _compose() async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      requestCallSignIn(context, onRequested: widget.onSignInRequested);
      return;
    }
    final entry = await showMarketPickerSheet(context: context);
    if (entry != null && mounted) _openCall(entry.call.id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Consumer<CallsProvider>(
          builder: (context, provider, _) {
            _loadFor(provider);
            return Column(
              children: [
                if (widget.showHeader)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: ChumbucketAppHeader(
                      title: 'Home',
                      showAccountActions: false,
                      onSearchTap: _openSearch,
                    ),
                  ),
                _ModeBar(provider: provider, onCompose: _compose),
                ..._notices(provider),
                Expanded(child: _content(provider)),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _notices(CallsProvider provider) {
    final notices = <Widget>[];
    // Saved content stays on screen and refreshes on its own; offline is a
    // small pill, never a banner with a retry button or a "last updated".
    if (provider.isOffline && provider.feed.isNotEmpty) {
      notices.add(CallsNotice.offline());
    }
    if (provider.invitations.isNotEmpty) {
      notices.add(
        CallsNotice(
          icon: 'fire-outline',
          color: AppColors.primary,
          message:
              '${provider.invitations.length} open dare'
              '${provider.invitations.length == 1 ? '' : 's'} waiting',
        ),
      );
    }
    return notices;
  }

  Widget _content(CallsProvider provider) {
    switch (provider.feedState) {
      case CallsLoadState.idle:
      case CallsLoadState.loading:
        return const CallsLoadingView();
      case CallsLoadState.offline:
        return CallsOfflineView(onRetry: _refresh);
      case CallsLoadState.error:
        return CallsErrorView(
          message: provider.feedError ?? 'Something went wrong.',
          onRetry: _refresh,
        );
      case CallsLoadState.empty:
        if (provider.feedMode == CallFeedMode.global &&
            widget.onBrowseMarkets != null) {
          final empty = CallsEmptyView(
            title: 'The first call could be yours',
            message:
                'Pick a real market. Put your view on record. '
                'Invite someone to Back or Fade it.',
            actionLabel: 'Explore markets',
            onAction: widget.onBrowseMarkets,
          );
          final banner = _shownBanner();
          if (banner == null) return empty;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: banner,
              ),
              Expanded(child: empty),
            ],
          );
        }
        if (!provider.isSignedIn) {
          return CallsSignedOutView(
            onSignIn:
                () => requestCallSignIn(
                  context,
                  onRequested: widget.onSignInRequested,
                ),
          );
        }
        final strip =
            provider.feedMode == CallFeedMode.following
                ? _topCallsStrip(provider)
                : null;
        final empty = CallsEmptyView(
          artwork:
              provider.feedMode == CallFeedMode.following
                  ? ChumbucketStateArtwork.people
                  : ChumbucketStateArtwork.calls,
          title:
              provider.feedMode == CallFeedMode.following
                  ? 'Nobody you follow has called anything'
                  : 'No calls yet',
          message:
              provider.feedMode == CallFeedMode.following
                  ? 'Follow a few people, or switch to Global to see everyone.'
                  : 'Be the first to go on record. It is free and it takes a tap.',
          actionLabel:
              provider.feedMode == CallFeedMode.following
                  ? 'View Global'
                  : 'Make a call',
          onAction:
              provider.feedMode == CallFeedMode.following
                  ? () => provider.setFeedMode(CallFeedMode.global)
                  : _compose,
        );
        if (strip == null) return empty;
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
            children: [strip, empty],
          ),
        );
      case CallsLoadState.ready:
        // A real resolved call from this session, not an invented unread count.
        final receipts =
            provider.feed
                .where(
                  (entry) =>
                      entry.author.id == provider.viewerUserId &&
                      entry.isShareableReceipt &&
                      entry.call.visibility == CallVisibility.public,
                )
                .toList()
              ..sort((a, b) => b.call.createdAt.compareTo(a.call.createdAt));
        final receipt = receipts.firstOrNull;
        final strip = _topCallsStrip(provider);
        final banner = _shownBanner();
        final headers = <Widget>[
          if (banner != null) banner,
          if (receipt != null)
            _ReceiptNudge(entry: receipt, onTap: () => _shareReceipt(receipt)),
          if (strip != null) strip,
        ];
        final headerCount = headers.length;
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
            itemCount:
                headerCount + provider.feed.length + (provider.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              if (index < headerCount) return headers[index];
              index -= headerCount;
              if (index >= provider.feed.length) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.h),
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }
              final entry = provider.feed[index];
              return CallCard(
                entry: entry,
                onOpenCall: () => _openCall(entry.call.id),
                onOpenPerson: () => _openPerson(entry.author.id),
                onBack:
                    entry.author.id == provider.viewerUserId
                        ? null
                        : () => _respond(entry, CallResponseKind.back),
                onFade:
                    entry.author.id == provider.viewerUserId
                        ? null
                        : () => _respond(entry, CallResponseKind.fade),
                onShareReceipt: () => _shareReceipt(entry),
              );
            },
          ),
        );
    }
  }
}

class _ModeBar extends StatelessWidget {
  final CallsProvider provider;
  final VoidCallback onCompose;

  const _ModeBar({required this.provider, required this.onCompose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 4.h),
      child: Row(
        children: [
          // ChumbucketTabs sizes to its labels; at a large text scale the two
          // labels plus the action can exceed a narrow phone, so the tabs
          // scroll rather than clipping a destination out of reach.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ChumbucketTabs(
                labels: const [
                  CallFeedMode.following,
                  CallFeedMode.global,
                ].map((m) => m.label).toList(growable: false),
                selectedIndex:
                    provider.feedMode == CallFeedMode.following ? 0 : 1,
                onSelected:
                    (index) => provider.setFeedMode(
                      index == 0 ? CallFeedMode.following : CallFeedMode.global,
                    ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Make a call',
            child: InkWell(
              onTap: onCompose,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BasilIcon(
                      'add-outline',
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                    SizedBox(width: 5.w),
                    Text(
                      'Call',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptNudge extends StatelessWidget {
  final CallFeedEntry entry;
  final VoidCallback onTap;
  const _ReceiptNudge({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const BasilIcon(
                'award-outline',
                size: 22,
                color: Color(0xFFB8173B),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your receipt',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.outcome.label} · ${entry.market.question}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (entry.market.venue.isDemo)
                      const Text(
                        'DEMO DATA',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const BasilIcon(
                'arrow-right-outline',
                size: 20,
                color: AppColors.textPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
