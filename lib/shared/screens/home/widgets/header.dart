import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
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

  /// Opens people + market search. Null shows no search action.
  final VoidCallback? onSearchTap;

  /// Extra icon actions for this screen, drawn before search (e.g. Friends'
  /// leaderboard). Icons, not words.
  final List<Widget> actions;

  const ChumbucketAppHeader({
    super.key,
    this.title,
    this.onProfileTap,
    this.showAccountActions = true,
    this.onActivityTap,
    this.onSearchTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          const _InboxResumeRefresh(),
          if (showAccountActions) _ProfileAvatar(onTap: onProfileTap),
          if (title != null) ...[
            if (showAccountActions) SizedBox(width: 12.w),
            // One word, one line: at large text the title shrinks to fit
            // rather than breaking mid-word beside the icons ("Market / s").
            Expanded(
              child: Semantics(
                header: true,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    title!,
                    maxLines: 1,
                    softWrap: false,
                    style: AppTextStyles.pageTitle,
                  ),
                ),
              ),
            ),
          ] else
            const Spacer(),
          ...actions,
          if (showAccountActions) ...[
            const _WalletButton(),
            SizedBox(width: 6.w),
          ],
          if (onSearchTap != null)
            IconButton(
              tooltip: 'Search',
              onPressed: onSearchTap,
              icon: BasilIcon(
                'search-outline',
                size: 20.w,
                color: AppColors.textPrimary,
              ),
            ),
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
    );
  }
}

/// Keeps the unread badge honest: refreshed when the app comes back to the
/// foreground and when a call notification arrives while it is open, not only
/// when the header first builds (prod readiness M3). Also makes sure this
/// device is registered for the signed-in account's pushes when the person
/// has already allowed notifications — it never prompts.
class _InboxResumeRefresh extends StatefulWidget {
  const _InboxResumeRefresh();

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

  /// The calls inbox count: the one the server derives and pushes for. The
  /// legacy Arena notices are not refreshed here (they leave the bell, M13).
  void _refreshBadge() {
    if (!mounted) return;
    context.read<NotificationsProvider?>()?.refreshUnreadCount();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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

/// The one bell: calls activity, opening [ActivityScreen]. The earlier Arena
/// and escrow notices live in Settings → History and do not count here.
class _NotificationBell extends StatefulWidget {
  const _NotificationBell();

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  @override
  void initState() {
    super.initState();
    // The count on first sight, so the badge is right before the inbox is
    // ever opened. A missing provider (a test, a preview) is simply skipped.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationsProvider?>()?.refreshUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = context.watch<NotificationsProvider?>()?.unreadCount ?? 0;
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
