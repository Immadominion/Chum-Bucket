import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
// MWA Wallet Provider for Pinocchio program integration
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/menu_tile.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_buttons.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/identity_link_sheet.dart';
import 'package:chumbucket/core/services/chat_service.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

class SettingsBottomSheet extends StatefulWidget {
  const SettingsBottomSheet({super.key});

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Settings & Support',
    height: MediaQuery.sizeOf(context).height * .8,
    body: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24.w,
          right: 24.w,
          top: 24.h,
          bottom: 24.h,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              title: "Link Google",
              subtitle: "Keep your existing profile and history",
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
              onPressed: () => signOutOfChumbucket(context),
              icon: 'arrow-right-outline',
              gradientColors: [Colors.grey.shade600, Colors.grey.shade700],
            ),

            SizedBox(height: 32.h),
          ],
        ),
      ),
    ),
  );

  void _showWalletExportWarning(BuildContext context) {
    // First close the settings sheet
    Navigator.of(context).pop();

    // Use a short delay to ensure the context is ready for the next modal
    Future.delayed(const Duration(milliseconds: 100), () {
      // Check if context is still mounted before showing new modal
      if (context.mounted) {
        // Show wallet export warning sheet
        showChumbucketWavySheet<void>(
          context: context,
          builder: (_) => const WalletExportWarningSheet(),
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
