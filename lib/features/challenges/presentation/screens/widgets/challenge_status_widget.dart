import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:chumbucket/shared/models/models.dart';
import '../models/challenge_status_data.dart';

/// Widget that displays the challenge status animation and text
class ChallengeStatusWidget extends StatelessWidget {
  final ChallengeStatus status;
  final ChallengeStatusData statusData;
  final String? errorMessage;

  const ChallengeStatusWidget({
    super.key,
    required this.status,
    required this.statusData,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.transparent,
          height: 200.h,
          width: 200.h,
          child: _buildAnimation(context),
        ),
        const SizedBox(height: 32),
        Text(
          statusData.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: statusData.color,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          statusData.message,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        if (status == ChallengeStatus.failed && errorMessage != null) ...[
          const SizedBox(height: 16),
          Text(
            errorMessage!,
            style: TextStyle(color: Colors.red.shade400),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildAnimation(BuildContext context) {
    // Use Lottie animations based on status
    switch (status) {
      case ChallengeStatus.accepted:
      case ChallengeStatus.funded:
      case ChallengeStatus.completed:
        // Use the success.json animation for completed challenges
        return Lottie.asset(
          'assets/animations/lottie/success.json',
          width: 200.w,
          height: 200.w,
          fit: BoxFit.contain,
          repeat: false,
        );
      case ChallengeStatus.failed:
      case ChallengeStatus.cancelled:
        return _buildStatusAnimation(Icons.cancel_outlined, Colors.red, true);
      case ChallengeStatus.pending:
        return Lottie.asset(
          'assets/animations/lottie/loading.json',
          width: 200.w,
          height: 200.w,
          fit: BoxFit.contain,
          repeat: false,
        );
      case ChallengeStatus.expired:
        return _buildStatusAnimation(Icons.access_time, Colors.orange, false);
    }
  }

  Widget _buildStatusAnimation(IconData icon, Color color, bool animated) {
    return Center(
      child:
          animated
              ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                builder: (context, value, child) {
                  // Ensure opacity is always between 0.0 and 1.0
                  final clampedValue = value.clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: 0.8 + (clampedValue * 0.2),
                    child: Opacity(
                      opacity: clampedValue,
                      child: Icon(icon, size: 120, color: color),
                    ),
                  );
                },
                curve: Curves.elasticOut,
              )
              : Icon(icon, size: 120, color: color),
    );
  }
}
