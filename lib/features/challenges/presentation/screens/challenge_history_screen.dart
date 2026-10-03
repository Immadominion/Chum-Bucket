import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_tab.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Settings → History → Escrow challenges: the signed-in wallet's earlier SOL
/// escrow challenges. Read-only, except that the witness can still settle an
/// open one (the home shell owns that flow: [onMarkChallengeCompleted]).
class ChallengeHistoryScreen extends StatelessWidget {
  final int refreshKey;
  final Future<void> Function(Map<String, dynamic>, bool)
  onMarkChallengeCompleted;

  const ChallengeHistoryScreen({
    super.key,
    required this.refreshKey,
    required this.onMarkChallengeCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const BasilIcon('caret-left-outline'),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(
                      'Escrow challenges',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                'From before calls. New ones can’t be started. An open one '
                'still holds SOL until its witness settles it with their '
                'wallet.',
                style: AppTextStyles.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: ChallengesTab(
                  refreshKey: refreshKey,
                  onMarkChallengeCompleted: onMarkChallengeCompleted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
