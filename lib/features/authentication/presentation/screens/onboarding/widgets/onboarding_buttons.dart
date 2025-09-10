import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/config/theme/app_theme.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/features/authentication/presentation/screens/onboarding/widgets/onboarding_controller.dart';

class OnboardingButtons extends StatelessWidget {
  final bool isLastPage;
  final VoidCallback onCompleteOnboarding;
  final Function(int) onSetCurrentPage;
  final int currentPage;

  const OnboardingButtons({
    super.key,
    required this.isLastPage,
    required this.onCompleteOnboarding,
    required this.onSetCurrentPage,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Back button (hidden on first page)
        if (currentPage > 0)
          Expanded(
            child: GestureDetector(
              onTap: () {
                print("Back button tapped");
                // Go to previous page
                final controller = OnboardingPageController.of(context);
                if (controller != null) {
                  controller.previousPage();
                }
                // Update the provider (fallback)
                if (currentPage > 0) {
                  onSetCurrentPage(currentPage - 1);
                }
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                child: Text(
                  "Back",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

        // Skip button (only shown when there is no back button)
        if (!isLastPage && currentPage == 0)
          Expanded(
            child: GestureDetector(
              onTap: () {
                print("Skip button tapped");
                onCompleteOnboarding();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 16.h),
                child: Text(
                  "Skip",
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

        Expanded(
          flex: isLastPage ? 2 : 1,
          child: GestureDetector(
            onTap: () {
              if (isLastPage) {
                onCompleteOnboarding();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                );
              } else {
                // Use the controller to navigate to next page
                print("Moving to next page");
                // Get the controller from context
                final controller = OnboardingPageController.of(context);
                if (controller != null) {
                  // Use the controller to navigate
                  controller.nextPage();

                  // Also update the provider to ensure UI is in sync
                  int nextPage = currentPage + 1;
                  if (nextPage < 3) {
                    // Assuming 3 pages total
                    onSetCurrentPage(nextPage);
                  }
                } else {
                  // Fallback: just update the provider
                  print("Controller not found, just updating provider");
                  onSetCurrentPage(currentPage + 1);
                }
              }
            },
            child: Container(
              width: 120.w, // Fixed width for consistent button size
              padding: EdgeInsets.symmetric(vertical: 16.h),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(18.r),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              child: Text(
                isLastPage ? "Get Started" : "Next",
                style: TextStyle(
                  color: AppColors.buttonText,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
