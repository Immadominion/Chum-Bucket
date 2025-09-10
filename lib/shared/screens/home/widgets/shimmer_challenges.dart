import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ShimmerChallenges extends StatefulWidget {
  const ShimmerChallenges({super.key});

  @override
  State<ShimmerChallenges> createState() => _ShimmerChallengesState();
}

class _ShimmerChallengesState extends State<ShimmerChallenges>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.ease),
    );
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26.r),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.2), offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          _buildShimmerChallengeCard(),
          SizedBox(height: 16.h),
          _buildShimmerChallengeCard(),
          SizedBox(height: 16.h),
          _buildShimmerChallengeCard(),
        ],
      ),
    );
  }

  Widget _buildShimmerChallengeCard() {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          height: 60.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            gradient: LinearGradient(
              colors: [
                Colors.grey.shade300,
                Colors.grey.shade100,
                Colors.grey.shade300,
              ],
              begin: Alignment(_animation.value - 1, 0.0),
              end: Alignment(_animation.value, 0.0),
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}
