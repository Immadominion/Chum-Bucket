import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/onboarding_controller.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/onboarding_page.dart';
import 'package:chumbucket/services/onboarding_audio_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final OnboardingAudioService _audioService = OnboardingAudioService();

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

    // Add observer for app lifecycle
    WidgetsBinding.instance.addObserver(this);

    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Start background music for onboarding
    _initializeAndStartMusic();
  }

  // Initialize and start the background music
  Future<void> _initializeAndStartMusic() async {
    try {
      await _audioService.initialize();
      await _audioService.startOnboardingMusic();
    } catch (e) {
      // Silently handle audio errors to prevent app crashes
      print('Audio initialization error: $e');
    }
  }

  @override
  void dispose() {
    // Remove observer
    WidgetsBinding.instance.removeObserver(this);

    _pageController.dispose();

    // Stop and dispose audio service when leaving onboarding
    _stopAndDisposeMusic();

    super.dispose();
  }

  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Pause music when app goes to background
        _audioService.pauseOnboardingMusic();
        break;
      case AppLifecycleState.resumed:
        // Resume music when app comes back to foreground
        _audioService.resumeOnboardingMusic();
        break;
      case AppLifecycleState.detached:
        // Stop music when app is detached
        _audioService.stopOnboardingMusic();
        break;
      case AppLifecycleState.hidden:
        // Optional: pause when hidden
        _audioService.pauseOnboardingMusic();
        break;
    }
  }

  // Stop and dispose the background music
  Future<void> _stopAndDisposeMusic() async {
    try {
      await _audioService.stopOnboardingMusic();
      await _audioService.dispose();
    } catch (e) {
      // Silently handle audio errors
      print('Audio disposal error: $e');
    }
  }

  // Method to get the current page widget based on index
  Widget _getCurrentPage(int currentPage) {
    const pages = [
      OnboardingPage(
        title: "Dare Your Friends with Chum Bucket",
        description:
            "Set up fun challenges with your friends, bet coins, and keep each other on track. It's simple, social, and rewarding!",
        illustration: "assets/animations/whisk_ai_generate/onb_animation_1.gif",
        isAnimated: true,
        fallback:
            "assets/images/ai_gen/whisk_animation_fallback/animation_image_1.jpg",
      ),
      OnboardingPage(
        title: "Lock Coins, Win Big",
        description:
            "Add your friend's email or wallet, lock your CHUM tokens, and agree on the challenge. Winner takes the pot—minus our small 1% fee (capped at \$10).",
        illustration: "assets/animations/whisk_ai_generate/onb_animation_2.gif",
        fallback:
            "assets/images/ai_gen/whisk_animation_fallback/animation_image_2.jpg",
        isAnimated: true,
      ),
      OnboardingPage(
        title: "Fair and Transparent Wins",
        description:
            "Challenger signs to release funds to the winner. We keep 1% as a fee (up to \$10), stored publicly, with 50% for the team and 50% for Solana user airdrops.",
        illustration: "assets/animations/whisk_ai_generate/onb_animation_3.gif",
        fallback:
            "assets/images/ai_gen/whisk_animation_fallback/animation_image_3.jpg",
        isAnimated: true,
      ),
    ];

    return KeyedSubtree(key: ValueKey(currentPage), child: pages[currentPage]);
  }

  @override
  Widget build(BuildContext context) {
    // Only rebuild this provider when the current page changes
    final onboardingProvider = Provider.of<OnboardingProvider>(
      context,
      listen: true,
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade50, // Light background like home screen
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: OnboardingPageController(
              controller: _pageController,
              context: context,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.1, 0.0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  );
                },
                child: _getCurrentPage(onboardingProvider.currentPage),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
