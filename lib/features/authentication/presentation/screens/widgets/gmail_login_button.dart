import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
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
    return ChallengeButton(
      createNewChallenge: () => _handleGmailLogin(context),
      label: 'Continue with email',
      blurRadius: false,
    );
  }
}
