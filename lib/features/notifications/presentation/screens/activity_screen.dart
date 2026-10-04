/// What the bell opens: the calls inbox (`inbox.*` on the calls BFF) — who
/// backed or faded your call, when the venue settled one, who dared you to go
/// on record.
///
/// Laid out as "New" (unread) and "Earlier" (read), compact rows grouped on
/// one surface. It opens on the inbox as last seen (saved on this phone) and
/// refreshes silently: on open, on pull, on resume. A failed refresh keeps the
/// rows with no banner; with nothing to show, a full-screen state with the
/// brand art says so in one line.
///
/// The wallet-keyed notices from the original challenge and Arena system now
/// live in Settings → History (`LegacyHistoryScreen`), read-only, and are not
/// counted on the bell.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/presentation/notification_target_router.dart';
import 'package:chumbucket/features/notifications/presentation/widgets/notification_row.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class ActivityScreen extends StatefulWidget {
  /// How a tapped calls row is opened. Defaults to [openNotificationTarget].
  final NotificationTargetOpener? openTarget;

  const ActivityScreen({super.key, this.openTarget});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Older rows load as you reach them — no "Show more" button.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 240) {
      context.read<NotificationsProvider>().loadMore();
    }
  }

  Future<void> _refresh() =>
      context.read<NotificationsProvider>().load(force: true);

  /// The row whose target is being fetched, so it can show progress.
  String? _openingId;

  Future<void> _open(CallNotification notification) async {
    if (_openingId != null) return;
    final opener = widget.openTarget ?? openNotificationTarget;
    setState(() => _openingId = notification.id);
    try {
      // Opening is the acknowledgement.
      await context.read<NotificationsProvider>().markRead(notification.id);
      if (!mounted) return;
      await opener(context, notification.target);
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _openActor(CallNotification notification) async {
    final target = notification.actorTarget;
    if (target == null) return;
    await (widget.openTarget ?? openNotificationTarget)(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<NotificationsProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        leading: IconButton(
          tooltip: 'Back',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const BasilIcon(
            'arrow-left-outline',
            color: AppColors.textPrimary,
          ),
        ),
        title: Text(
          'Activity',
          style: AppTextStyles.questionTitle.copyWith(
            fontSize: 20,
            letterSpacing: 0,
          ),
        ),
        actions: [
          if (calls.unreadCount > 0 &&
              calls.state == NotificationsLoadState.ready)
            IconButton(
              key: const ValueKey('activity-mark-all-read'),
              tooltip: 'Mark all read',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: calls.isMarkingRead ? null : calls.markAllRead,
              icon: const BasilIcon(
                'checked-box-outline',
                color: AppColors.textPrimary,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: _body(calls),
      ),
    );
  }

  Widget _body(NotificationsProvider calls) {
    switch (calls.state) {
      case NotificationsLoadState.idle:
      case NotificationsLoadState.loading:
        return const CallsLoadingView(rows: 4);
      case NotificationsLoadState.signedOut:
        return ChumbucketStateFill(
          child: ChumbucketStateView(
            artwork: ChumbucketStateArtwork.inbox,
            message: 'Sign in to see who backs your calls',
            actionLabel: 'Sign in',
            actionIcon: 'login-outline',
            onAction: () => requestCallSignIn(context),
          ),
        );
      case NotificationsLoadState.offline:
        return ChumbucketStateFill(
          child: ChumbucketStateView(
            artwork: ChumbucketStateArtwork.offline,
            message: 'You’re offline',
            actionLabel: 'Try again',
            onAction: _refresh,
          ),
        );
      case NotificationsLoadState.error:
        return ChumbucketStateFill(
          child: ChumbucketStateView(
            artwork: ChumbucketStateArtwork.error,
            message: 'Couldn’t load your activity',
            semanticsHint: calls.error,
            actionLabel: 'Try again',
            onAction: _refresh,
          ),
        );
      case NotificationsLoadState.empty:
        return const ChumbucketStateFill(
          child: ChumbucketStateView(
            artwork: ChumbucketStateArtwork.inbox,
            message: 'No activity yet',
            semanticsHint:
                'Backs, fades, results and dares on your calls land here.',
          ),
        );
      case NotificationsLoadState.ready:
        final fresh = [
          for (final n in calls.notifications)
            if (n.isUnread) n,
        ];
        final earlier = [
          for (final n in calls.notifications)
            if (!n.isUnread) n,
        ];
        return ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (calls.isOffline)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ChumbucketOfflinePill(),
                ),
              ),
            if (fresh.isNotEmpty) ...[
              const _SectionLabel('New'),
              _Group(children: [for (final n in fresh) _row(n)]),
            ],
            if (earlier.isNotEmpty) ...[
              if (fresh.isNotEmpty) const SizedBox(height: 20),
              const _SectionLabel('Earlier'),
              _Group(children: [for (final n in earlier) _row(n)]),
            ],
            if (calls.isLoadingMore)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
          ],
        );
    }
  }

  Widget _row(CallNotification notification) => NotificationRow(
    key: ValueKey('activity-${notification.id}'),
    notification: notification,
    grouped: true,
    opening: _openingId == notification.id,
    onTap: () => _open(notification),
    onOpenActor:
        notification.actorTarget == null
            ? null
            : () => _openActor(notification),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'PPNeueMachina',
          color: AppColors.textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: .2,
        ),
      ),
    ),
  );
}

/// Rows on one white surface with hairline dividers: denser than a card each.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            const Divider(
              height: 1,
              thickness: 1,
              indent: 66,
              color: AppColors.outlineVariant,
            ),
          children[i],
        ],
      ],
    ),
  );
}
