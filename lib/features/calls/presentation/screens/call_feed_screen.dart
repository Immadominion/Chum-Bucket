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
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_picker_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
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

  const CallFeedScreen({
    super.key,
    this.showHeader = true,
    this.onSignInRequested,
  });

  @override
  State<CallFeedScreen> createState() => _CallFeedScreenState();
}

class _CallFeedScreenState extends State<CallFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CallsProvider>();
      provider.loadFeed();
      provider.loadInvitations();
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

  Future<void> _refresh() => context.read<CallsProvider>().loadFeed(force: true);

  void _openMarket(String marketId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MarketDetailScreen(marketId: marketId)),
    );
  }

  void _openPerson(String personRef) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CallPersonScreen(personRef: personRef)),
    );
  }

  Future<void> _respond(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      widget.onSignInRequested?.call();
      return;
    }
    await showCallResponseSheet(context: context, entry: entry);
  }

  Future<void> _shareReceipt(CallFeedEntry entry) async {
    final provider = context.read<CallsProvider>();
    await showCallReceiptSheet(
      context: context,
      receipt: CallReceipt.fromEntry(
        entry,
        shareUrl: provider.shareLinkForCall(entry.call.id),
      ),
    );
  }

  Future<void> _compose() async {
    final provider = context.read<CallsProvider>();
    if (!provider.isSignedIn) {
      widget.onSignInRequested?.call();
      return;
    }
    await showMarketPickerSheet(context: context);
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
            return Column(
              children: [
                if (widget.showHeader)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: const ChumbucketAppHeader(title: 'Calls'),
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
    // Offline, but there is cached content underneath — say so rather than
    // presenting it as live.
    if (provider.isOffline && provider.feed.isNotEmpty) {
      notices.add(CallsNotice.offline(onRetry: _refresh));
    } else if (provider.isFeedStale && provider.feed.isNotEmpty) {
      final age = provider.feedAge;
      notices.add(
        CallsNotice.stale(
          message:
              'Last updated ${age == null ? 'a while ago' : CallsFormat.relative(provider.feedServedAtUtc!)}.',
          onRefresh: _refresh,
        ),
      );
    }
    if (provider.invitations.isNotEmpty) {
      notices.add(
        CallsNotice(
          icon: 'fire-outline',
          color: AppColors.primary,
          message:
              '${provider.invitations.length} open challenge'
              '${provider.invitations.length == 1 ? '' : 's'} waiting. '
              'No money involved — just go on record.',
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
        if (!provider.isSignedIn) {
          return CallsSignedOutView(onSignIn: widget.onSignInRequested);
        }
        return CallsEmptyView(
          title:
              provider.feedMode == CallFeedMode.following
                  ? 'Nobody you follow has called anything'
                  : 'No calls yet',
          message:
              provider.feedMode == CallFeedMode.following
                  ? 'Follow a few people, or switch to Global to see everyone.'
                  : 'Be the first to go on record. It is free and it takes a tap.',
          actionLabel: 'Make a call',
          onAction: _compose,
        );
      case CallsLoadState.ready:
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 110.h),
            itemCount: provider.feed.length + (provider.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
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
                onOpenMarket: () => _openMarket(entry.market.id),
                onOpenPerson: () => _openPerson(entry.author.id),
                onRespond:
                    entry.author.id == provider.viewerUserId
                        ? null
                        : () => _respond(entry),
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
                labels:
                    CallFeedMode.values
                        .map((m) => m.label)
                        .toList(growable: false),
                selectedIndex: CallFeedMode.values.indexOf(provider.feedMode),
                onSelected:
                    (index) => provider.setFeedMode(CallFeedMode.values[index]),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Make a call',
            child: InkWell(
              onTap: onCompose,
              borderRadius: BorderRadius.circular(999.r),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(999.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BasilIcon('add-outline', size: 15.w, color: Colors.white),
                    SizedBox(width: 5.w),
                    Text(
                      'Call it',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.sp,
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
