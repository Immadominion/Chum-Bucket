/// One inbox row.
///
/// Renders generically off `title` / `body` / `createdAt` / `isUnread` and
/// branches on `kind` — the same shape `arena_notifications_sheet.dart` already
/// uses, so the two inboxes read as one app.
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

  const NotificationRow({
    super.key,
    required this.notification,
    required this.onTap,
    this.onOpenActor,
    this.opening = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(notification);
    final unread = notification.isUnread;

    return Semantics(
      button: true,
      label:
          '${opening ? 'Opening. ' : ''}${unread ? 'Unread. ' : ''}'
          '${notification.title}. '
          '${notification.body} ${CallsFormat.relative(notification.createdAtUtc)}.',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        child: InkWell(
          onTap: opening ? null : onTap,
          borderRadius: BorderRadius.circular(18.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              // Unread is carried by the border tint, the weight of the title
              // and an explicit dot — never by colour alone.
              color: unread ? tone.withValues(alpha: 0.04) : Colors.transparent,
              borderRadius: BorderRadius.circular(18.r),
              border: Border.all(
                color:
                    unread
                        ? tone.withValues(alpha: 0.30)
                        : AppColors.outlineVariant,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Leading(
                  notification: notification,
                  tone: tone,
                  onOpenActor: onOpenActor,
                ),
                SizedBox(width: 11.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              notification.kind.label.toUpperCase(),
                              style: TextStyle(
                                color: tone,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          if (opening)
                            SizedBox(
                              key: const ValueKey('notification-opening'),
                              width: 12.w,
                              height: 12.w,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: tone,
                              ),
                            )
                          else
                            Text(
                              CallsFormat.relative(notification.createdAtUtc),
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (unread && !opening) ...[
                            SizedBox(width: 6.w),
                            Container(
                              width: 8.w,
                              height: 8.w,
                              decoration: BoxDecoration(
                                color: tone,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        notification.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.sp,
                          height: 1.25,
                          fontWeight:
                              unread ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        notification.body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                          height: 1.35,
                        ),
                      ),
                      if (notification.outcome != null) ...[
                        SizedBox(height: 8.h),
                        CallOutcomeBadge(outcome: notification.outcome!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
