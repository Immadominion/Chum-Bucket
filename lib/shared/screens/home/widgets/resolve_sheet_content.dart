import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';

/// Bottom section of the resolve challenge sheet containing the challenge text
/// and action buttons for completing or failing the challenge
class ResolveSheetContent extends StatelessWidget {
  final Map<String, dynamic> challenge;
  final bool isPending;
  final Function(Map<String, dynamic>, bool) onMarkCompleted;

  const ResolveSheetContent({
    super.key,
    required this.challenge,
    required this.isPending,
    required this.onMarkCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 12.h),
        child: Column(
          children: [
            // Challenge description
            Flexible(
              flex: 3,
              child: Center(
                child: Container(
                  constraints: BoxConstraints(maxWidth: 350.w, minHeight: 60.h),
                  child: Text(
                    (challenge['description'] as String?) ??
                        (challenge['title'] as String?) ??
                        'Create challenge first',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Spacer to push buttons to bottom
            const Spacer(),

            // Action buttons
            if (isPending) ...[
              // Challenge completed button
              ChallengeButton(
                createNewChallenge: () => onMarkCompleted(challenge, true),
                label: 'Challenge Completed',
              ),
              SizedBox(height: 8.h),
              // Failed to complete button
              TextButton(
                onPressed: () => onMarkCompleted(challenge, false),
                child: Text(
                  'Failed to complete',
                  style: TextStyle(
                    fontSize: 17.sp,
                    color: const Color(0xFFFF5A76),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ] else ...[
              // Completed state
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PhosphorIcon(
                      PhosphorIconsRegular.checkCircle,
                      color: Colors.green.shade600,
                      size: 20.w,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Challenge completed',
                      style: TextStyle(
                        fontSize: 16.sp,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 8.h), // Bottom padding
          ],
        ),
      ),
    );
  }
}
