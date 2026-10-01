/// Share flow for a resolved receipt.
///
/// Reuses the existing pipeline verbatim — `Screenshot(controller:)` wrapping
/// the content, `capture()` to PNG, write to the temp directory,
/// `Share.shareXFiles` (`receipt_modal.dart:15`). That path is content-agnostic,
/// so the only thing that changes is the widget inside the [Screenshot].
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/widgets/call_receipt_card.dart';
import 'package:chumbucket/shared/utils/snackbar_utils.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

Future<void> showCallReceiptSheet({
  required BuildContext context,
  required CallReceipt receipt,
  CallFeedEntry? entry,
  AnalyticsSurface surface = AnalyticsSurface.receiptSheet,
  AnalyticsRecorder? analytics,
}) {
  // Older entry points can supply their already-authorized cache context.
  final provider = context.read<CallsProvider?>();
  var original = entry?.call.id == receipt.callId ? entry : null;
  original ??= provider?.callDetail(receipt.callId)?.entry;
  if (original == null && provider != null) {
    for (final candidate in provider.feed) {
      if (candidate.call.id == receipt.callId) {
        original = candidate;
        break;
      }
    }
  }
  return showChumbucketWavySheet<void>(
    context: context,
    builder:
        (_) => CallReceiptSheet(
          receipt: receipt,
          entry: original,
          surface: surface,
          analytics: analytics,
        ),
  );
}

class CallReceiptSheet extends StatefulWidget {
  final CallReceipt receipt;
  final CallFeedEntry? entry;

  /// Which screen opened the sheet. §9 wants to know whether receipts are
  /// reached from the feed, a person's record or a shared link.
  final AnalyticsSurface surface;

  /// Injected in tests; production uses the ambient in-memory recorder.
  final AnalyticsRecorder? analytics;

  const CallReceiptSheet({
    super.key,
    required this.receipt,
    this.entry,
    this.surface = AnalyticsSurface.receiptSheet,
    this.analytics,
  });

  @override
  State<CallReceiptSheet> createState() => _CallReceiptSheetState();
}

class _CallReceiptSheetState extends State<CallReceiptSheet> {
  final ScreenshotController _controller = ScreenshotController();
  bool _busy = false;

  CallFeedEntry? get _entry =>
      widget.entry?.call.id == widget.receipt.callId ? widget.entry : null;
  bool get _public => _entry?.call.visibility == CallVisibility.public;
  String get _linkCaption =>
      _public
          ? widget.receipt.shareCaption
          : 'View this Chumbucket call.'
              '${widget.receipt.venueIsDemo ? ' [DEMO DATA — not a real market result]' : ''} ${widget.receipt.shareUrl}';

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
    if (_busy || _entry == null) return;
    // A followers-only image leaves its audience. Ask before capturing anything.
    if (!_public) {
      final disclose = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Share outside your followers?'),
              content: const Text(
                'This image includes the author, question, reason and result. Anyone receiving it can view or forward it, even without access to the call. Share a link to keep access controlled.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep it private'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Export image'),
                ),
              ],
            ),
      );
      if (disclose != true || !mounted) return;
    }
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
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: widget.receipt.shareCaption,
          subject: 'Chumbucket receipt',
        ),
      );
      if (result.status == ShareResultStatus.success) {
        _recordShareCompleted(AnalyticsShareChannel.image);
      }
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
      final result = await SharePlus.instance.share(
        ShareParams(text: _linkCaption),
      );
      if (result.status == ShareResultStatus.success) {
        _recordShareCompleted(AnalyticsShareChannel.link);
      }
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
    return CallJourneySheet(
      title: receipt.isSettled ? 'Your receipt' : 'On record',
      busy: _busy,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Screenshot(
                      controller: _controller,
                      child: CallReceiptCard(receipt: receipt, entry: _entry),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!receipt.isSettled)
                    const CallJourneyNote(
                      'This is your locked call, not a settled receipt. The venue has not published a result.',
                      icon: 'clock-outline',
                    ),
                  if (receipt.isVoid)
                    const CallJourneyNote(
                      'The market was cancelled, so this is void — it counts as neither a win nor a loss.',
                    ),
                  if (!_public)
                    CallJourneyNote(
                      _entry == null
                          ? 'Share a link. Image export is unavailable until this call’s visibility can be verified.'
                          : 'Followers-only call. Share a link to preserve access controls. Exporting an image discloses the content outside that audience.',
                      icon: 'lock-outline',
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final link = CallJourneyButton(
                  label: 'Share link',
                  icon: 'share-outline',
                  primary: !_public,
                  busy: _busy,
                  onPressed: _busy ? null : _shareLink,
                );
                final image = CallJourneyButton(
                  label: 'Share image',
                  icon: 'document-outline',
                  primary: _public,
                  busy: _busy,
                  onPressed: _busy || _entry == null ? null : _shareImage,
                );
                final actions = _public ? [image, link] : [link, image];
                if (MediaQuery.textScalerOf(context).scale(14) > 20 ||
                    constraints.maxWidth < 300) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      actions[0],
                      const SizedBox(height: 8),
                      actions[1],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: actions[0]),
                    const SizedBox(width: 8),
                    Expanded(child: actions[1]),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
