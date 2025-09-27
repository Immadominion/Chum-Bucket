import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/menu_tile.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_buttons.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/core/services/chat_service.dart';
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
                icon: Icon(CupertinoIcons.xmark, size: 18.sp),
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
          Consumer<WalletProvider>(
            builder: (context, walletProvider, _) {
              return MenuTile(
                icon: CupertinoIcons.square_arrow_up,
                title: "Export Wallet",
                subtitle:
                    walletProvider.walletAddress != null
                        ? 'Export or copy your wallet details'
                        : 'Loading...',
                onTap: () => _showWalletExportWarning(context),
              );
            },
          ),

          MenuTile(
            icon: CupertinoIcons.star_fill,
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
            icon: CupertinoIcons.delete_solid,
            title: "Delete Account",
            subtitle: "Permanently remove your account",
            onTap: () {},
            isDanger: true,
          ),
          SizedBox(height: 16.h),

          // Sign Out Button
          GradientButton(
            text: "Sign Out",
            onPressed: () async {
              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );
              await authProvider.clearUserData();

              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
            icon: CupertinoIcons.square_arrow_right,
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
}
