import 'dart:developer' as dev;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/auth_provider.dart';
import 'package:chumbucket/providers/profile_provider.dart';
import 'package:chumbucket/providers/wallet_provider.dart';
import 'package:chumbucket/screens/profile/widgets/profile_header.dart';
import 'package:chumbucket/screens/profile/widgets/wallet_balance_card.dart';
import 'package:chumbucket/screens/profile/widgets/settings_bottom_sheet.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  String _username = 'Username';
  String _bio = 'This is a short bio that describes the user.';

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    // Start animations
    _fadeController.forward();
    _slideController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // First ensure auth provider is initialized
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Make sure auth is initialized first
      if (!authProvider.isInitialized) {
        await authProvider.initialize();
      }

      // Only proceed if user is authenticated
      if (authProvider.isAuthenticated) {
        // Load user profile
        final profileProvider = Provider.of<ProfileProvider>(
          context,
          listen: false,
        );
        final profile = await profileProvider.getUserProfileFromLocal();

        if (profile != null) {
          setState(() {
            _username = profile['full_name'] ?? 'Username';
            _bio =
                profile['bio'] ??
                'This is a short bio that describes the user.';
          });
        }

        // Ensure wallet provider is initialized
        final walletProvider = Provider.of<WalletProvider>(
          context,
          listen: false,
        );

        if (!walletProvider.isInitialized) {
          dev.log('Initializing wallet from profile screen');
          // Explicitly initialize the wallet
          await walletProvider.initializeWallet(context);
        } else {
          // If wallet is already initialized, just refresh the balance
          // This triggers the loading state to show
          dev.log('Wallet already initialized, refreshing balance');
          walletProvider.refreshBalance();
        }
      } else {
        // Handle not authenticated state
        // This depends on your app flow - you might want to redirect to login
        // or show a placeholder until authentication completes
        dev.log(
          'User not authenticated, skipping profile and wallet initialization',
        );
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 20.h),

                  // Top Row with Settings and Cancel Icons
                  _buildTopBar(context),

                  SizedBox(height: 12.h),

                  // Profile Header
                  ProfileHeader(username: _username, bio: _bio),

                  SizedBox(height: 24.h),

                  // Wallet Balance Card
                  const WalletBalanceCard(),

                  SizedBox(height: 330.h),

                  // Footer
                  _buildFooter(context),

                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: Icon(CupertinoIcons.gear_alt, size: 28.sp),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
              ),
              isScrollControlled: true,
              builder: (context) => const SettingsBottomSheet(),
            );
          },
        ),
        IconButton(
          icon: Icon(CupertinoIcons.xmark, size: 26.sp),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Center(
      child: Text.rich(
        TextSpan(
          text: 'Chum Bucket v0.0.1 • ',
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(150),
          ),
          children: [
            TextSpan(
              text: 'Privacy Policy',
              style: TextStyle(
                fontSize: 18.sp,
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
