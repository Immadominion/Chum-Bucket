import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/trust/data/legal_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
                    "The short version",
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.glassmorphismText,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    "Chumbucket Terms (draft, pending legal review)",
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.glassmorphismText,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    "• You must be 18 or older.\n\n"
                    "• Calls are free, public and permanent once locked. Back, Fade and Dare never move money.\n\n"
                    "• Funded positions are optional, use real USDC on Panta (Solana mainnet), and you can lose what you put in. You sign every transaction in your own wallet; we never hold your funds or keys.\n\n"
                    "• No harassment, hate, scams or links in what you post. You can report, block and mute.\n\n"
                    "• You can export or delete your account any time in Settings.",
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: AppColors.glassmorphismSecondaryText,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed:
                            () => openExternalLink(context, LegalLinks.terms),
                        child: const Text('Read the Terms'),
                      ),
                      TextButton(
                        onPressed:
                            () => openExternalLink(context, LegalLinks.privacy),
                        child: const Text('Privacy Policy'),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
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
