import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';



class EmptyChallenges extends StatelessWidget {
  const EmptyChallenges({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildEmptyChallengeContainer(),
        SizedBox(height: 16.h),
        _buildEmptyChallengeContainer(),
      ],
    );
  }

  Widget _buildEmptyChallengeContainer() {
    return Container(
      width: double.infinity,
      height: 80.h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF5F5F5), // Lighter gray
            const Color(0xFFE8E8E8), // Slightly darker gray
          ],
        ),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.transparent, // No visible border
        ),
      ),
    );
  }
}
