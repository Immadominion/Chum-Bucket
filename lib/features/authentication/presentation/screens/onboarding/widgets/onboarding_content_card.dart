import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: compact ? 24.sp : 28.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
                height: 1.2,
              ),
              textAlign: TextAlign.left,
            ),

            SizedBox(height: compact ? 16.h : 20.h),

            Text(
              description,
              style: TextStyle(
                fontSize: compact ? 16.sp : 18.sp,
                color: Colors.grey.shade600,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.left,
            ),

            SizedBox(height: compact ? 24.h : 32.h),

            // Buttons
            buttonsWidget,
          ],
        ),
      ),
    );
  }
}
