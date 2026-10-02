import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/notifications/presentation/screens/activity_screen.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Shared top header for the main tabs (Home, Calls, Friends) — profile
/// avatar, optional screen title, notification bell, wallet quick-copy.
/// One component so the tabs read as the same app instead of each
/// inventing its own header treatment.
class ChumbucketAppHeader extends StatelessWidget {
  /// Screen context text (e.g. "Calls"). Home passes null to keep its
  /// personal, dashboard feel instead of restating the obvious.
  final String? title;
  final VoidCallback? onProfileTap;
  final bool showAccountActions;
  final VoidCallback? onActivityTap;

  const ChumbucketAppHeader({
    super.key,
    this.title,
    this.onProfileTap,
    this.showAccountActions = true,
    this.onActivityTap,
  });

  @override
  Widget build(BuildContext context) {
    return _InboxResumeRefresh(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Row(
          children: [
            if (showAccountActions) _ProfileAvatar(onTap: onProfileTap),
            if (title != null) ...[
              if (showAccountActions) SizedBox(width: 12.w),
              Expanded(child: Text(title!, style: AppTextStyles.pageTitle)),
            ] else
              const Spacer(),
            if (showAccountActions) ...[
              const _WalletButton(),
              SizedBox(width: 6.w),
            ],
            if (onActivityTap != null)
              IconButton(
                tooltip: 'Activity',
                onPressed: onActivityTap,
                icon: const BasilIcon('notification-outline', size: 22),
              )
            else
              const _NotificationBell(),
          ],
        ),
      ),
    );
  }
}

/// Keeps the unread badge honest: refreshed when the app comes back to the
/// foreground and when a call notification arrives while it is open, not only
/// when the header first builds (prod readiness M3). Also makes sure this
/// device is registered for the signed-in account's pushes when the person
/// has already allowed notifications — it never prompts.
class _InboxResumeRefresh extends StatefulWidget {
  const _InboxResumeRefresh({required this.child});
  final Widget child;

  @override
  State<_InboxResumeRefresh> createState() => _InboxResumeRefreshState();
}

class _InboxResumeRefreshState extends State<_InboxResumeRefresh>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FcmTokenService.onCallNotification = _refreshBadge;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushRegistration.syncIfPermitted(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (FcmTokenService.onCallNotification == _refreshBadge) {
      FcmTokenService.onCallNotification = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _refreshBadge();
    PushRegistration.syncIfPermitted(context);
  }

  void _refreshBadge() {
    if (!mounted) return;
    final wallet = context.read<MwaAuthProvider?>()?.walletAddress;
    final arena = context.read<ArenaProvider?>();
    if (wallet != null && arena != null) {
      arena.loadNotifications(walletAddress: wallet);
    }
    context.read<NotificationsProvider?>()?.refreshUnreadCount();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ProfileAvatar extends StatelessWidget {
  final VoidCallback? onTap;

  const _ProfileAvatar({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          onTap ??
          () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
            );
          },
      child: Consumer2<MwaAuthProvider, ProfileProvider>(
        builder: (context, authProvider, profileProvider, child) {
          if (authProvider.walletAddress == null) {
            return _avatarShell(
              child: BasilIcon(
                'user-outline',
                size: 18.w,
                color: Colors.grey[700],
              ),
            );
          }
          return FutureBuilder<String>(
            future: profileProvider.getUserPfp(authProvider.walletAddress!),
            builder: (context, snapshot) {
              return _avatarShell(
                image: snapshot.hasData ? AssetImage(snapshot.data!) : null,
                child:
                    !snapshot.hasData
                        ? BasilIcon(
                          'user-outline',
                          size: 18.w,
                          color: Colors.grey[700],
                        )
                        : null,
              );
            },
          );
        },
      ),
    );
  }

  Widget _avatarShell({ImageProvider? image, Widget? child}) {
    return Container(
      width: 42.w,
      height: 42.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(color: Colors.grey[300]!, width: 1.w),
      ),
      child: Padding(
        padding: EdgeInsets.all(2.w),
        child: CircleAvatar(
          backgroundColor: Colors.grey[300],
          backgroundImage: image,
          child: child,
        ),
      ),
    );
  }
}

class _WalletButton extends StatelessWidget {
  const _WalletButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<MwaWalletProvider>(
      builder: (context, walletProvider, child) {
        return IconButton(
          tooltip: 'Copy wallet address',
          onPressed:
              walletProvider.walletAddress == null
                  ? null
                  : () async {
                    await Clipboard.setData(
                      ClipboardData(text: walletProvider.walletAddress!),
                    );
                    if (!context.mounted) return;
                    SnackBarUtils.showSuccess(
                      context,
                      title: 'Copied!',
                      subtitle: 'Wallet address copied to clipboard',
                    );
                  },
          icon: BasilIcon(
            'wallet-outline',
            size: 20.w,
            color: AppColors.textPrimary,
          ),
        );
      },
    );
  }
}

/// The one bell: calls activity plus the earlier wallet notices, opening
/// [ActivityScreen]. Its badge is the two unread counts added together.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell();

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  @override
  void initState() {
    super.initState();
    // Both counts on first sight, so the badge is right before the inbox is
    // ever opened. A missing provider (a test, a preview) is simply skipped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wallet = context.read<MwaAuthProvider?>()?.walletAddress;
      final arena = context.read<ArenaProvider?>();
      if (wallet != null && arena != null) {
        arena.loadNotifications(walletAddress: wallet);
      }
      context.read<NotificationsProvider?>()?.refreshUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final legacy =
        context.watch<ArenaProvider?>()?.unreadNotificationCount ?? 0;
    final calls = context.watch<NotificationsProvider?>()?.unreadCount ?? 0;
    final count = legacy + calls;
    return IconButton(
      tooltip: count == 0 ? 'Activity' : '$count unread',
      onPressed: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ActivityScreen()));
      },
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count'),
        backgroundColor: AppColors.primary,
        child: BasilIcon(
          'notification-outline',
          size: 20.w,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
