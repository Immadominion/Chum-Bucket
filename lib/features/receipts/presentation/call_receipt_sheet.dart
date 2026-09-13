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

import 'package:chumbucket/core/analytics/analytics.dart';
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
  AnalyticsSurface surface = AnalyticsSurface.receiptSheet,
  AnalyticsRecorder? analytics,
}) {
  return showChumbucketWavySheet<void>(
    context: context,
    builder:
        (_) => CallReceiptSheet(
          receipt: receipt,
          surface: surface,
          analytics: analytics,
        ),
  );
}

class CallReceiptSheet extends StatefulWidget {
  final CallReceipt receipt;

  /// Which screen opened the sheet. §9 wants to know whether receipts are
  /// reached from the feed, a person's record or a shared link.
  final AnalyticsSurface surface;

  /// Injected in tests; production uses the ambient in-memory recorder.
  final AnalyticsRecorder? analytics;

  const CallReceiptSheet({
    super.key,
    required this.receipt,
    this.surface = AnalyticsSurface.receiptSheet,
    this.analytics,
  });

  @override
  State<CallReceiptSheet> createState() => _CallReceiptSheetState();
}

class _CallReceiptSheetState extends State<CallReceiptSheet> {
  final ScreenshotController _controller = ScreenshotController();
  bool _busy = false;

  AnalyticsRecorder get _analytics =>
      widget.analytics ?? AnalyticsRecorder.instance;

  @override
  void initState() {
    super.initState();
    // Reported once per sheet, from initState rather than build, so a rebuild
    // (the busy flag flips twice per share) cannot inflate it. `settled` is
    // recorded because an unsettled call shows the pending card, not a
    // receipt — the two are different views and must not be pooled.
    _analytics.record(
      AnalyticsEvents.receiptViewed(
        callId: widget.receipt.callId,
        settled: widget.receipt.isSettled,
        surface: widget.surface,
        outcome: widget.receipt.outcome.wire,
        venueIsDemo: widget.receipt.venueIsDemo,
      ),
    );
  }

  /// The share funnel is two events, not one: [AnalyticsEventName.shareStarted]
  /// when the sheet is asked for, [AnalyticsEventName.receiptShared] only after
  /// the platform sheet actually accepted it. A cancelled or failed share is
  /// therefore visible as a start with no completion.
  ///
  /// Neither event carries the URL or the caption. `shareCaption` contains the
  /// market question verbatim, which is free text, and the URL can carry a
  /// `?ref=` handle.
  void _recordShareStarted(AnalyticsShareChannel channel) {
    _analytics.record(
      AnalyticsEvents.shareStarted(
        linkKind: AnalyticsLinkKind.receipt,
        channel: channel,
        callId: widget.receipt.callId,
        outcome: widget.receipt.outcome.wire,
        surface: widget.surface,
      ),
    );
  }

  void _recordShareCompleted(AnalyticsShareChannel channel) {
    _analytics.record(
      AnalyticsEvents.receiptShared(
        callId: widget.receipt.callId,
        channel: channel,
        outcome: widget.receipt.outcome.wire,
      ),
    );
  }

  Future<void> _shareImage() async {
    if (_busy) return;
    setState(() => _busy = true);
    _recordShareStarted(AnalyticsShareChannel.image);
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
      _recordShareCompleted(AnalyticsShareChannel.image);
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
    _recordShareStarted(AnalyticsShareChannel.link);
    try {
      await SharePlus.instance.share(
        ShareParams(text: widget.receipt.shareCaption),
      );
      _recordShareCompleted(AnalyticsShareChannel.link);
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
              // Flexible so a large accessibility text scale shortens the
              // label instead of overflowing the button off the screen edge —
              // at the default scale nothing about the layout changes.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
