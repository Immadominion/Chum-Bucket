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
