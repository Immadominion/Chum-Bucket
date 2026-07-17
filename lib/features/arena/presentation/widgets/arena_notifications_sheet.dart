import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/wave_clipper.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class ArenaNotificationsSheet extends StatefulWidget {
  final VoidCallback onOpenClaimable;

  const ArenaNotificationsSheet({super.key, required this.onOpenClaimable});

  @override
  State<ArenaNotificationsSheet> createState() =>
      _ArenaNotificationsSheetState();
}

class _ArenaNotificationsSheetState extends State<ArenaNotificationsSheet> {
  bool _isMarkingRead = false;

  Future<void> _markAllRead() async {
    setState(() => _isMarkingRead = true);
    try {
      await context.read<ArenaProvider>().markNotificationsRead(
        authProvider: context.read<MwaAuthProvider>(),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not mark notifications read',
        subtitle: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _isMarkingRead = false);
    }
  }

  Future<void> _retry() async {
    final wallet = context.read<MwaAuthProvider>().walletAddress;
    if (wallet != null) {
      await context.read<ArenaProvider>().loadNotifications(
        walletAddress: wallet,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ArenaProvider>(
      builder: (context, arena, _) {
        final notifications = arena.notifications;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _InboxHeader(
                  unreadCount: arena.unreadNotificationCount,
                  isMarkingRead: _isMarkingRead,
                  onClose: () => Navigator.of(context).pop(),
                  onMarkAllRead: _markAllRead,
                ),
                Expanded(
                  child: _InboxBody(
                    notifications: notifications,
                    isLoading: arena.isLoadingNotifications,
                    error: arena.notificationsError,
                    onRetry: _retry,
                    onOpenClaimable: widget.onOpenClaimable,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InboxHeader extends StatelessWidget {
  final int unreadCount;
  final bool isMarkingRead;
  final VoidCallback onClose;
  final VoidCallback onMarkAllRead;

  const _InboxHeader({
    required this.unreadCount,
    required this.isMarkingRead,
    required this.onClose,
    required this.onMarkAllRead,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 142.h,
      child: Stack(
        children: [
          ClipPath(
            clipper: DetailedWaveClipper(),
            child: Container(
              height: 132.h,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 12.w, 0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Inbox',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close notifications',
                      onPressed: onClose,
                      icon: const BasilIcon('cross-outline', color: Colors.white),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      unreadCount == 0
                          ? 'You are all caught up.'
                          : '$unreadCount unread ${unreadCount == 1 ? 'update' : 'updates'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (unreadCount > 0)
                      TextButton(
                        onPressed: isMarkingRead ? null : onMarkAllRead,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 10.w),
                        ),
                        child:
                            isMarkingRead
                                ? SizedBox(
                                  width: 16.w,
                                  height: 16.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Text('Mark all read'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxBody extends StatelessWidget {
  final List<ArenaNotification> notifications;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenClaimable;

  const _InboxBody({
    required this.notifications,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.onOpenClaimable,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && notifications.isEmpty) {
      return ListView.separated(
        padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
        itemCount: 4,
        separatorBuilder: (_, __) => SizedBox(height: 10.h),
        itemBuilder:
            (_, __) => Container(
              height: 78.h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
              ),
            ),
      );
    }
    if (error != null && notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BasilIcon(
                'cloud-off-outline',
                size: 36.sp,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 10.h),
              Text(
                'Could not load notifications',
                style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6.h),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (notifications.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(28.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BasilIcon(
                'notification-outline',
                size: 40.sp,
                color: AppColors.textSecondary,
              ),
              SizedBox(height: 10.h),
              Text(
                'Nothing new right now',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4.h),
              Text(
                'Calls from people you follow and claimable winnings will land here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.sp,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
      itemCount: notifications.length,
      separatorBuilder: (_, __) => SizedBox(height: 10.h),
      itemBuilder:
          (context, index) => _NotificationRow(
            notification: notifications[index],
            onTap:
                notifications[index].type == 'CLAIM_AVAILABLE'
                    ? onOpenClaimable
                    : null,
          ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final ArenaNotification notification;
  final VoidCallback? onTap;

  const _NotificationRow({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isClaim = notification.type == 'CLAIM_AVAILABLE';
    final tone = isClaim ? AppColors.success : AppColors.primary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(13.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color:
                  notification.isUnread
                      ? tone.withValues(alpha: 0.2)
                      : AppColors.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: BasilIcon(
                  isClaim ? 'wallet-outline' : 'stack-outline',
                  size: 20.sp,
                  color: tone,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 5.h),
                    Text(
                      DateFormat(
                        'MMM d, h:mm a',
                      ).format(notification.createdAt.toLocal()),
                      style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (notification.isUnread)
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: tone,
                    shape: BoxShape.circle,
                  ),
                )
              else if (onTap != null)
                BasilIcon(
                  'caret-right-outline',
                  size: 20.sp,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
