import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenges_tab.dart';

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
                    icon: const PhosphorIcon(PhosphorIconsRegular.caretLeft),
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'Your challenges',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
