import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/config/theme/app_theme.dart';

class TermsAndConditionsDialog extends StatelessWidget {
  const TermsAndConditionsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      shadowColor: Theme.of(context).colorScheme.onSurface,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.glassmorphismCard,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: AppColors.glassmorphismBorder, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Terms and Conditions (Short and Simple)",
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.glassmorphismText,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    "Chum Bucket Terms and Conditions",
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.glassmorphismText,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    "By using Chum Bucket, you agree to these rules:\n"
                    "• You're responsible for your bets and challenges. We're just the platform.\n\n"
                    "• Challenges are made with friends using email or wallet addresses. Both must agree to release funds, or one party can sign if agreed.\n\n"
                    "• We take a 1% fee on bets (max \$10). Fees go to a public wallet—50% for the team, 50% for airdrops to Solana users.\n\n"
                    "• No illegal challenges allowed. We can remove content if needed.\n\n"
                    "• We're not responsible for lost funds or disputes. Use at your own risk.\n\n"
                    "• We can update these terms anytime. Check back often.",
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.glassmorphismSecondaryText,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 24.h),
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 24.w,
                          vertical: 12.h,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.buttonBackground,
                          borderRadius: BorderRadius.circular(18.r),
                          border: Border.all(
                            color: AppColors.glassmorphismBorder,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          "I Understand",
                          style: TextStyle(
                            color: AppColors.buttonText,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
