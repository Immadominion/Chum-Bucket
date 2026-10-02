import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_menu_item.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
import 'package:chumbucket/core/services/chat_service.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/identity_link_sheet.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

/// Settings modal sheet following the app's design conventions
class ProfileSettingsSheet extends StatelessWidget {
  const ProfileSettingsSheet({super.key});

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Account & Support',
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Menu items - scrollable content
          Column(
            children: [
              // Note: "My Wallet - Export private key" removed since
              // wallet is connected via MWA (Mobile Wallet Adapter)
              // Users manage their keys in their wallet app (Phantom, etc.)
              ProfileMenuItem(
                basilIcon: 'star-outline',
                title: 'Rate Chum Bucket',
                subtitle: 'Share your experience',
                iconColor: Colors.amber,
                onTap: () {},
              ),

              ProfileMenuItem(
                icon: Icons.help_outline,
                title: 'Talk To Support',
                subtitle: 'Get help when you need it',
                iconColor: Colors.blue,
                onTap: () => _openTawkToSupport(context),
                iconSize: 30,
              ),

              // Linking Google carries a connected wallet's existing profile;
              // with no wallet connected (a Google or X account) there is
              // nothing to carry, so it is not offered.
              if (context.watch<MwaAuthProvider?>()?.isAuthenticated == true)
                ProfileMenuItem(
                  basilIcon: 'user-outline',
                  title: 'Link Google',
                  subtitle: 'Keep your existing profile and history',
                  iconColor: AppColors.primary,
                  onTap: () => _showIdentityLink(context),
                ),

              ProfileMenuItem(
                basilIcon: 'trash-outline',
                title: 'Delete Your Account',
                subtitle: 'Permanently remove your account',
                isDanger: true,
                onTap: () {
                  Navigator.pop(context);
                  SnackBarUtils.showInfo(
                    context,
                    title: 'Coming Soon...',
                    subtitle: 'You can open a ticket about that for now.',
                  );
                },
              ),

              SizedBox(height: 16.h),
            ],
          ),

          // Actions follow the menu; no screen-height spacer or empty tail.
          ChallengeButton(
            createNewChallenge: () => signOutOfChumbucket(context),
            label: 'Sign Out',
          ),
        ],
      ),
    ),
  );

  /// Open Tawk.to support chat in external browser
  void _openTawkToSupport(BuildContext context) {
    // Close the current sheet first
    Navigator.pop(context);
    // Open chat in external browser to avoid webview privacy manifest requirements
    ChatService.openChat(context);
  }

  void _showIdentityLink(BuildContext context) {
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;
    navigator.pop();
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (!hostContext.mounted) return;
      showChumbucketWavySheet<void>(
        context: hostContext,
        builder: (_) => const IdentityLinkSheet(),
      );
    });
  }
}

/// Warning sheet for wallet export
class WalletExportWarningSheet extends StatefulWidget {
  const WalletExportWarningSheet({super.key});

  @override
  State<WalletExportWarningSheet> createState() =>
      _WalletExportWarningSheetState();
}

class _WalletExportWarningSheetState extends State<WalletExportWarningSheet> {
  final bool _isLoading = false;

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Export Wallet',
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            Text(
              'Are you sure you want to export your wallet secret phrase?',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            Text(
              'We cannot guarantee the security of your account after you export your secret phrase. Please store it securely and never share it with anyone.',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Action buttons
            ChumbucketPrimaryButton(
              label: 'Export Wallet',
              busy: _isLoading,
              busyLabel: 'Exporting…',
              onPressed: _attemptWalletExport,
            ),

            SizedBox(height: 8.h),

            // Cancel button
            ChumbucketTextAction(
              label: 'Cancel',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _attemptWalletExport() async {
    if (_isLoading) return;

    Navigator.pop(context);
    SnackBarUtils.showInfo(
      context,
      title: 'Coming Soon...',
      subtitle: 'This feature is under development.',
    );

    //TODO: Work on wallet export functionality
    // setState(() {
    //   _isLoading = true;
    // });

    // try {
    //   final walletProvider = Provider.of<MwaWalletProvider>(
    //     context,
    //     listen: false,
    //   );

    //   final walletAddress = walletProvider.walletAddress;
    //   if (walletAddress == null) {
    //     throw Exception('No wallet address available');
    //   }

    //   // Simulate wallet export attempt (since Privy may not allow direct export)
    //   await Future.delayed(const Duration(seconds: 2));

    //   if (!mounted) return;

    //   // For now, show that full export is not available but address can be copied
    //   Navigator.pop(context);
    //   await Future.delayed(const Duration(milliseconds: 100));

    //   if (mounted) {
    //     _showWalletCopyOptions(context);
    //   }
    // } catch (e) {
    //   if (!mounted) return;

    //   ScaffoldMessenger.of(context).showSnackBar(
    //     SnackBar(
    //       content: Text('Export failed: $e'),
    //       backgroundColor: Colors.red,
    //     ),
    //   );

    //   // Close current sheet and show address copy as fallback
    //   Navigator.pop(context);
    //   await Future.delayed(const Duration(milliseconds: 100));

    //   if (mounted) {
    //     _showWalletCopyOptions(context);
    //   }
    // } finally {
    //   if (mounted) {
    //     setState(() {
    //       _isLoading = false;
    //     });
    //   }
    // }
  }
}

/// Sheet for copying wallet address (alternative to full export)
class WalletCopySheet extends StatelessWidget {
  final String walletAddress;

  const WalletCopySheet({super.key, required this.walletAddress});

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Wallet Address',
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            // Wallet address display
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                walletAddress,
                style: TextStyle(
                  fontSize: 14.sp,
                  fontFamily: 'monospace',
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            SizedBox(height: 16.h),

            Text(
              'Full wallet export is not available through the mobile app for security reasons. You can copy your address above.',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Copy button
            ChallengeButton(
              createNewChallenge: () async {
                await Clipboard.setData(ClipboardData(text: walletAddress));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Wallet address copied to clipboard'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              label: 'Copy Address',
              hasGradient: false,
            ),

            SizedBox(height: 8.h),

            // Close button
            ChumbucketTextAction(
              label: 'Close',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Sheet showing that wallet export is not available
class WalletExportNotAvailableSheet extends StatelessWidget {
  const WalletExportNotAvailableSheet({super.key});

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Export Not Available',
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          children: [
            Text(
              'Your holdings are held in cryptocurrency wallets in your custody.',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            Text(
              'You can directly control your wallets using your secret phrase, but wallet export is currently not available through the mobile app. Your wallet secrets are managed securely by Privy.',
              style: TextStyle(
                fontSize: 14.sp,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // Close button
            ChallengeButton(
              createNewChallenge: () => Navigator.pop(context),
              label: 'Got It',
              hasGradient: false,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Function to show the settings sheet with backdrop blur
Future<void> showProfileSettingsSheet(BuildContext context) =>
    showChumbucketWavySheet<void>(
      context: context,
      builder: (_) => const ProfileSettingsSheet(),
    );
