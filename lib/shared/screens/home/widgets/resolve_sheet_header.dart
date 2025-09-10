import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Header section of the resolve challenge sheet with gradient background,
/// bet amount display, and drag handle
class ResolveSheetHeader extends StatelessWidget {
  final String amountText;

  const ResolveSheetHeader({super.key, required this.amountText});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200.h,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          SizedBox(height: 24.h),
          // Bet Amount text
          Text(
            'Bet Amount',
            style: TextStyle(
              fontSize: 14.sp,
              color: Colors.white.withOpacity(0.5),
              fontWeight: FontWeight.w700,
            ),
          ),
          // Amount
          Text(
            '$amountText SOL',
            style: TextStyle(
              fontSize: 40.sp,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          // Add some bottom padding to ensure proper spacing
          SizedBox(height: 20.h),
        ],
      ),
    );
  }
}
