/// The thesis as a thread: the author's timestamped follow-ups under a call's
/// original reason.
///
/// The original reason is drawn by the call screen and never by this widget,
/// so nothing here can be mistaken for an edit of it. Each update carries its
/// distance from the lock ("2h after locking") as well as its exact UTC time,
/// so a reader always knows what was said before and after the facts moved.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class ThesisThread extends StatelessWidget {
  final CallDetail detail;

  /// The viewer is the call's author.
  final bool isAuthor;

  /// Opens the compose sheet; null hides the action.
  final VoidCallback? onAddUpdate;

  const ThesisThread({
    super.key,
    required this.detail,
    required this.isAuthor,
    this.onAddUpdate,
  });

  /// "just after locking", "40m after locking", "2h after locking",
  /// "3d after locking".
  static String sinceLock(DateTime lockedAt, DateTime at) {
    final delta = at.toUtc().difference(lockedAt.toUtc());
    if (delta.inMinutes < 1) return 'just after locking';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m after locking';
    if (delta.inHours < 48) return '${delta.inHours}h after locking';
    return '${delta.inDays}d after locking';
  }

  /// [sinceLock], plus "after the result" for an update posted once the venue
  /// had resolved the market, so hindsight never reads as part of the call.
  static String caption(DateTime lockedAt, DateTime? resolvedAt, DateTime at) {
    final since = sinceLock(lockedAt, at);
    if (resolvedAt != null && !at.isBefore(resolvedAt)) {
      return '$since · after the result';
    }
    return since;
  }

  @override
  Widget build(BuildContext context) {
    final updates = detail.updates;
    final lockedAt = detail.entry.call.lockedAtUtc;
    final resolvedAt = detail.entry.result?.resolvedAtUtc;
    final canAdd =
        isAuthor &&
        onAddUpdate != null &&
        detail.updatesAvailable &&
        updates.length < kMaxThesisUpdatesPerCall;
    if (updates.isEmpty && !canAdd) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 18, bottom: 14),
          child: Divider(height: 1, color: AppColors.outlineVariant),
        ),
        Semantics(
          header: true,
          child: Text(
            updates.isEmpty
                ? 'Thesis updates'
                : 'Thesis updates · ${updates.length}',
            style: callJourneyHeading(context, 15),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Added after the call locked. The original reason above never changes.',
          style: callJourneyBody(12),
        ),
        const SizedBox(height: 12),
        for (final update in updates)
          _UpdateTile(
            update: update,
            caption: caption(lockedAt, resolvedAt, update.createdAtUtc),
          ),
        if (canAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                foregroundColor: _pinkInk,
              ),
              onPressed: onAddUpdate,
              icon: const BasilIcon('add-outline', size: 18, color: _pinkInk),
              label: Text(
                updates.isEmpty ? 'Add an update' : 'Add another update',
                style: callJourneyHeading(
                  context,
                  13,
                ).copyWith(color: _pinkInk),
              ),
            ),
          )
        else if (isAuthor && updates.length >= kMaxThesisUpdatesPerCall)
          Text(
            'This call has the most updates one call can carry.',
            style: callJourneyBody(12),
          ),
      ],
    );
  }
}

class _UpdateTile extends StatelessWidget {
  final ThesisUpdate update;
  final String caption;
  const _UpdateTile({required this.update, required this.caption});

  @override
  Widget build(BuildContext context) {
    final exact = CallsFormat.timestampUtc(update.createdAtUtc);
    return Semantics(
      container: true,
      label: 'Update, $caption, $exact. ${update.body}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The thread's spine, as a thesis thread draws it.
              Container(
                width: 3,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$caption · $exact', style: callJourneyBody(12)),
                    const SizedBox(height: 4),
                    SelectableText(
                      update.body,
                      style: callJourneyBody(
                        14,
                      ).copyWith(color: AppColors.textPrimary, height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compose one update. Returns the posted update, or null if dismissed.
Future<ThesisUpdate?> showThesisUpdateSheet({
  required BuildContext context,
  required CallDetail detail,
}) => showChumbucketWavySheet<ThesisUpdate>(
  context: context,
  builder: (_) => ThesisUpdateSheet(detail: detail),
);

class ThesisUpdateSheet extends StatefulWidget {
  final CallDetail detail;
  const ThesisUpdateSheet({super.key, required this.detail});

  @override
  State<ThesisUpdateSheet> createState() => _ThesisUpdateSheetState();
}

class _ThesisUpdateSheetState extends State<ThesisUpdateSheet> {
  final _body = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final provider = context.read<CallsProvider>();
    if (provider.isSubmitting) return;
    setState(() => _error = null);
    try {
      final update = await provider.appendThesisUpdate(
        widget.detail.entry.call.id,
        _body.text,
      );
      if (mounted) Navigator.of(context).pop(update);
    } on CallsException catch (e) {
      // The draft stays in the field; only the reason is added.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // An answer the app could not read (e.g. a malformed reply). The
      // server may already hold the update, so say so instead of inviting a
      // duplicate, and re-read the call so the thread shows what is true.
      if (!mounted) return;
      setState(
        () =>
            _error =
                'We couldn’t confirm that update. Check the thread before '
                'posting it again.',
      );
      unawaited(
        provider.loadCall(
          widget.detail.entry.call.id,
          force: true,
          reportOpen: false,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.detail.entry;
    return Consumer<CallsProvider>(
      builder: (context, provider, _) {
        final busy = provider.isSubmitting;
        return CallJourneySheet(
          title: 'Update your thesis',
          busy: busy,
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        entry.market.question,
                        style: callJourneyHeading(context, 18),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your ${entry.call.side.wire} call, locked '
                        '${CallsFormat.timestampUtc(entry.call.lockedAtUtc)}',
                        style: callJourneyBody(12),
                      ),
                      if (entry.call.thesis?.isNotEmpty == true) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Original reason',
                          style: callJourneyHeading(context, 13),
                        ),
                        const SizedBox(height: 4),
                        Text(entry.call.thesis!, style: callJourneyBody()),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'What changed?',
                        style: callJourneyHeading(context, 14),
                      ),
                      const SizedBox(height: 8),
                      CallJourneyReason(
                        controller: _body,
                        enabled: !busy,
                        hint: 'New evidence, a level you’re watching, a doubt…',
                      ),
                      const CallJourneyNote(
                        'Posted with today’s time, after your call. Your side and '
                        'original reason stay exactly as locked, and an update '
                        'can’t be edited or deleted.',
                        icon: 'lock-outline',
                        quiet: true,
                      ),
                      if (_error != null)
                        Semantics(
                          liveRegion: true,
                          child: CallJourneyNote(_error!, error: true),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: CallJourneyButton(
                  label: 'Post update',
                  primary: true,
                  busy: busy,
                  onPressed: busy || _body.text.trim().isEmpty ? null : _post,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The prototype's pink ink for text actions (#B8173B, 6.4:1 on white).
const _pinkInk = Color(0xFFB8173B);
