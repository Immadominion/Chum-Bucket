import 'dart:io';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:flutter/material.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
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
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Challenge receipt',
    height: MediaQuery.sizeOf(context).height * .85,
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Center(
        child: Screenshot(
          controller: screenshotController,
          child: SizedBox(
            width: double.infinity,
            child: ReceiptContentWidget(challenge: challenge, status: status),
          ),
        ),
      ),
    ),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: ReceiptActionButtons(
        onShareImage: () => _shareAsImage(context),
        onSharePDF: () => _shareAsPDF(context),
      ),
    ),
  );

  Future<void> _shareAsImage(BuildContext context) async {
    try {
      final imageBytes = await screenshotController.capture();
      if (imageBytes == null) return;

      final directory = await getTemporaryDirectory();
      final imagePath =
          '${directory.path}/challenge_receipt_${DateTime.now().millisecondsSinceEpoch}.png';
      final imageFile = File(imagePath);
      await imageFile.writeAsBytes(imageBytes);

      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(imageFile.path)], text: 'Challenge Receipt'),
      );

      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        SnackBarUtils.showError(
          context,
          title: 'Error',
          subtitle: 'Error sharing receipt: $e',
        );
        Navigator.pop(context);
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

      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(pdfFile.path)], text: 'Challenge Receipt'),
      );

      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        SnackBarUtils.showError(
          context,
          title: 'Error',
          subtitle: 'Error creating PDF: $e',
        );
        Navigator.pop(context);
      }
    }
  }
}
