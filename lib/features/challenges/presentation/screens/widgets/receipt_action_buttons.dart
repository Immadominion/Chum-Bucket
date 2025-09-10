import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';

/// Action buttons for receipt sharing using ChallengeButton and TextButton
class ReceiptActionButtons extends StatelessWidget {
  final VoidCallback onShareImage;
  final VoidCallback onSharePDF;

  const ReceiptActionButtons({
    super.key,
    required this.onShareImage,
    required this.onSharePDF,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Share as Image button using ChallengeButton
        ChallengeButton(
          createNewChallenge: onShareImage,
          label: 'Share as Image',
        ),

        // Share as PDF text button (like resolve_sheet_content.dart)
        TextButton(
          onPressed: onSharePDF,
          child: Text(
            'Share as PDF',
            style: TextStyle(
              fontSize: 17.sp,
              color: const Color(0xFFFF5A76),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
