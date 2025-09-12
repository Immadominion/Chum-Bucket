import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ChallengeButton extends StatelessWidget {
  final VoidCallback createNewChallenge;
  final String? label; // optional custom label
  final bool enabled; // allow disabling
  final bool isLoading; // optional loading state
  final bool hasGradient; // optional gradient background
  final bool blurRadius; // optional no blur radius

  const ChallengeButton({
    super.key,
    required this.createNewChallenge,
    this.label,
    this.enabled = true,
    this.isLoading = false,
    this.hasGradient = true,
    this.blurRadius = true,
  });

  @override
  Widget build(BuildContext context) {
    final buttonChild =
        isLoading
            ? SizedBox(
              width: 20.w,
              height: 20.w,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
            : Text(
              label ?? 'Challenge a new friend',
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.r),
        color:
            hasGradient ? null : Theme.of(context).colorScheme.primaryContainer,
        gradient:
            hasGradient
                ? const LinearGradient(
                  colors: [Color(0xFFFF5A76), Color(0xFFFF3355)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
                : null,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withAlpha(75),
            blurRadius: blurRadius ? 8 : 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (enabled && !isLoading) ? createNewChallenge : null,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          padding: EdgeInsets.symmetric(vertical: 14.h),
        ),
        child: buttonChild,
      ),
    );
  }
}
