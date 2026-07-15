import 'dart:async';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/shared/screens/splash/widgets/bucket.dart';
import 'package:chumbucket/shared/screens/splash/widgets/chum_text.dart';
import 'package:chumbucket/shared/screens/splash/widgets/splash_animations.dart';
import 'package:chumbucket/shared/screens/splash/widgets/splash_background_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/features/authentication/presentation/screens/mwa_login_screen.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/edit_profile_screen.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

/// MWA-compatible splash screen
/// Uses MwaAuthProvider for wallet-based authentication instead of Privy
class MwaSplashScreen extends StatefulWidget {
  const MwaSplashScreen({super.key});

  @override
  State<MwaSplashScreen> createState() => _MwaSplashScreenState();
}

class _MwaSplashScreenState extends State<MwaSplashScreen>
    with TickerProviderStateMixin {
  late SplashAnimations _animations;

  bool _showBucket = false;
  bool _showText = false;

  @override
  void initState() {
    super.initState();
    _animations = SplashAnimations(vsync: this);
    _startAnimationSequence();
  }

  Future<void> _startAnimationSequence() async {
    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Start background animation
    _animations.backgroundController.forward();

    // Show and animate bucket
    await Future.delayed(const Duration(milliseconds: 100));
    setState(() {
      _showBucket = true;
    });
    await _animations.bucketController.forward();

    // Show and animate text
    await Future.delayed(const Duration(milliseconds: 50));
    setState(() {
      _showText = true;
    });
    await _animations.textController.forward();

    // Hold the bucket and text logo
    await Future.delayed(const Duration(milliseconds: 400));

    // Check MWA auth state and onboarding completion
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final onboardingProvider = Provider.of<OnboardingProvider>(
      context,
      listen: false,
    );

    // Initialize MWA Auth Provider if needed
    if (authProvider.state == MwaAuthState.initial) {
      debugPrint('Initializing MwaAuthProvider...');
      await authProvider.initialize();
      debugPrint('MwaAuthProvider initialized');
    }

    final isAuthenticated = authProvider.isAuthenticated;
    final hasCompletedOnboarding =
        await onboardingProvider.isOnboardingCompleted();

    debugPrint(
      'MWA Auth status: $isAuthenticated, Onboarding completed: $hasCompletedOnboarding',
    );

    if (isAuthenticated) {
      // Check if user has a name set up - if not, force profile setup
      final profileProvider = Provider.of<ProfileProvider>(
        context,
        listen: false,
      );
      final profile = await profileProvider.fetchUserProfile(
        authProvider.walletAddress!,
      );

      final hasName =
          profile != null &&
          profile['full_name'] != null &&
          profile['full_name'].toString().trim().isNotEmpty;

      // Also check if they have an SNS domain - that counts as having a name
      final hasDomain =
          authProvider.snsDomain != null && authProvider.snsDomain!.isNotEmpty;

      debugPrint('Profile check: hasName=$hasName, hasDomain=$hasDomain');

      if (!hasName && !hasDomain) {
        // User has no name AND no domain - force profile setup
        debugPrint('No name or domain found - forcing profile setup');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) => const EditProfileScreen(
                  showCancelIcon: false, // Can't skip
                  isRequired: true, // Must enter name
                ),
          ),
        );
      } else {
        // User has a name or domain - go to home screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
        // Trigger background sync for logged-in users to load challenges
        _triggerInitialSync(authProvider);
      }
    } else {
      // For new users, check if onboarding has been completed
      if (hasCompletedOnboarding) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MwaLoginScreen()),
        );
      } else {
        // Show onboarding for first-time users
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const OnboardingScreen()),
        );
      }
    }
  }

  // Trigger initial sync when user logs in to load challenges from blockchain
  Future<void> _triggerInitialSync(MwaAuthProvider authProvider) async {
    try {
      AppLogger.info('Scheduling delayed sync for MWA authenticated user');

      final walletAddress = authProvider.walletAddress;
      if (walletAddress == null || !mounted) return;

      // Schedule sync to happen AFTER navigation is complete
      // This prevents blocking the UI during app startup
      Future.delayed(Duration(seconds: 3), () async {
        if (!mounted) return;

        try {
          // Trigger background sync using wallet address as user ID
          EfficientSyncService.instance
              .getChallenges(
                userId: walletAddress, // Use wallet address as user identifier
                walletAddress: walletAddress,
              )
              .then((_) {
                AppLogger.info('Delayed sync completed successfully');
              })
              .catchError((e) {
                AppLogger.error('Delayed sync failed: $e');
                // Don't show errors to users
              });
        } catch (e) {
          AppLogger.error('Delayed sync error: $e');
        }
      });
    } catch (e) {
      AppLogger.error('Error scheduling initial sync: $e');
      // Don't block navigation on errors
    }
  }

  @override
  void dispose() {
    _animations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _animations.fadeOutAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _animations.fadeOutAnimation.value,
            child: Stack(
              children: [
                // Animated background pattern
                _buildAnimatedBackground(),

                // Main content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        // Constrain the area for the Stack
                        width: 200.w, // Matches BucketWidget's width
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: Stack(
                          children: [
                            // Individual bucket (shows first, hidden when combined shows)
                            if (_showBucket)
                              BucketWidget(animations: _animations),

                            if (_showText)
                              Positioned(
                                top: 150.h,
                                left: 0,
                                right: 0.w,
                                child: ChumTextLogo(animations: _animations),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _animations.backgroundAnimation,
      builder: (context, child) {
        return Positioned.fill(
          child: CustomPaint(
            painter: SplashBackgroundPainter(
              _animations.backgroundAnimation.value,
            ),
          ),
        );
      },
    );
  }
}
