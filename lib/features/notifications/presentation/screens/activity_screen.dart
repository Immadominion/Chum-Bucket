/// What the bell opens: the calls inbox (`inbox.*` on the calls BFF) — who
/// backed or faded your call, when the venue settled one, who dared you to go
/// on record. Session-scoped; with no session it says so in one row and
/// offers to connect, rather than blocking the screen.
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
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
            fontSize: 17,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _SectionHeader(
              title: 'Your calls',
              action:
                  calls.unreadCount > 0
                      ? TextButton(
                        onPressed:
                            calls.isMarkingRead ? null : calls.markAllRead,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: _pinkInk,
                        ),
                        child: const Text('Mark all read'),
                      )
                      : null,
            ),
            ..._callsSection(calls),
          ],
        ),
      ),
    );
  }

  List<Widget> _callsSection(NotificationsProvider calls) {
    switch (calls.state) {
      case NotificationsLoadState.idle:
      case NotificationsLoadState.loading:
        return const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
        ];
      case NotificationsLoadState.signedOut:
        return [
          _Row(
            icon: 'user-outline',
            text:
                'Sign in to see who backed or faded your calls and when they '
                'settle. Your wallet, Google or X.',
            actionLabel: 'Sign in',
            onAction: () => requestCallSignIn(context),
          ),
        ];
      case NotificationsLoadState.offline:
        return [
          _Row(
            icon: 'cloud-off-outline',
            text: 'You’re offline.',
            actionLabel: 'Retry',
            onAction: _refresh,
          ),
        ];
      case NotificationsLoadState.error:
        return [
          _Row(
            icon: 'info-circle-outline',
            text: calls.error ?? 'Something went wrong.',
            actionLabel: 'Retry',
            onAction: _refresh,
          ),
        ];
      case NotificationsLoadState.empty:
        return [
          _Row(
            icon: 'notification-outline',
            text:
                'Nothing has come back yet. When someone backs or fades one '
                'of your calls, or the venue settles one, it lands here.',
          ),
        ];
      case NotificationsLoadState.ready:
        return [
          for (final notification in calls.notifications) ...[
            NotificationRow(
              notification: notification,
              opening: _openingId == notification.id,
              onTap: () => _open(notification),
              onOpenActor:
                  notification.actorTarget == null
                      ? null
                      : () => _openActor(notification),
            ),
            const SizedBox(height: 10),
          ],
          if (calls.hasMore)
            Center(
              child: TextButton(
                onPressed: calls.isLoadingMore ? null : calls.loadMore,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: _pinkInk,
                ),
                child: Text(calls.isLoadingMore ? 'Loading…' : 'Show more'),
              ),
            ),
        ];
    }
  }
}

const _pinkInk = Color(0xFFB8173B);
const _muted = Color(0xFF606775);
final _meta = AppTextStyles.textTheme.bodySmall!.copyWith(
  color: _muted,
  height: 1.5,
);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 48),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: AppTextStyles.questionTitle.copyWith(
                fontSize: 17,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

/// A one-row state inside a section: the screen stays usable around it.
class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });
  final String icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        BasilIcon(icon, size: 20, color: AppColors.textPrimary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: _meta)),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              foregroundColor: _pinkInk,
            ),
            child: Text(actionLabel!),
          ),
      ],
    ),
  );
}
