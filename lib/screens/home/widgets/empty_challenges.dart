import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class EmptyChallenges extends StatelessWidget {
  const EmptyChallenges({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min, // Use minimum space needed
      children: [
        Flexible(
          // Make containers flexible
          child: _buildEmptyChallengeContainer(),
        ),
        SizedBox(height: 12.h), // Reduced from 16.h
        Flexible(
          // Make containers flexible
          child: _buildEmptyChallengeContainer(),
        ),
      ],
    );
  }

  Widget _buildEmptyChallengeContainer() {
    return Container(
      width: double.infinity,
      height: 70.h, // Reduced from 80.h
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
