import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/arena/presentation/screens/arena_notifications_screen.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
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

  const ChumbucketAppHeader({super.key, this.title, this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Row(
        children: [
          _ProfileAvatar(onTap: onProfileTap),
          if (title != null) ...[
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                title!,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ] else
            const Spacer(),
          const _WalletButton(),
          SizedBox(width: 6.w),
          const _NotificationBell(),
        ],
      ),
    );
  }
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
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (context) => const ProfileScreen()));
          },
      child: Consumer2<MwaAuthProvider, ProfileProvider>(
        builder: (context, authProvider, profileProvider, child) {
          if (authProvider.walletAddress == null) {
            return _avatarShell(
              child: BasilIcon('user-outline', size: 18.w, color: Colors.grey[700]),
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

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return Consumer<ArenaProvider>(
      builder: (context, arena, child) {
        final count = arena.unreadNotificationCount;
        return IconButton(
          tooltip: count == 0 ? 'Inbox' : '$count unread notifications',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ArenaNotificationsScreen(),
              ),
            );
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
      },
    );
  }
}
