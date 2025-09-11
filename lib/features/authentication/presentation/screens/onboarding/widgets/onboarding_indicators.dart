import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
    // Get the onboarding controller for navigation
    final controller = OnboardingPageController.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
            margin: EdgeInsets.symmetric(horizontal: 4.w),
            height: 8.h,
            width: index == currentPage ? 24.w : 8.w,
            decoration: BoxDecoration(
              color:
                  index == currentPage
                      ? const Color(0xFFFF3355) // Primary color
                      : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),
        ),
      ),
    );
  }
}
