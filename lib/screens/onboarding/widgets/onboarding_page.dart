import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/providers/onboarding_provider.dart';
import 'package:chumbucket/screens/onboarding/widgets/onboarding_buttons.dart';
import 'package:chumbucket/screens/onboarding/widgets/onboarding_content_card.dart';
import 'package:chumbucket/screens/onboarding/widgets/onboarding_page_layout.dart';

class OnboardingPage extends StatefulWidget {
  final String title;
  final String description;
  final String illustration;
  final String? fallback;
  final bool
  isAnimated; // Flag to determine if the illustration is an animated GIF

  const OnboardingPage({
    super.key,
    required this.title,
    required this.description,
    required this.illustration,
    this.isAnimated = false,
    this.fallback, // Default to static image
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(
        milliseconds: 800,
      ), // Shorter animation duration for better performance
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.9, // Less extreme scale for better performance
      end: 1.0,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    ); // Simplified curve

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingPageLayout(
      illustration: widget.illustration,
      isAnimated: widget.isAnimated,
      fallback: widget.fallback,
      scaleAnimation: _scaleAnimation,
      contentCard: _buildContentCard(context),
    );
  }

  Widget _buildContentCard(BuildContext context) {
    return Consumer<OnboardingProvider>(
      builder: (context, onboardingProvider, _) {
        // Use MediaQuery to check screen size and adjust content if needed
        final screenHeight = MediaQuery.of(context).size.height;
        final bool isSmallDevice = screenHeight < 700;

        return OnboardingContentCard(
          title: widget.title,
          description:
              isSmallDevice
                  ? widget.description.split('.').first + '...'
                  : widget.description,
          fadeAnimation: _fadeAnimation,
          buttonsWidget: OnboardingButtons(
            isLastPage: onboardingProvider.isLastPage,
            onCompleteOnboarding: onboardingProvider.completeOnboarding,
            onSetCurrentPage: onboardingProvider.setCurrentPage,
            currentPage: onboardingProvider.currentPage,
          ),
          compact:
              isSmallDevice, // Pass a flag to use compact layout on small devices
        );
      },
    );
  }
}

// Define a proper abstraction for navigation
// This way we don't need to rely on finding ancestor state
abstract class OnboardingNavigator {
  void nextPage();
}
