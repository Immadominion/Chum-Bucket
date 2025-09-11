import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/animated_onboarding_image.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/onboarding_indicators.dart';

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

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
            child: Column(
              children: [
                SizedBox(height: availableHeight * 0.05),

                // Illustration takes about 30% of available height
                SizedBox(
                  height: availableHeight * 0.30,
                  child: ScaleTransition(
                    scale: scaleAnimation,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20.w),
                      child: AnimatedOnboardingImage(
                        illustration: illustration,
                        isAnimated: isAnimated,
                        fallback: fallback,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: availableHeight * 0.05),

                // Content card - use Expanded to fill available space
                Expanded(child: contentCard),

                SizedBox(height: 20.h),

                // Page indicators at bottom
                Consumer<OnboardingProvider>(
                  builder: (context, onboardingProvider, _) {
                    return OnboardingPageIndicators(
                      currentPage: onboardingProvider.currentPage,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
