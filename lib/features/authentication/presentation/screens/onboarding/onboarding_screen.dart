import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/config/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/background_pattern_painter.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/onboarding_controller.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/onboarding_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();

  // Method to navigate to a specific page - used by indicators
  void goToPage(int page) {
    if (page >= 0 && page < 3) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );

      // Update the provider
      Provider.of<OnboardingProvider>(
        context,
        listen: false,
      ).setCurrentPage(page);
    }
  }

  // Method to be called from OnboardingPage to navigate to next page
  void nextPage() {
    final int currentPage = _pageController.page?.round() ?? 0;
    final int nextPage = currentPage + 1;

    // Check if we're not already at the last page
    if (nextPage < 3) {
      // Use animateToPage for more reliable animation
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );

      // Also update the provider to keep everything in sync
      Provider.of<OnboardingProvider>(
        context,
        listen: false,
      ).setCurrentPage(nextPage);
    }
  }

  // Helper method to navigate to previous page
  void previousPage() {
    final int currentPage = _pageController.page?.round() ?? 0;

    // Check if we're not already at the first page
    if (currentPage > 0) {
      final int prevPage = currentPage - 1;

      // Use animateToPage for reliable animation
      _pageController.animateToPage(
        prevPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );

      // Also update the provider to keep everything in sync
      Provider.of<OnboardingProvider>(
        context,
        listen: false,
      ).setCurrentPage(prevPage);
    }
  }

  @override
  void initState() {
    super.initState();

    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only rebuild this provider when the current page changes
    final onboardingProvider = Provider.of<OnboardingProvider>(
      context,
      listen: true,
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          // Cache the gradient to improve performance
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.gradientStart,
              AppColors.gradientMiddle,
              AppColors.gradientEnd,
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Background pattern
            Positioned.fill(
              child: CustomPaint(painter: BackgroundPatternPainter()),
            ),

            // Main content
            SafeArea(
              child: OnboardingPageController(
                controller: _pageController,
                child: PageView(
                  physics:
                      const NeverScrollableScrollPhysics(), // Disable scrolling to use only buttons/indicators
                  controller: _pageController,
                  onPageChanged: (index) {
                    onboardingProvider.setCurrentPage(index);
                  },
                  children: const [
                    OnboardingPage(
                      title: "Dare Your Friends with Chum Bucket",
                      description:
                          "Set up fun challenges with your friends, bet coins, and keep each other on track. It's simple, social, and rewarding!",
                      illustration:
                          "assets/animations/whisk_ai_generate/onb_animation_1.gif",
                      isAnimated: true,
                      fallback:
                          "assets/images/ai_gen/whisk_animation_fallback/animation_image_1.jpg",
                    ),
                    OnboardingPage(
                      title: "Lock Coins, Win Big",
                      description:
                          "Add your friend's email or wallet, lock your CHUM tokens, and agree on the challenge. Winner takes the pot—minus our small 1% fee (capped at \$10).",
                      illustration:
                          "assets/animations/whisk_ai_generate/onb_animation_2.gif",
                      fallback:
                          "assets/images/ai_gen/whisk_animation_fallback/animation_image_2.jpg",
                      isAnimated: true,
                    ),
                    OnboardingPage(
                      title: "Fair and Transparent Wins",
                      description:
                          "Both friends sign to release funds to the winner. We keep 1% as a fee (up to \$10), stored publicly, with 50% for the team and 50% for Solana user airdrops.",
                      illustration:
                          "assets/animations/whisk_ai_generate/onb_animation_3.gif",
                      fallback:
                          "assets/images/ai_gen/whisk_animation_fallback/animation_image_3.jpg",
                      isAnimated: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
