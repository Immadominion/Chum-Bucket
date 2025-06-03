import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/config/theme/app_theme.dart';

class OnboardingContentCard extends StatelessWidget {
  final String title;
  final String description;
  final Animation<double> fadeAnimation;
  final Widget buttonsWidget;
  final bool compact;

  const OnboardingContentCard({
    super.key,
    required this.title,
    required this.description,
    required this.fadeAnimation,
    required this.buttonsWidget,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnimation,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 10,
            sigmaY: 10,
          ), // Reduced blur for better performance
          child: Container(
            width: double.infinity,
            height: compact ? 230.h : 260.h,
            padding: EdgeInsets.all(26.w),
            decoration: BoxDecoration(
              color: AppColors.glassmorphismCard,
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(
                color: AppColors.glassmorphismBorder,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 28.sp, // Increased font size
                    fontWeight: FontWeight.bold,
                    color: AppColors.glassmorphismText,
                  ),
                  textAlign: TextAlign.left,
                ),

                SizedBox(height: 16.h),

                Text(
                  description,
                  style: TextStyle(
                    fontSize: 20.sp, // Increased font size
                    color: AppColors.glassmorphismSecondaryText,
                  ),
                  textAlign: TextAlign.left,
                ),

                SizedBox(height: 24.h),

                // Buttons
                buttonsWidget,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
