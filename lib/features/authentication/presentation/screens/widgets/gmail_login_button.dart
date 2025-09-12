import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/features/authentication/presentation/screens/email_input_screen.dart';

class EmailLoginButton extends StatelessWidget {
  const EmailLoginButton({super.key});

  Future<void> _handleGmailLogin(BuildContext context) async {
    try {
      // Implement Gmail login logic here (if any before email input)

      // Navigate to email input screen
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const EmailInputScreen()));
    } catch (error) {
      // Handle login errors
      SnackBarUtils.showError(
        context,
        title: 'Login Error',
        subtitle: error.toString(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleGmailLogin(context),
      child: Container(
        width: double.infinity, // Full width instead of fixed 330.w
        constraints: BoxConstraints(maxWidth: 330.w, minWidth: 280.w),
        padding: EdgeInsets.symmetric(vertical: 12.h),
        margin: EdgeInsets.symmetric(horizontal: 6.h),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: AppColors.glassmorphismBorder, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Continue with Email",
              style: TextStyle(
                color: AppColors.buttonText,
                fontSize: 18.sp, // Reduced from 20.sp for smaller screens
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
