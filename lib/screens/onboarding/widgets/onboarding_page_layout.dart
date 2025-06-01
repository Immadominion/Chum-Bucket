import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:recess/providers/onboarding_provider.dart';
import 'package:recess/screens/onboarding/widgets/animated_onboarding_image.dart';
import 'package:recess/screens/onboarding/widgets/onboarding_indicators.dart';
import 'package:recess/screens/onboarding/widgets/question_button.dart';

class OnboardingPageLayout extends StatelessWidget {
  final String illustration;
  final bool isAnimated;
  final String? fallback;
  final Animation<double> scaleAnimation;
  final Widget contentCard;

  const OnboardingPageLayout({
    super.key,
    required this.illustration,
    required this.isAnimated,
    this.fallback,
    required this.scaleAnimation,
    required this.contentCard,
  });

  @override
  Widget build(BuildContext context) {
    // Pre-cache images for better performance
    precacheImage(AssetImage(illustration), context);
    if (fallback != null) {
      precacheImage(AssetImage(fallback!), context);
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Use available height for calculations instead of screen height
          final availableHeight = constraints.maxHeight;

          return Column(
            children: [
              SizedBox(height: 12.h), // Reduced top padding
              // Question button at top
              const QuestionButton(),

              SizedBox(height: availableHeight * 0.02), // Reduced spacing
              // Illustration takes about 38% of available height (reduced from 40%)
              SizedBox(
                height: availableHeight * 0.38,
                child: ScaleTransition(
                  scale: scaleAnimation,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: AnimatedOnboardingImage(
                      illustration: illustration,
                      isAnimated: isAnimated,
                      fallback: fallback,
                    ),
                  ),
                ),
              ),

              SizedBox(height: availableHeight * 0.03), // Reduced spacing
              // Content card with buttons - use Flexible to prevent overflow
              Flexible(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: contentCard,
                ),
              ),

              Expanded(
                flex: 1,
                child: SizedBox(),
              ), // Push indicators to bottom with equal spacing
              // Page indicators now at bottom of the page
              Consumer<OnboardingProvider>(
                builder: (context, onboardingProvider, _) {
                  return OnboardingPageIndicators(
                    currentPage: onboardingProvider.currentPage,
                  );
                },
              ),
              Expanded(flex: 1, child: SizedBox()),
              // Increased bottom padding for better spacing
            ],
          );
        },
      ),
    );
  }
}
