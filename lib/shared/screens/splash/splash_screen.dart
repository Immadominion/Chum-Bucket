import 'dart:async';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/shared/screens/splash/widgets/bucket.dart';
import 'package:chumbucket/shared/screens/splash/widgets/chum_text.dart';
import 'package:chumbucket/shared/screens/splash/widgets/splash_animations.dart';
import 'package:chumbucket/shared/screens/splash/widgets/splash_background_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/onboarding_screen.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/features/wallet/providers/wallet_provider.dart';
import 'package:chumbucket/shared/services/efficient_sync_service.dart';
import 'package:chumbucket/core/utils/app_logger.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
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

    // Check login state and onboarding completion
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final onboardingProvider = Provider.of<OnboardingProvider>(
      context,
      listen: false,
    );

    // Ensure AuthProvider is initialized before checking login status
    if (!authProvider.isInitialized) {
      debugPrint('Initializing AuthProvider...');
      await authProvider.initialize();
      debugPrint('AuthProvider initialized');
    }

    final isLoggedIn = await authProvider.isLoggedIn();
    final hasCompletedOnboarding =
        await onboardingProvider.isOnboardingCompleted();

    debugPrint(
      'Login status: $isLoggedIn, Onboarding completed: $hasCompletedOnboarding',
    );

    if (isLoggedIn) {
      // If they're logged in, always go to HomeScreen regardless of onboarding status
      // This ensures onboarding doesn't show repeatedly for existing users
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );

      // Trigger background sync for logged-in users to load challenges
      _triggerInitialSync(authProvider);
    } else {
      // For new users, check if onboarding has been completed
      if (hasCompletedOnboarding) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
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
  Future<void> _triggerInitialSync(AuthProvider authProvider) async {
    try {
      AppLogger.info('Triggering initial sync for logged-in user');

      final currentUser = authProvider.currentUser;
      if (currentUser == null || !mounted) return;

      // Get wallet provider to get wallet address
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );

      // Initialize wallet if not already done
      if (!walletProvider.isInitialized && mounted) {
        await walletProvider.initializeWallet(context);
      }

      final walletAddress = walletProvider.walletAddress;
      if (walletAddress != null) {
        // Trigger background sync without blocking navigation
        EfficientSyncService.instance
            .forceBlockchainSync(
              userId: currentUser.id,
              walletAddress: walletAddress,
            )
            .catchError((e) {
              AppLogger.error('Initial sync failed: $e');
              // Don't block navigation on sync failure
            });
      }
    } catch (e) {
      AppLogger.error('Error triggering initial sync: $e');
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
