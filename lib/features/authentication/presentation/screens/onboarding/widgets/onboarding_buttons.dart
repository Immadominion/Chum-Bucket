import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/features/authentication/presentation/screens/login_screen.dart';
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary action button (Next/Get Started)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3355).withAlpha(75),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: () {
              if (isLastPage) {
                onCompleteOnboarding();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
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
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
              ),
              padding: EdgeInsets.symmetric(vertical: 16.h),
            ),
            child: Text(
              isLastPage ? "Get Started" : "Next",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),

        SizedBox(height: 12.h),

        // Secondary actions row (Back/Skip)
        Row(
          children: [
            // Back button (shown from page 2 onwards)
            if (currentPage > 0)
              Expanded(
                child: TextButton(
                  onPressed: () {
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
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                  child: Text(
                    "Back",
                    style: TextStyle(
                      color: const Color(0xFFFF3355),
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            // Skip button (only shown on first page)
            if (!isLastPage && currentPage == 0)
              Expanded(
                child: TextButton(
                  onPressed: () {
                    print("Skip button tapped");
                    onCompleteOnboarding();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                  child: Text(
                    "Skip",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
