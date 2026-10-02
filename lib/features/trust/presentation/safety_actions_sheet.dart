/// Report, mute and block — reachable from a call (the "More" button on the
/// call screen) and from a person's page.
///
/// Every action is server-side and session-keyed: the BFF decides who is
/// asking. Blocking hides both people from each other and stops them
/// responding to or following each other; muting hides someone from you only.
/// Neither person is told.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/features/trust/data/trust_models.dart';
import 'package:chumbucket/features/trust/data/trust_repository.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Who and what the actions are about.
class SafetyTarget {
  const SafetyTarget({
    required this.personId,
    required this.handle,
    required this.displayName,
    this.callId,
    this.hasThesis = false,
  });

  final String personId;
  final String handle;
  final String displayName;
  final String? callId;
  final bool hasThesis;
}

/// Opens the actions sheet, or the sign-in prompt when signed out.
Future<void> showSafetyActions(BuildContext context, SafetyTarget target) {
  final calls = context.read<CallsProvider?>();
  if (calls != null && !calls.isSignedIn) {
    requestCallSignIn(context);
    return Future.value();
  }
  final repository = TrustRepository.of(context);
  return showChumbucketWavySheet<void>(
    context: context,
    builder: (_) => SafetyActionsSheet(target: target, repository: repository),
  );
}

class SafetyActionsSheet extends StatefulWidget {
  const SafetyActionsSheet({
    super.key,
    required this.target,
    required this.repository,
  });

  final SafetyTarget target;
  final TrustRepository repository;

  @override
  State<SafetyActionsSheet> createState() => _SafetyActionsSheetState();
}

class _SafetyActionsSheetState extends State<SafetyActionsSheet> {
  RelationLists? _lists;
  String? _error;
  bool _busy = false;

  SafetyTarget get _t => widget.target;
  bool get _blocked =>
      _lists?.blocked.any((p) => p.userId == _t.personId) ?? false;
  bool get _muted => _lists?.muted.any((p) => p.userId == _t.personId) ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lists = await widget.repository.lists();
      if (mounted) setState(() => _lists = lists);
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _report(ReportSubject subject) async {
    final navigator = Navigator.of(context);
    final host = navigator.context;
    navigator.pop();
    await showChumbucketWavySheet<void>(
      context: host,
      builder:
          (_) => ReportSheet(
            subject: subject,
            target: _t,
            repository: widget.repository,
          ),
    );
  }

  Future<void> _toggleMute() async {
    final muting = !_muted;
    await _run(
      () => widget.repository.setMuted(_t.personId, muted: muting),
      muting
          ? 'Muted @${_t.handle}. Their calls and notifications are hidden from you.'
          : 'Unmuted @${_t.handle}.',
    );
  }

  Future<void> _toggleBlock() async {
    final blocking = !_blocked;
    if (blocking) {
      final ok = await showDialog<bool>(
        context: context,
        builder:
            (dialog) => AlertDialog(
              title: Text('Block @${_t.handle}?'),
              content: const Text(
                'You won\'t see each other\'s calls, and neither of you can '
                'respond to or follow the other. Any follow between you ends. '
                'They aren\'t told. You can unblock in Settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialog).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialog).pop(true),
                  style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  child: const Text('Block'),
                ),
              ],
            ),
      );
      if (ok != true || !mounted) return;
    }
    await _run(
      () => widget.repository.setBlocked(_t.personId, blocked: blocking),
      blocking ? 'Blocked @${_t.handle}.' : 'Unblocked @${_t.handle}.',
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      final calls = context.read<CallsProvider?>();
      final inbox = context.read<NotificationsProvider?>();
      Navigator.of(context).pop();
      messenger?.showSnackBar(SnackBar(content: Text(done)));
      // The server filters them out now; show that straight away.
      calls?.loadFeed(force: true);
      calls?.loadInvitations(force: true);
      inbox?.refreshUnreadCount();
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final loading = _lists == null && _error == null;
    return ChumbucketWavySheet(
      title: '@${_t.handle}',
      subtitle: _t.displayName,
      canDismiss: !_busy,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_t.callId != null)
              _ActionRow(
                icon: 'info-triangle-outline',
                title: 'Report this call',
                onTap: _busy ? null : () => _report(ReportSubject.call),
              ),
            if (_t.callId != null && _t.hasThesis)
              _ActionRow(
                icon: 'comment-outline',
                title: 'Report the thesis',
                onTap: _busy ? null : () => _report(ReportSubject.thesis),
              ),
            _ActionRow(
              icon: 'user-outline',
              title: 'Report @${_t.handle}',
              onTap: _busy ? null : () => _report(ReportSubject.person),
            ),
            const SizedBox(height: 8),
            _ActionRow(
              icon: _muted ? 'volume-up-outline' : 'volume-off-outline',
              title: _muted ? 'Unmute @${_t.handle}' : 'Mute @${_t.handle}',
              detail: 'Hides their calls and notifications from you only.',
              onTap: loading || _busy ? null : _toggleMute,
            ),
            _ActionRow(
              icon: 'user-block-outline',
              title: _blocked ? 'Unblock @${_t.handle}' : 'Block @${_t.handle}',
              detail:
                  'Hides you from each other and stops replies and follows.',
              danger: !_blocked,
              onTap: loading || _busy ? null : _toggleBlock,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: styles.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ChumbucketTextAction(
              label: 'Close',
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pick a reason, optionally add a line, send.
class ReportSheet extends StatefulWidget {
  const ReportSheet({
    super.key,
    required this.subject,
    required this.target,
    required this.repository,
  });

  final ReportSubject subject;
  final SafetyTarget target;
  final TrustRepository repository;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _reason;
  final _details = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = widget.target;
      final receipt = await widget.repository.report(
        subject: widget.subject,
        reason: reason,
        callId: widget.subject == ReportSubject.person ? null : t.callId,
        personRef: widget.subject == ReportSubject.person ? t.personId : null,
        details: _details.text,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            receipt.alreadyReported
                ? 'You already reported ${widget.subject.noun}. We\'re reviewing it.'
                : 'Thanks. We\'ll review ${widget.subject.noun}.',
          ),
        ),
      );
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    return ChumbucketWavySheet(
      title: 'Report ${widget.subject.noun}',
      subtitle:
          'Reports are private. @${widget.target.handle} isn\'t told who reported.',
      canDismiss: !_busy,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (!_busy) setState(() => _reason = value);
              },
              child: Column(
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      value: reason,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.primary,
                      title: Text(reason.label, style: styles.titleSmall),
                      subtitle: Text(reason.hint, style: styles.bodySmall),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              enabled: !_busy,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Anything we should know? (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: styles.bodySmall?.copyWith(color: AppColors.error),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ChumbucketPrimaryButton(
              label: 'Send report',
              busy: _busy,
              busyLabel: 'Sending…',
              onPressed: _reason == null ? null : _send,
            ),
            const SizedBox(height: 4),
            ChumbucketTextAction(
              label: 'Cancel',
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.detail,
    this.danger = false,
  });

  final String icon;
  final String title;
  final String? detail;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final styles = AppTextStyles.textTheme;
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          minVerticalPadding: 12,
          leading: BasilIcon(icon, color: color),
          title: Text(title, style: styles.titleSmall?.copyWith(color: color)),
          subtitle:
              detail == null
                  ? null
                  : Text(
                    detail!,
                    style: styles.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
        ),
      ),
    );
  }
}
