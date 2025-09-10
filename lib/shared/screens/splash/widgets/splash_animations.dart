import 'package:flutter/material.dart';

class SplashAnimations {
  final TickerProvider vsync;

  late AnimationController bucketController;
  late AnimationController textController;
  late AnimationController combineController;
  late AnimationController backgroundController;
  late AnimationController fadeOutController;

  late Animation<double> bucketScaleAnimation;
  late Animation<double> bucketBounceAnimation;
  late Animation<double> bucketRotationAnimation;
  late Animation<Offset> bucketSlideAnimation;

  late Animation<double> textScaleAnimation;
  late Animation<double> textFadeAnimation;
  late Animation<Offset> textSlideAnimation;

  late Animation<double> combineScaleAnimation;
  late Animation<double> combineFadeAnimation;

  late Animation<double> backgroundAnimation;
  late Animation<double> fadeOutAnimation;

  SplashAnimations({required this.vsync}) {
    _setupAnimations();
  }

  void _setupAnimations() {
    // Bucket animations
    bucketController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: vsync,
    );

    bucketScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: bucketController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    bucketBounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: bucketController,
        curve: const Interval(0.6, 1.0, curve: Curves.bounceOut),
      ),
    );

    bucketRotationAnimation = Tween<double>(begin: -0.1, end: 0.0).animate(
      CurvedAnimation(parent: bucketController, curve: Curves.elasticOut),
    );

    bucketSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: bucketController, curve: Curves.elasticOut),
    );

    // Text animations
    textController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: vsync,
    );

    textScaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: textController, curve: Curves.elasticOut),
    );

    textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: textController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
      ),
    );

    textSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: textController, curve: Curves.easeOutBack),
    );

    // Combine animations
    combineController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: vsync,
    );

    combineScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: combineController, curve: Curves.easeOutBack),
    );

    combineFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: combineController, curve: Curves.easeOut),
    );

    // Background animation
    backgroundController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: vsync,
    );

    backgroundAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: backgroundController, curve: Curves.easeInOut),
    );

    // Fade out animation
    fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: vsync,
    );

    fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: fadeOutController, curve: Curves.easeInOut),
    );
  }

  void dispose() {
    bucketController.dispose();
    textController.dispose();
    combineController.dispose();
    backgroundController.dispose();
    fadeOutController.dispose();
  }
}
