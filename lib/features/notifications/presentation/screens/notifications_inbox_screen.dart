/// The inbox: what came back.
///
/// This is the return half of the free loop. Everything in it is relational —
/// somebody backed your call, somebody faded it, the venue settled it, somebody
/// wants a rematch. There is deliberately no price alert, no "N people are on
/// this market", no streak nag and no amount, because none of those is a person
/// answering you and all of them are the urgency copy the pivot refuses.
///
/// Reused verbatim rather than rebuilt: [ChumbucketTabs] for the All/Unread
/// filter (same component the feed uses for Global/Following) and the
/// `CallsStateView` family — `CallsLoadingView`, `CallsEmptyView`,
/// `CallsErrorView`, `CallsOfflineView`, `CallsSignedOutView`, `CallsNotice` —
/// so every reachable state looks and reads like the rest of the slice.
///
/// `ChumbucketAppHeader` is **not** used here even though it already badges an
/// unread count: it depends on `MwaAuthProvider`, `MwaWalletProvider` and
/// `ProfileProvider`, and this surface has to work with no wallet at all. A
/// plain `AppBar` keeps that promise. The patch that teaches the shared header
/// about this inbox is filed in
/// `docs/contracts/integration-requests/packet-g.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';
import 'package:chumbucket/features/notifications/presentation/notification_target_router.dart';
import 'package:chumbucket/features/notifications/presentation/widgets/notification_row.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_tabs.dart';

class NotificationsInboxScreen extends StatefulWidget {
  /// Invoked when a signed-out person lands here. The shell owns what "sign
  /// in" means — this slice never does it itself, and never asks for a wallet.
  final VoidCallback? onSignInRequested;

  /// How a tapped row is opened. Defaults to [openNotificationTarget], which
  /// needs a `CallsProvider` in the tree; tests and embedded previews pass
  /// their own.
  final NotificationTargetOpener? openTarget;

  const NotificationsInboxScreen({
    super.key,
    this.onSignInRequested,
    this.openTarget,
  });

  @override
  State<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState extends State<NotificationsInboxScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsProvider>().load();
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
    if (position.pixels > position.maxScrollExtent - 280) {
      context.read<NotificationsProvider>().loadMore();
    }
  }

  Future<void> _refresh() =>
      context.read<NotificationsProvider>().load(force: true);

  Future<void> _open(CallNotification notification) async {
    final provider = context.read<NotificationsProvider>();
    final opener = widget.openTarget ?? openNotificationTarget;
    // Read state first: opening is the acknowledgement.
    await provider.markRead(notification.id);
    if (!mounted) return;
    await opener(context, notification.target);
  }

  Future<void> _openActor(CallNotification notification) async {
    final target = notification.actorTarget;
    if (target == null) return;
    final opener = widget.openTarget ?? openNotificationTarget;
    await opener(context, target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text(
          'Inbox',
          style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700),
        ),
        actions: [
          Consumer<NotificationsProvider>(
            builder: (context, provider, _) {
              if (provider.unreadCount == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed:
                    provider.isMarkingRead ? null : provider.markAllRead,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
                child:
                    provider.isMarkingRead
                        ? SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                        : Text(
                          'Mark all read',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationsProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              _FilterBar(provider: provider),
              ..._notices(provider),
              Expanded(child: _content(provider)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _notices(NotificationsProvider provider) {
    final notices = <Widget>[];
    // Offline with rows underneath: say they are cached rather than passing
    // them off as live.
    if (provider.isOffline && provider.notifications.isNotEmpty) {
      notices.add(CallsNotice.offline(onRetry: _refresh));
    } else if (provider.isStale && provider.notifications.isNotEmpty) {
      final servedAt = provider.servedAtUtc;
      notices.add(
        CallsNotice.stale(
          message:
              'Last updated '
              '${servedAt == null ? 'a while ago' : CallsFormat.relative(servedAt)}.',
          onRefresh: _refresh,
        ),
      );
    }
    return notices;
  }

  Widget _content(NotificationsProvider provider) {
    switch (provider.state) {
      case NotificationsLoadState.idle:
      case NotificationsLoadState.loading:
        return const CallsLoadingView(rows: 4);

      case NotificationsLoadState.signedOut:
        return CallsSignedOutView(
          message:
              'Sign in to see who backed you, who faded you, and when the '
              'venue settles your calls. No wallet needed.',
          onSignIn: widget.onSignInRequested,
        );

      case NotificationsLoadState.offline:
        return CallsOfflineView(onRetry: _refresh);

      case NotificationsLoadState.error:
        return CallsErrorView(
          message: provider.error ?? 'Something went wrong.',
          onRetry: _refresh,
        );

      case NotificationsLoadState.empty:
        return CallsEmptyView(
          artwork: ChumbucketStateArtwork.inbox,
          title:
              provider.filter == NotificationFilter.unread
                  ? 'Nothing unread'
                  : 'Nothing has come back yet',
          message:
              provider.filter == NotificationFilter.unread
                  ? 'You have read everything here. Switch to All to look back.'
                  : 'When somebody backs or fades one of your calls, when the '
                      'venue settles one, or when somebody wants a rematch, '
                      'it lands here.',
          actionLabel:
              provider.filter == NotificationFilter.unread ? 'Show all' : null,
          onAction:
              provider.filter == NotificationFilter.unread
                  ? () => provider.setFilter(NotificationFilter.all)
                  : null,
        );

      case NotificationsLoadState.ready:
        return RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView.separated(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 28.h),
            itemCount:
                provider.notifications.length + (provider.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (context, index) {
              if (index >= provider.notifications.length) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.h),
                  child: const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }
              final notification = provider.notifications[index];
              return NotificationRow(
                notification: notification,
                onTap: () => _open(notification),
                onOpenActor:
                    notification.actorTarget == null
                        ? null
                        : () => _openActor(notification),
              );
            },
          ),
        );
    }
  }
}

class _FilterBar extends StatelessWidget {
  final NotificationsProvider provider;

  const _FilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 4.h),
      child: Row(
        children: [
          // ChumbucketTabs sizes to its labels; at a large text scale two
          // labels plus the count can exceed a narrow phone, so the tabs
          // scroll rather than clipping a destination out of reach.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ChumbucketTabs(
                labels:
                    NotificationFilter.values
                        .map((f) => f.label)
                        .toList(growable: false),
                selectedIndex: NotificationFilter.values.indexOf(
                  provider.filter,
                ),
                onSelected:
                    (index) =>
                        provider.setFilter(NotificationFilter.values[index]),
              ),
            ),
          ),
          if (provider.unreadCount > 0)
            Padding(
              padding: EdgeInsets.only(right: 4.w),
              child: Text(
                '${provider.unreadCount} unread',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
