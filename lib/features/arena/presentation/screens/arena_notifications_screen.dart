import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';

class ArenaNotificationsScreen extends StatefulWidget {
  const ArenaNotificationsScreen({super.key});

  @override
  State<ArenaNotificationsScreen> createState() =>
      _ArenaNotificationsScreenState();
}

class _ArenaNotificationsScreenState extends State<ArenaNotificationsScreen> {
  bool _isMarkingRead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final wallet = context.read<MwaAuthProvider>().walletAddress;
    if (wallet != null) {
      await context.read<ArenaProvider>().loadNotifications(
        walletAddress: wallet,
      );
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _isMarkingRead = true);
    try {
      await context.read<ArenaProvider>().markNotificationsRead(
        authProvider: context.read<MwaAuthProvider>(),
      );
    } catch (error) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Could not mark notifications read',
        subtitle: error.toString(),
      );
    } finally {
      if (mounted) setState(() => _isMarkingRead = false);
    }
  }

  void _open(ArenaNotification notification) {
    if (notification.type == 'CLAIM_AVAILABLE') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MyPotsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Consumer<ArenaProvider>(
          builder: (context, arena, _) {
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(12.w, 8.h, 20.w, 12.h),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const PhosphorIcon(
                              PhosphorIconsRegular.caretLeft,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Inbox',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 24.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (arena.unreadNotificationCount > 0)
                            TextButton(
                              onPressed: _isMarkingRead ? null : _markAllRead,
                              child:
                                  _isMarkingRead
                                      ? SizedBox(
                                        width: 16.w,
                                        height: 16.w,
                                        child: const CircularProgressIndicator(
                                          color: AppColors.primary,
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Text('Mark all read'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (arena.isLoadingNotifications &&
                      arena.notifications.isEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      sliver: SliverList.separated(
                        itemCount: 4,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (_, __) => const _NotificationSkeleton(),
                      ),
                    )
                  else if (arena.notificationsError != null &&
                      arena.notifications.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _InboxState(
                        icon: Icons.cloud_off_outlined,
                        title: 'Could not load your inbox',
                        action: _load,
                      ),
                    )
                  else if (arena.notifications.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _InboxState(
                        icon: PhosphorIconsRegular.bell,
                        title: 'You are all caught up',
                        detail:
                            'Followed calls and claim-ready winnings will appear here.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                      sliver: SliverList.separated(
                        itemCount: arena.notifications.length,
                        separatorBuilder: (_, __) => SizedBox(height: 10.h),
                        itemBuilder: (context, index) {
                          final notification = arena.notifications[index];
                          return _NotificationRow(
                            notification: notification,
                            onTap: () => _open(notification),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  final ArenaNotification notification;
  final VoidCallback onTap;

  const _NotificationRow({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final claim = notification.type == 'CLAIM_AVAILABLE';
    final tone = claim ? AppColors.success : AppColors.primary;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: PhosphorIcon(
                  claim
                      ? PhosphorIconsFill.checkCircle
                      : PhosphorIconsRegular.broadcast,
                  color: tone,
                  size: 21.w,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14.sp,
                              fontWeight:
                                  notification.isUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                            ),
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
                          ),
                      ],
                    ),
                    if (notification.body.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(
                        notification.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                          height: 1.35,
                        ),
                      ),
                    ],
                    SizedBox(height: 6.h),
                    Text(
                      DateFormat(
                        'MMM d, h:mm a',
                      ).format(notification.createdAt.toLocal()),
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? action;

  const _InboxState({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PhosphorIcon(icon, size: 40.w, color: AppColors.textTertiary),
            SizedBox(height: 12.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
            ),
            if (detail != null) ...[
              SizedBox(height: 6.h),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.sp,
                  height: 1.4,
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: 8.h),
              TextButton(onPressed: action, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationSkeleton extends StatelessWidget {
  const _NotificationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92.h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
    );
  }
}
