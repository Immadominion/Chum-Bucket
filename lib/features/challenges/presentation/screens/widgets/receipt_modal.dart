import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'receipt_header_widget.dart';
import 'receipt_content_widget.dart';
import 'receipt_action_buttons.dart';

/// Receipt modal following the same design pattern as other bottom sheets
class ReceiptModal extends StatelessWidget {
  final Challenge? challenge;
  final ChallengeStatus status;
  final ScreenshotController screenshotController;

  const ReceiptModal({
    super.key,
    required this.challenge,
    required this.status,
    required this.screenshotController,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate responsive height
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.9;
    final minHeight = 450.h;
    final preferredHeight = 650.h;
    final finalHeight = preferredHeight.clamp(minHeight, maxHeight);

    return Container(
      height: finalHeight,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(43.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Header section
          const ReceiptHeaderWidget(),

          // Receipt content
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
            child: Column(
              children: [
                // Receipt image with wave stacking effect
                Expanded(
                  child: Screenshot(
                    controller: screenshotController,
                    child: ReceiptContentWidget(
                      challenge: challenge,
                      status: status,
                    ),
                  ),
                ),

                SizedBox(height: 24.h),

                // Action buttons
                ReceiptActionButtons(
                  onShareImage: () => _shareAsImage(context),
                  onSharePDF: () => _shareAsPDF(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareAsImage(BuildContext context) async {
    try {
      final imageBytes = await screenshotController.capture();
      if (imageBytes == null) return;

      final directory = await getTemporaryDirectory();
      final imagePath =
          '${directory.path}/challenge_receipt_${DateTime.now().millisecondsSinceEpoch}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(imageBytes);

      await Share.shareXFiles([
        XFile(imageFile.path),
      ], text: 'Challenge Receipt');

      Navigator.pop(context);
    } catch (e) {
      Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sharing receipt: $e')));
      }
    }
  }

  Future<void> _shareAsPDF(BuildContext context) async {
    try {
      final imageBytes = await screenshotController.capture();
      if (imageBytes == null) return;

      final image = pw.MemoryImage(imageBytes);
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          },
        ),
      );

      final directory = await getTemporaryDirectory();
      final pdfPath =
          '${directory.path}/challenge_receipt_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final pdfFile = File(pdfPath);
      await pdfFile.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(pdfFile.path)], text: 'Challenge Receipt');

      Navigator.pop(context);
    } catch (e) {
      Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating PDF: $e')));
      }
    }
  }
}
