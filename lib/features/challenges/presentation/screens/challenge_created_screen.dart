import 'dart:ui';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:screenshot/screenshot.dart';
import 'widgets/challenge_status_widget.dart';
import 'widgets/receipt_modal.dart';
import 'utils/challenge_status_helper.dart';

class ChallengeStateScreen extends StatefulWidget {
  final ChallengeStatus status;
  final String? errorMessage;
  final VoidCallback onDone;
  final Challenge? challenge;

  const ChallengeStateScreen({
    super.key,
    required this.status,
    this.errorMessage,
    required this.onDone,
    this.challenge,
  });

  @override
  State<ChallengeStateScreen> createState() => _ChallengeStateScreenState();
}

class _ChallengeStateScreenState extends State<ChallengeStateScreen> {
  final screenshotController = ScreenshotController();

  @override
  Widget build(BuildContext context) {
    final statusData = ChallengeStatusHelper.getStatusData(widget.status);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Challenge Status Animation and Text
            ChallengeStatusWidget(
              status: widget.status,
              statusData: statusData,
              errorMessage: widget.errorMessage,
            ),

            const SizedBox(height: 30),

            // Action Buttons
            Row(
              children: [
                // Show receipt button for successful challenges
                if (widget.status == ChallengeStatus.accepted ||
                    widget.status == ChallengeStatus.funded) ...[
                  Flexible(
                    child: ChallengeButton(
                      createNewChallenge: () => _showReceiptModal(context),
                      label: 'Share Receipt',
                      hasGradient: false,
                      blurRadius: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                Flexible(
                  child: ChallengeButton(
                    createNewChallenge:
                        () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
                    label: 'Done',
                    blurRadius: false,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showReceiptModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.5),
      elevation: 0,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 3.0, sigmaY: 3.0),
          child: SafeArea(
            child: ReceiptModal(
              challenge: widget.challenge,
              status: widget.status,
              screenshotController: screenshotController,
            ),
          ),
        );
      },
    );
  }
}
