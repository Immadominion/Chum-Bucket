import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:recess/config/theme/app_theme.dart';
import 'package:recess/screens/onboarding/widgets/terms_and_conditions_dialog.dart';

class QuestionButton extends StatelessWidget {
  const QuestionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onTap: () => _showTermsAndConditionsDialog(context),
          child: Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: AppColors.glassmorphismCard,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: AppColors.glassmorphismBorder,
                width: 1,
              ),
            ),
            child: Icon(
              Icons.question_mark,
              color: AppColors.glassmorphismText,
              size: 20.w,
            ),
          ),
        ),
      ),
    );
  }

  void _showTermsAndConditionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return const TermsAndConditionsDialog();
      },
    );
  }
}
