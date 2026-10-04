/// One inbox row.
///
/// Compact: who (avatar with the kind's glyph), what (title, one line of
/// body), when (a short age) and an unread dot. The kind is carried by the
/// glyph and read out to screen readers rather than printed as an eyebrow.
///
/// Reused rather than rebuilt: `AppAvatar` for the actor, `CallOutcomeBadge` so
/// a settled result is labelled here exactly as it is on a call card, and
/// `CallsFormat.relative` so a timestamp is worded the same everywhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class NotificationRow extends StatelessWidget {
  final CallNotification notification;

  /// Opens whatever the notification refers to.
  final VoidCallback onTap;

  /// Opens the actor's person page. Null when the venue, not a person,
  /// produced the row.
  final VoidCallback? onOpenActor;

  /// True while the tapped target is being fetched (a receipt re-reads its
  /// call first). Shows progress in place of the time and ignores taps.
  final bool opening;

  /// Drawn inside a grouped list (Activity): no card of its own, the group
  /// supplies the white surface and the dividers.
  final bool grouped;

  const NotificationRow({
    super.key,
    required this.notification,
    required this.onTap,
    this.onOpenActor,
    this.opening = false,
    this.grouped = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(notification);
    final unread = notification.isUnread;
    final radius = BorderRadius.circular(grouped ? 0 : 18.r);
    // At large text a side column for the age would squeeze the title to a
    // word per line, so the age moves under the body and the title gets the
    // row's full width.
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    final age = Text(
      _ago(notification.createdAtUtc),
      style: const TextStyle(
        color: AppColors.textTertiary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );

    return Semantics(
      button: true,
      label:
          '${opening ? 'Opening. ' : ''}${unread ? 'Unread. ' : ''}'
          '${notification.kind.label}. '
          '${notification.title}. '
          '${notification.body} ${CallsFormat.relative(notification.createdAtUtc)}.',
      child: Material(
        color: grouped ? Colors.transparent : Colors.white,
        borderRadius: radius,
        child: InkWell(
          onTap: opening ? null : onTap,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              // Unread is carried by the tint, the weight of the title and an
              // explicit dot — never by colour alone.
              color: unread ? AppColors.primary.withValues(alpha: 0.05) : null,
              borderRadius: radius,
            ),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Leading(
                  notification: notification,
                  tone: tone,
                  onOpenActor: onOpenActor,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        // Large text gets a third line rather than losing
                        // the end of "backed your call".
                        maxLines: large ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight:
                              unread ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        notification.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      if (large && !opening) ...[
                        SizedBox(height: 2.h),
                        age,
                      ],
                      if (notification.outcome != null) ...[
                        SizedBox(height: 6.h),
                        CallOutcomeBadge(outcome: notification.outcome!),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (opening)
                      SizedBox(
                        key: const ValueKey('notification-opening'),
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: tone,
                        ),
                      )
                    else if (!large)
                      age,
                    if (unread && !opening) ...[
                      if (!large) SizedBox(height: 6.h),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "now", "12m", "3h", "5d", then "27 Sep" (with the year once it is not
/// this year): a row's age at a glance, short enough for 2x text.
String _ago(DateTime at, {DateTime? now}) {
  final reference = (now ?? DateTime.now()).toUtc();
  final delta = reference.difference(at.toUtc());
  if (delta.inMinutes < 1) return 'now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m';
  if (delta.inHours < 24) return '${delta.inHours}h';
  if (delta.inDays < 7) return '${delta.inDays}d';
  final local = at.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = '${local.day} ${months[local.month - 1]}';
  return local.year == reference.toLocal().year ? day : '$day ${local.year}';
}

class _Leading extends StatelessWidget {
  final CallNotification notification;
  final Color tone;
  final VoidCallback? onOpenActor;

  const _Leading({
    required this.notification,
    required this.tone,
    required this.onOpenActor,
  });

  @override
  Widget build(BuildContext context) {
    final actor = notification.actor;

    // No actor means the venue published this, and the venue is not a person.
    // A glyph, never a fake avatar.
    if (actor == null) {
      return Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: BasilIcon(_iconFor(notification), size: 19.w, color: tone),
        ),
      );
    }

    return Semantics(
      button: onOpenActor != null,
      label: 'Open ${actor.displayName}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppAvatar(
            initials: actor.initials,
            imageUrl: actor.avatarUrl,
            size: 40,
            onTap: onOpenActor,
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: EdgeInsets.all(3.w),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: BasilIcon(_iconFor(notification), size: 12.w, color: tone),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tone per kind. A resolution takes the tone of its outcome, so a miss is
/// never dressed up as a win and a void is neither.
Color _toneFor(CallNotification notification) => switch (notification.kind) {
  CallNotificationKind.backed => AppColors.success,
  CallNotificationKind.faded => AppColors.tertiary,
  CallNotificationKind.rematch => AppColors.primary,
  CallNotificationKind.resolved => switch (notification.outcome) {
    CallOutcome.correct => AppColors.success,
    CallOutcome.incorrect => AppColors.error,
    CallOutcome.voided => AppColors.textTertiary,
    _ => AppColors.textSecondary,
  },
};

String _iconFor(CallNotification notification) => switch (notification.kind) {
  CallNotificationKind.backed => 'arrow-up-outline',
  CallNotificationKind.faded => 'exchange-outline',
  CallNotificationKind.rematch => 'fire-outline',
  CallNotificationKind.resolved => switch (notification.outcome) {
    CallOutcome.correct => 'check-outline',
    CallOutcome.incorrect => 'cross-outline',
    CallOutcome.voided => 'info-circle-outline',
    _ => 'stack-outline',
  },
};
