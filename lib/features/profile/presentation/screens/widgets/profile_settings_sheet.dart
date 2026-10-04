import 'package:chumbucket/core/crash/crash_reports_setting_tile.dart';
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
import 'package:chumbucket/features/profile/presentation/screens/widgets/sign_in_methods_sheet.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_settings.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:chumbucket/features/trust/presentation/delete_account_screen.dart';
import 'package:chumbucket/features/trust/presentation/legacy_history_screen.dart';
import 'package:chumbucket/features/trust/presentation/privacy_data_screen.dart';

/// Settings: support, privacy and data, legal, history and the account.
class ProfileSettingsSheet extends StatelessWidget {
  const ProfileSettingsSheet({super.key, this.onOpenChallenges});

  /// Opens the escrow challenge list (owned by the home shell). Passed through
  /// to Settings → History.
  final VoidCallback? onOpenChallenges;

  @override
  Widget build(BuildContext context) {
    return ChumbucketWavySheet(
      title: 'Account & Support',
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProfileMenuItem(
              basilIcon: 'star-outline',
              title: 'Rate Chumbucket',
              subtitle: 'Tell others what you think',
              iconColor: Colors.amber,
              onTap: () => openStoreListing(context),
            ),
            ProfileMenuItem(
              icon: Icons.help_outline,
              title: 'Talk To Support',
              subtitle: 'Get help when you need it',
              iconColor: Colors.blue,
              onTap: () => _openTawkToSupport(context),
              iconSize: 30,
            ),
            // Every way into this account (wallet, X, Google): signed in
            // with, link, unlink, and moving another account in.
            if (context.watch<ChumbucketSession?>()?.isReady == true)
              ProfileMenuItem(
                basilIcon: 'key-outline',
                title: 'Sign-in methods',
                subtitle: 'Wallet, X and Google',
                iconColor: AppColors.primary,
                onTap: () => _showSignInMethods(context),
              )
            // Linking Google carries a connected wallet's existing profile;
            // with no wallet connected (a Google or X account) there is
            // nothing to carry, so it is not offered.
            else if (context.watch<MwaAuthProvider?>()?.isAuthenticated == true)
              ProfileMenuItem(
                basilIcon: 'user-outline',
                title: 'Link Google',
                subtitle: 'Keep your existing profile and history',
                iconColor: AppColors.primary,
                onTap: () => _showIdentityLink(context),
              ),

            // The topics chosen in onboarding, and where notifications stand
            // (asked for in context, never from here unprompted).
            const TopicsSettingsItem(),
            const NotificationsSettingsItem(),
            const CrashReportsSettingTile(),
            ProfileMenuItem(
              basilIcon: 'shield-outline',
              title: 'Privacy & data',
              subtitle: 'Analytics, export, blocks, terms',
              iconColor: AppColors.primary,
              onTap: () => _push(context, (_) => const PrivacyDataScreen()),
            ),
            ProfileMenuItem(
              basilIcon: 'history-outline',
              title: 'History',
              subtitle: 'Earlier escrow challenges and Arena',
              iconColor: AppColors.primary,
              onTap:
                  () => _push(
                    context,
                    (_) => LegacyHistoryScreen(
                      onOpenEscrowChallenges: onOpenChallenges,
                    ),
                  ),
            ),
            ProfileMenuItem(
              basilIcon: 'trash-outline',
              title: 'Delete account',
              subtitle: 'Permanently remove your account',
              isDanger: true,
              onTap: () => _push(context, (_) => const DeleteAccountScreen()),
            ),

            SizedBox(height: 16.h),
            // Actions follow the menu; no screen-height spacer or empty tail.
            ChallengeButton(
              createNewChallenge: () => signOutOfChumbucket(context),
              label: 'Sign Out',
            ),
          ],
        ),
      ),
    );
  }

  /// Close the sheet, then open a full screen on the same navigator.
  void _push(BuildContext context, WidgetBuilder builder) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: builder));
  }

  /// Open Tawk.to support chat in external browser
  void _openTawkToSupport(BuildContext context) {
    // Close the current sheet first
    Navigator.pop(context);
    // Open chat in external browser to avoid webview privacy manifest requirements
    ChatService.openChat(context);
  }

  void _showSignInMethods(BuildContext context) {
    final navigator = Navigator.of(context);
    final hostContext = navigator.context;
    navigator.pop();
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (!hostContext.mounted) return;
      showSignInMethodsSheet(hostContext);
    });
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

    // A connected (MWA) wallet's keys live in that wallet app; Chumbucket
    // never holds them. Device-wallet export belongs to the wallet itself.
    Navigator.pop(context);
    SnackBarUtils.showInfo(
      context,
      title: 'Use your wallet app',
      subtitle:
          'Chumbucket never holds your secret phrase. Export it from the wallet app you connected.',
    );
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
              'Your keys stay in your wallet app.',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            Text(
              'Chumbucket never holds your secret phrase. To back up or export your keys, use the wallet app you connected (for example Phantom or Solflare).',
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
Future<void> showProfileSettingsSheet(
  BuildContext context, {
  VoidCallback? onOpenChallenges,
}) => showChumbucketWavySheet<void>(
  context: context,
  builder: (_) => ProfileSettingsSheet(onOpenChallenges: onOpenChallenges),
);
