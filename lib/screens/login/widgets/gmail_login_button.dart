import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:recess/config/theme/app_theme.dart';
import 'package:recess/screens/login/email_input_screen.dart';

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Login failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleGmailLogin(context),
      child: Container(
        width: 330.w, // Fixed width for consistent button size
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
                fontSize: 20.sp,
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
