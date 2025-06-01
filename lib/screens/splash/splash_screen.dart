import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:recess/screens/login/login_screen.dart';
import 'package:recess/screens/splash/widgets/chum_text.dart';
import 'package:recess/screens/splash/widgets/splash_animations.dart';
import 'package:recess/screens/splash/widgets/bucket.dart';
import 'package:recess/screens/splash/widgets/splash_background_painter.dart'; // Added import

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

    // Fade out and navigate
    await _animations.fadeOutController.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
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
                SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          // Constrain the area for the Stack
                          width: 200.w, // Matches BucketWidget's width
                          height: 400.w, // Matches BucketWidget's height
                          child: Stack(
                            children: [
                              // Individual bucket (shows first, hidden when combined shows)
                              if (_showBucket)
                                BucketWidget(animations: _animations),

                              if (_showText)
                                Positioned(
                                  top: 200.h,
                                  left: 0,
                                  right: 0,
                                  child: ChumTextLogo(animations: _animations),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
