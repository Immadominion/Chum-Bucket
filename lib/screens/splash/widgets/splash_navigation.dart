import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:recess/providers/onboarding_provider.dart';
import 'package:recess/screens/home/home.dart';
import 'package:recess/screens/onboarding/onboarding_screen.dart';

class SplashNavigation {
  static Future<void> navigateToNextScreen(BuildContext context) async {
    final onboardingProvider = Provider.of<OnboardingProvider>(
      context,
      listen: false,
    );

    final bool isOnboardingCompleted =
        await onboardingProvider.isOnboardingCompleted();

    if (!context.mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                isOnboardingCompleted
                    ? const HomeScreen()
                    : const OnboardingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }
}
