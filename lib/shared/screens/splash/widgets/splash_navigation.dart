import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/features/authentication/presentation/screens/mwa_login_screen.dart';

class SplashNavigation {
  static Future<void> navigateToNextScreen(BuildContext context) async {
    final authProvider = Provider.of<MwaAuthProvider>(context, listen: false);
    final onboardingProvider = Provider.of<OnboardingProvider>(
      context,
      listen: false,
    );

    // Check if user is logged in (MWA wallet connected)
    final bool isLoggedIn = authProvider.isAuthenticated;

    // Mark onboarding as completed for logged in users
    if (isLoggedIn) {
      await onboardingProvider.completeOnboarding();
    }

    if (!context.mounted) return;

    // Direct logged in users to home, others to MWA login
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                isLoggedIn ? const HomeScreen() : const MwaLoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }
}
