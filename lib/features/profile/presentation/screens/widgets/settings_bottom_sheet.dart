import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
// MWA Auth Provider for wallet-based authentication
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
// MWA Wallet Provider for Pinocchio program integration
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
// MWA Login Screen for wallet connection
import 'package:chumbucket/features/authentication/presentation/screens/mwa_login_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/menu_tile.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_buttons.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/identity_link_sheet.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/core/services/chat_service.dart';
import 'package:chumbucket/core/services/realtime_service.dart';
import 'package:chumbucket/core/services/app_lifecycle_service.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'dart:ui';
import 'dart:io';

class SettingsBottomSheet extends StatefulWidget {
  const SettingsBottomSheet({Key? key}) : super(key: key);

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24.w,
        right: 24.w,
        top: 24.h,
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            24.h, // Adjust for keyboard
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: BasilIcon('cross-outline', size: 18.sp),
                onPressed: () => Navigator.of(context).pop(),
              ),
              SizedBox(width: 24.w),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            "Settings & Support",
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          SizedBox(height: 16.h),
          Consumer<MwaWalletProvider>(
            builder: (context, walletProvider, _) {
              return MenuTile(
                basilIcon: 'share-box-outline',
                title: "Export Wallet",
                subtitle:
                    walletProvider.walletAddress != null
                        ? 'View your wallet details'
                        : 'Loading...',
                onTap: () => _showWalletExportWarning(context),
              );
            },
          ),

          MenuTile(
            basilIcon: 'star-solid',
            title: "Rate Chum Bucket",
            subtitle: "Share your experience",
            onTap: () {},
            iconColor: Colors.amber,
          ),
          MenuTile(
            icon: CupertinoIcons.question_circle_fill,
            title: "Support",
            subtitle: "Get help when you need it",
            onTap: () => _openSupport(context),
            iconColor: Colors.blue,
          ),
          MenuTile(
            basilIcon: 'user-plus-outline',
            title: "Link Google or X",
            subtitle: "Put a name behind your calls",
            onTap: () => _showIdentityLink(context),
            iconColor: Theme.of(context).colorScheme.primary,
          ),
          MenuTile(
            basilIcon: 'trash-solid',
            title: "Delete Account",
            subtitle: "Permanently remove your account",
            onTap: () {},
            isDanger: true,
          ),
          SizedBox(height: 16.h),

          // Sign Out Button (Disconnect Wallet for MWA)
          GradientButton(
            text: "Disconnect Wallet",
            onPressed: () async {
              debugPrint('🚪 LOGOUT: Starting disconnect process');

              // Get all providers before clearing
              final authProvider = Provider.of<MwaAuthProvider>(
                context,
                listen: false,
              );
              final walletProvider = Provider.of<MwaWalletProvider>(
                context,
                listen: false,
              );
              final profileProvider = Provider.of<ProfileProvider>(
                context,
                listen: false,
              );
              final onboardingProvider = Provider.of<OnboardingProvider>(
                context,
                listen: false,
              );

              // Clear all services and providers in correct order
              debugPrint('🚪 LOGOUT: Unsubscribing from realtime');
              await RealtimeService.instance.unsubscribe();

              debugPrint('🚪 LOGOUT: Disposing AppLifecycleService');
              AppLifecycleService.instance.dispose();

              debugPrint('🚪 LOGOUT: Clearing ChallengeStateProvider');
              ChallengeStateProvider.instance.clear();

              debugPrint('🚪 LOGOUT: Clearing MwaWalletProvider');
              walletProvider.clear();

              debugPrint('🚪 LOGOUT: Clearing ProfileProvider');
              await profileProvider.clearUserData();

              debugPrint('🚪 LOGOUT: Clearing OnboardingProvider');
              await onboardingProvider.clearUserData();

              debugPrint('🚪 LOGOUT: Calling authProvider.logout()');
              await authProvider.logout();

              debugPrint(
                '🚪 LOGOUT: All providers cleared, navigating to login',
              );
              // Use pushAndRemoveUntil to completely clear the navigation stack
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => const MwaLoginScreen(),
                  ),
                  (route) => false, // Remove ALL routes
                );
              }
            },
            icon: 'arrow-right-outline',
            gradientColors: [Colors.grey.shade600, Colors.grey.shade700],
          ),

          SizedBox(height: 32.h),
        ],
      ),
    );
  }

  void _showWalletExportWarning(BuildContext context) {
    // First close the settings sheet
    Navigator.of(context).pop();

    // Use a short delay to ensure the context is ready for the next modal
    Future.delayed(const Duration(milliseconds: 100), () {
      // Check if context is still mounted before showing new modal
      if (context.mounted) {
        // Show wallet export warning sheet
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withOpacity(0.5),
          elevation: 0,
          builder: (context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom:
                        Platform.isIOS
                            ? MediaQuery.of(context).padding.bottom + 10.h
                            : MediaQuery.of(context).padding.bottom + 20.h,
                  ),
                  child: const WalletExportWarningSheet(),
                ),
              ),
            );
          },
        );
      }
    });
  }

  Future<void> _openSupport(BuildContext context) async {
    try {
      // First close the settings sheet
      Navigator.of(context).pop();

      // Use a short delay to ensure the context is ready
      await Future.delayed(const Duration(milliseconds: 100));

      // Check if context is still mounted before opening support
      if (context.mounted) {
        await ChatService.openChat(context);
      }
    } catch (e) {
      // If there's an error, show a simple error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to open support chat: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showIdentityLink(BuildContext context) {
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;
    navigator.pop();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!hostContext.mounted) return;
      showChumbucketWavySheet<void>(
        context: hostContext,
        builder: (_) => const IdentityLinkSheet(),
      );
    });
  }
}
