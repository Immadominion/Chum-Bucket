/// Share flow for a resolved receipt.
///
/// Reuses the existing pipeline verbatim — `Screenshot(controller:)` wrapping
/// the content, `capture()` to PNG, write to the temp directory,
/// `Share.shareXFiles` (`receipt_modal.dart:15`). That path is content-agnostic,
/// so the only thing that changes is the widget inside the [Screenshot].
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/widgets/call_receipt_card.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

Future<void> showCallReceiptSheet({
  required BuildContext context,
  required CallReceipt receipt,
}) {
  return showChumbucketWavySheet<void>(
    context: context,
    builder: (_) => CallReceiptSheet(receipt: receipt),
  );
}

class CallReceiptSheet extends StatefulWidget {
  final CallReceipt receipt;

  const CallReceiptSheet({super.key, required this.receipt});

  @override
  State<CallReceiptSheet> createState() => _CallReceiptSheetState();
}

class _CallReceiptSheetState extends State<CallReceiptSheet> {
  final ScreenshotController _controller = ScreenshotController();
  bool _busy = false;

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _controller.capture();
      if (bytes == null) {
        throw const FileSystemException('Nothing was captured');
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/call_receipt_${widget.receipt.callId}_'
          '${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: widget.receipt.shareCaption,
          subject: 'Chumbucket receipt',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Couldn\'t share that',
        subtitle: 'The receipt image could not be created. Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLink() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SharePlus.instance.share(
        ShareParams(text: widget.receipt.shareCaption),
      );
    } catch (e) {
      if (!mounted) return;
      SnackBarUtils.showError(
        context,
        title: 'Couldn\'t share that',
        subtitle: 'The link could not be shared. Try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    return ChumbucketWavySheet(
      title: 'Receipt',
      subtitle: '@${receipt.personHandle} · ${receipt.sideLabel}',
      height: MediaQuery.sizeOf(context).height * 0.86,
      body:
          receipt.isSettled
              ? _settled(receipt)
              : const CallsStateView(
                icon: 'clock-outline',
                title: 'Not settled yet',
                message:
                    'A receipt only exists once the venue has published a '
                    'result. Until then this call is simply pending.',
              ),
    );
  }

  Widget _settled(CallReceipt receipt) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 10.h),
            child: Center(
              child: Screenshot(
                controller: _controller,
                child: CallReceiptCard(receipt: receipt),
              ),
            ),
          ),
        ),
        if (receipt.isVoid)
          Padding(
            padding: EdgeInsets.only(bottom: 6.h),
            child: CallsNotice(
              icon: 'info-circle-outline',
              color: AppColors.textSecondary,
              message:
                  'The market was cancelled, so this is void — it counts as '
                  'neither a win nor a loss.',
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 18.h),
          child: Row(
            children: [
              Expanded(
                child: _ReceiptAction(
                  icon: 'share-outline',
                  label: 'Share image',
                  primary: true,
                  busy: _busy,
                  onTap: _shareImage,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _ReceiptAction(
                  icon: 'copy-outline',
                  label: 'Share link',
                  busy: _busy,
                  onTap: _shareLink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReceiptAction extends StatelessWidget {
  final String icon;
  final String label;
  final bool primary;
  final bool busy;
  final VoidCallback onTap;

  const _ReceiptAction({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : AppColors.textPrimary;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          decoration: BoxDecoration(
            color: primary ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: primary ? AppColors.primary : AppColors.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BasilIcon(icon, size: 16.w, color: foreground),
              SizedBox(width: 8.w),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
