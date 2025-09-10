import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/auth_provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';

class SplashNavigation {
  static Future<void> navigateToNextScreen(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final onboardingProvider = Provider.of<OnboardingProvider>(
      context,
      listen: false,
    );

    // Check if user is logged in
    final bool isLoggedIn = await authProvider.isLoggedIn();

    // Mark onboarding as completed for logged in users
    if (isLoggedIn) {
      await onboardingProvider.completeOnboarding();
    }

    if (!context.mounted) return;

    // Direct logged in users to home, others to login
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                isLoggedIn ? const HomeScreen() : const LoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }
}
