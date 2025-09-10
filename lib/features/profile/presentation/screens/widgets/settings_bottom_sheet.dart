import 'package:chumbucket/shared/screens/database_test_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/menu_tile.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_buttons.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';

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
                icon: CupertinoIcons.creditcard,
                title: "My Wallet",
                subtitle:
                    walletProvider.walletAddress != null
                        ? 'Tap to view with domain resolution' // User can tap to see full resolved address in modal
                        : 'Loading...',
                onTap: () => _showMyWalletModal(context),
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
            onTap: () {},
            iconColor: Colors.blue,
          ),
          MenuTile(
            icon: CupertinoIcons.hammer_fill,
            title: "Database Test",
            subtitle: "Test local SQLite database",
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const DatabaseTestScreen(),
                ),
              );
            },
            iconColor: Colors.purple,
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

              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            icon: CupertinoIcons.square_arrow_right,
            gradientColors: [Colors.grey.shade600, Colors.grey.shade700],
          ),

          SizedBox(height: 32.h),
        ],
      ),
    );
  }

  void _showMyWalletModal(BuildContext context) {
    // Get the wallet provider first to ensure it's available to the modal
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    // Ensure we have the wallet address
    if (walletProvider.walletAddress == null) {
      walletProvider.refreshBalance();
    }

    // First close the settings sheet
    Navigator.of(context).pop();

    // Use a short delay to ensure the context is ready for the next modal
    Future.delayed(const Duration(milliseconds: 100), () {
      // Then show the wallet modal
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        builder: (BuildContext modalContext) {
          // Return the modal with an explicit provider to avoid context issues
          return ChangeNotifierProvider<WalletProvider>.value(
            value: walletProvider,
            child: const WalletModal(),
          );
        },
      );
    });
  }
}
