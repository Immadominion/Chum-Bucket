import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Header widget for the receipt modal with gradient and close button
class ReceiptHeaderWidget extends StatelessWidget {
  const ReceiptHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180.h,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(43.r),
          topRight: Radius.circular(43.r),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(height: 8.h),
            // Drag handle
            Container(
              width: 43.w,
              height: 3.2.h,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),

            // Title and close button
          ],
        ),
      ),
    );
  }
}
