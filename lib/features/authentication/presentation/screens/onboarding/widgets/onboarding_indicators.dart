import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/config/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/onboarding_controller.dart';

class OnboardingPageIndicators extends StatelessWidget {
  final int currentPage;
  final int pageCount;

  const OnboardingPageIndicators({
    super.key,
    required this.currentPage,
    this.pageCount = 3,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate the total width available for indicators based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final containerWidth =
        screenWidth - 16.w; // Accounting for the 24.w padding on each side

    // Calculate indicator widths to be evenly distributed
    final totalIndicatorWidth =
        containerWidth * 0.7; // Use 70% of container width
    final singleIndicatorWidth = totalIndicatorWidth / pageCount;

    // Get the onboarding controller for navigation
    final controller = OnboardingPageController.of(context);

    return SizedBox(
      width: containerWidth,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          pageCount,
          (index) => GestureDetector(
            onTap: () {
              // Navigate directly to the tapped page
              if (controller != null) {
                controller.goToPage(index);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 6.h,
              width:
                  index == currentPage
                      ? singleIndicatorWidth *
                          3 // Active dot is 80% longer
                      : singleIndicatorWidth * 0.2, // Inactive dots
              decoration: BoxDecoration(
                color:
                    index == currentPage
                        ? AppColors.primary
                        : AppColors.glassmorphismSecondaryText.withOpacity(0.5),
                borderRadius: BorderRadius.circular(3.r),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
