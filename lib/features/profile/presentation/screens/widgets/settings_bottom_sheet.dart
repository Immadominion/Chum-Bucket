import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/menu_tile.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/identity_link_sheet.dart';
import 'package:chumbucket/core/services/chat_service.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:chumbucket/features/trust/presentation/delete_account_screen.dart';

class SettingsBottomSheet extends StatefulWidget {
  const SettingsBottomSheet({super.key});

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Settings & Support',
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // No "Export Wallet": a connected wallet's keys live in that
            // wallet app, and Chumbucket never holds them.
            MenuTile(
              basilIcon: 'star-solid',
              title: "Rate Chumbucket",
              subtitle: "Tell others what you think",
              onTap: () => openStoreListing(context),
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
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeleteAccountScreen(),
                  ),
                );
              },
              isDanger: true,
            ),
            SizedBox(height: 16.h),

            // Sign Out Button (Disconnect Wallet for MWA)
            // The same call to action as Account & Support's Sign Out.
            ChumbucketPrimaryButton(
              label: 'Disconnect Wallet',
              onPressed: () => signOutOfChumbucket(context),
            ),
          ],
        ),
      ),
    ),
  );

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
