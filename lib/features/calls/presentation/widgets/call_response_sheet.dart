/// Answer someone's call: Back (their side), Fade (the other side) or Dare
/// (a free invitation to them). Back and Fade lock the viewer's OWN free
/// call; a Dare locks nothing.
///
/// One screen, icon-led: who called what, three actions, exactly what you
/// are locking, one button. Every refusal stops the spinner and says why,
/// beside the button; your own call never offers an answer at all.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/analytics/analytics_event.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_refusals.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/trust/data/content_policy.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Preselection never submits. A successful Back/Fade returns its resultingCall.
Future<CallResponseResult?> showCallResponseSheet({
  required BuildContext context,
  required CallFeedEntry entry,
  CallResponseKind? initialKind,
  String? note,
  AnalyticsSurface? surface,
  bool askForNotifications = true,
}) => showChumbucketWavySheet<CallResponseResult>(
  context: context,
  builder:
      (_) => CallResponseSheet(
        entry: entry,
        initialKind: initialKind,
        note: note,
        surface: surface,
        askForNotifications: askForNotifications,
      ),
);

/// The icon each answer wears, everywhere it appears.
abstract final class CallResponseIcons {
  static const back = 'add-outline';
  static const fade = 'exchange-outline';
  static const dare = 'lightning-outline';

  static String of(CallResponseKind kind) => switch (kind) {
    CallResponseKind.back => back,
    CallResponseKind.fade => fade,
    CallResponseKind.challenge => dare,
  };
}

class CallResponseSheet extends StatefulWidget {
  final CallFeedEntry entry;
  final CallResponseKind? initialKind;

  /// A note above the form (after an onboarding sign-in).
  final String? note;

  /// Where the response was made, for analytics.
  final AnalyticsSurface? surface;

  /// After a Back/Fade/Challenge, explain-then-ask for notifications
  /// (lockdown's in-context ask). Onboarding passes false: its "You're on
  /// record" step asks there.
  final bool askForNotifications;
  const CallResponseSheet({
    super.key,
    required this.entry,
    this.initialKind,
    this.note,
    this.surface,
    this.askForNotifications = true,
  });
  @override
  State<CallResponseSheet> createState() => _CallResponseSheetState();
}

class _CallResponseSheetState extends State<CallResponseSheet> {
  /// On a market that stopped taking calls only a Dare can go out, so the
  /// sheet opens on it rather than on a Lock that can't be pressed.
  late CallResponseKind _kind = switch (widget.initialKind ??
      CallResponseKind.back) {
    final kind when kind.createsOwnCall && _closed() =>
      CallResponseKind.challenge,
    final kind => kind,
  };
  final _note = TextEditingController();
  bool _showReason = false;
  CallVisibility _visibility = CallVisibility.public;
  String? _error;

  /// The server said this is the viewer's own call.
  bool _ownCall = false;

  /// The server said the viewer already has a live call on this market.
  bool _alreadyOnRecord = false;

  /// Answers the server says this viewer already sent (a second Dare).
  final Set<CallResponseKind> _answered = {};

  CallFeedEntry get _entry => widget.entry;

  Side get _side =>
      _kind == CallResponseKind.fade
          ? _entry.call.side.opposite
          : _entry.call.side;

  @override
  void initState() {
    super.initState();
    // The current price and "already on record" come from the market's
    // detail. Read it quietly; the sheet works without it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<CallsProvider>();
      if (provider.isSignedIn &&
          !_isOwn(provider) &&
          provider.marketDetail(_entry.market.id) == null) {
        unawaited(provider.loadMarketDetail(_entry.market.id));
      }
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool _isOwn(CallsProvider provider) =>
      _ownCall ||
      (provider.viewerUserId != null &&
          _entry.author.id == provider.viewerUserId);

  bool _closed() => !_entry.market.status.acceptsNewCalls;

  bool _alreadyCalled(CallsProvider provider) =>
      _alreadyOnRecord ||
      _entry.viewerHasCalled ||
      provider.marketDetail(_entry.market.id)?.viewerHasCalled == true;

  /// Back and Fade need an open market and no call of yours on it yet; any
  /// answer, once the server says it was already sent, is done.
  bool _canLock(CallResponseKind kind, CallsProvider provider) =>
      !_answered.contains(kind) &&
      (!kind.createsOwnCall || (!_closed() && !_alreadyCalled(provider)));

  void _choose(CallResponseKind kind) => setState(() {
    _kind = kind;
    _error = null;
  });

  Future<void> _submit() async {
    final provider = context.read<CallsProvider>();
    if (provider.isSubmitting) return;
    final text = _note.text.trim();
    final problem = contentPolicyProblem(
      text,
      _kind.createsOwnCall ? ContentField.thesis : ContentField.note,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _error = null);
    try {
      final result = await provider.respondToCall(
        RespondToCallInput(
          targetCallId: _entry.call.id,
          kind: _kind,
          // A Back/Fade's reason goes on the new call; a Dare's words are
          // the note the person dared reads.
          thesis: _kind.createsOwnCall && text.isNotEmpty ? text : null,
          note: !_kind.createsOwnCall && text.isNotEmpty ? text : null,
          visibility: _visibility,
        ),
        surface: widget.surface,
      );
      if (!mounted) return;
      final root = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop(result);
      if (widget.askForNotifications && root.mounted) {
        unawaited(PushRegistration.afterSocialAction(root));
      }
    } on CallsException catch (e) {
      if (!mounted) return;
      setState(() {
        switch (classifyCallRefusal(e)) {
          case CallRefusal.ownCall:
            _ownCall = true;
            _error = null;
          case CallRefusal.alreadyOnRecord:
            _alreadyOnRecord = true;
            _error = callRefusalMessage(e);
          case CallRefusal.alreadyAnswered:
            _answered.add(_kind);
            _error = callRefusalMessage(e);
          default:
            _error = callRefusalMessage(e);
        }
      });
    } catch (_) {
      // Never a spinner with no way out: whatever failed, say so.
      if (mounted) setState(() => _error = kCallUnexpectedFailure);
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<CallsProvider>(
    builder: (context, provider, _) {
      final own = provider.isSignedIn && _isOwn(provider);
      return CallJourneySheet(
        // The body already says "That's your call"; the header doesn't
        // repeat it.
        title: own ? 'On record' : 'Your move',
        busy: provider.isSubmitting,
        body:
            !provider.isSignedIn
                ? SingleChildScrollView(
                  child: CallsSignedOutView(
                    message: 'Sign in to answer. Calling is free.',
                    onSignIn: () => requestCallSignIn(context),
                  ),
                )
                : own
                ? const _OwnCallState()
                : _form(provider),
      );
    },
  );

  Widget _form(CallsProvider provider) {
    final busy = provider.isSubmitting;
    final canLock = _canLock(_kind, provider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.note != null) ...[
                  _QuietLine(widget.note!, icon: 'user-outline'),
                  const SizedBox(height: 10),
                ],
                _TheirCall(entry: _entry),
                const SizedBox(height: 16),
                _AnswerTiles(
                  entry: _entry,
                  selected: _kind,
                  enabled: {
                    for (final kind in CallResponseKind.values)
                      kind: !busy && _canLock(kind, provider),
                  },
                  onChanged: _choose,
                ),
                const SizedBox(height: 12),
                _Locking(
                  entry: _entry,
                  kind: _kind,
                  side: _side,
                  price: _currentPrice(provider),
                  closed: _closed(),
                  alreadyCalled: _alreadyCalled(provider),
                ),
                const SizedBox(height: 4),
                if (_showReason) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: CallJourneyReason(
                      controller: _note,
                      enabled: !busy,
                      autofocus: true,
                      hint:
                          _kind.createsOwnCall
                              ? 'What are you seeing?'
                              : 'Say something to @${_entry.author.handle}',
                    ),
                  ),
                  if (_kind.createsOwnCall)
                    CallJourneyVisibility(
                      value: _visibility,
                      onChanged:
                          busy
                              ? null
                              : (value) => setState(() => _visibility = value),
                    ),
                ] else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('response-add-reason'),
                      onPressed:
                          busy
                              ? null
                              : () => setState(() => _showReason = true),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        foregroundColor: AppColors.pinkInk,
                      ),
                      icon: const BasilIcon(
                        'edit-outline',
                        size: 18,
                        color: AppColors.pinkInk,
                      ),
                      label: Text(
                        _kind.createsOwnCall ? 'Add a reason' : 'Add a note',
                        style: callJourneyHeading(
                          context,
                          13,
                        ).copyWith(color: AppColors.pinkInk),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                CallInlineError(_error!),
                const SizedBox(height: 10),
              ],
              CallJourneyButton(
                key: const ValueKey('response-lock'),
                label:
                    _kind == CallResponseKind.challenge
                        ? 'Send the dare'
                        : 'Lock my ${_side.wire} call',
                primary: true,
                busy: busy,
                onPressed: busy || !canLock ? null : _submit,
              ),
              const SizedBox(height: 8),
              CallFinePrint(
                _kind.createsOwnCall
                    ? 'Free · final once locked'
                    : 'Free · no money moves',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Panta's current price for the side being locked, when it is fresh.
  String? _currentPrice(CallsProvider provider) {
    if (!_kind.createsOwnCall) return null;
    final price = provider.marketDetail(_entry.market.id)?.sharePrice;
    if (price == null || !price.isUsableAt(DateTime.now())) return null;
    final side = price.priceFor(_side);
    return side == null ? null : CallsFormat.displayPrice(side);
  }
}

/// Who called what: the person, their side, the question. Nothing else.
class _TheirCall extends StatelessWidget {
  const _TheirCall({required this.entry});
  final CallFeedEntry entry;

  @override
  Widget build(BuildContext context) {
    final author = entry.author;
    return MergeSemantics(
      child: Semantics(
        label:
            '${author.displayName}, @${author.handle}, called '
            '${entry.call.side.wire} on ${entry.market.question}',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F6F7),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Initials are decorative here (the name sits beside
                    // them), so they keep their size at large text.
                    MediaQuery.withNoTextScaling(
                      child: AppAvatar(
                        initials: author.initials,
                        imageUrl: author.avatarUrl,
                        size: 36,
                        backgroundColor: AppColors.primaryContainer,
                        textColor: AppColors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        author.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: callJourneyHeading(context, 15),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SidePill(side: entry.call.side),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  entry.market.question,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: callJourneyHeading(context, 17),
                ),
                if (entry.market.venue.isDemo) ...[
                  const SizedBox(height: 8),
                  DemoVenueBadge(venue: entry.market.venue),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Back, Fade and Dare as three big icon actions.
class _AnswerTiles extends StatelessWidget {
  const _AnswerTiles({
    required this.entry,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final CallFeedEntry entry;
  final CallResponseKind selected;
  final Map<CallResponseKind, bool> enabled;
  final ValueChanged<CallResponseKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final side = entry.call.side;
    Widget tile(CallResponseKind kind) {
      final (sub, ink, fill, semantics) = switch (kind) {
        CallResponseKind.back => (
          side.wire,
          CallSideColors.ink(side),
          CallSideColors.fill(side),
          'Back: call ${side.wire} with @${entry.author.handle}',
        ),
        CallResponseKind.fade => (
          side.opposite.wire,
          CallSideColors.ink(side.opposite),
          CallSideColors.fill(side.opposite),
          'Fade: call ${side.opposite.wire} against @${entry.author.handle}',
        ),
        CallResponseKind.challenge => (
          '@${entry.author.handle}',
          AppColors.pinkInk,
          AppColors.primaryContainer,
          'Dare @${entry.author.handle}',
        ),
      };
      return Expanded(
        child: _AnswerTile(
          key: ValueKey('response-${kind.wire}'),
          icon: CallResponseIcons.of(kind),
          label: kind.label,
          sub: sub,
          ink: ink,
          fill: fill,
          semanticsLabel: semantics,
          selected: selected == kind,
          onTap: enabled[kind] == true ? () => onChanged(kind) : null,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile(CallResponseKind.back),
        const SizedBox(width: 8),
        tile(CallResponseKind.fade),
        const SizedBox(width: 8),
        tile(CallResponseKind.challenge),
      ],
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.sub,
    required this.ink,
    required this.fill,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String label;
  final String sub;
  final Color ink;
  final Color fill;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback? onTap;

  static const _rule = Color(0xFFE3E5E8);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = selected ? ink : AppColors.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled || selected ? 1 : .45,
        child: Material(
          color: selected ? fill : AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? ink : _rule,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.surface : fill,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: BasilIcon(icon, size: 20, color: ink),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: callJourneyHeading(
                          context,
                          14,
                        ).copyWith(color: fg),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: callJourneyBody(11).copyWith(
                        color: selected ? ink : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Exactly what Lock will do, in one line.
class _Locking extends StatelessWidget {
  const _Locking({
    required this.entry,
    required this.kind,
    required this.side,
    required this.price,
    required this.closed,
    required this.alreadyCalled,
  });

  final CallFeedEntry entry;
  final CallResponseKind kind;
  final Side side;
  final String? price;
  final bool closed;
  final bool alreadyCalled;

  @override
  Widget build(BuildContext context) {
    final handle = '@${entry.author.handle}';
    final Widget content;
    final Color fill;
    final String spoken;
    if (kind.createsOwnCall && (closed || alreadyCalled)) {
      final why =
          alreadyCalled
              ? 'You’re already on record here'
              : '${entry.market.status.label} · dares still work';
      fill = const Color(0xFFF6F6F7);
      spoken = why;
      content = _line(
        context,
        icon: alreadyCalled ? 'check-outline' : 'lock-time-outline',
        ink: AppColors.textMuted,
        children: [Text(why, style: callJourneyBody(13))],
      );
    } else if (kind.createsOwnCall) {
      // Back and Fade each lock the viewer's OWN call, never a copy of
      // theirs: the line says whose call it is and nothing else.
      final ink = CallSideColors.ink(side);
      fill = CallSideColors.fill(side);
      spoken =
          'Your own call: ${side.wire}'
          '${price == null ? '' : ', at $price'}';
      content = _line(
        context,
        icon: 'lock-outline',
        ink: ink,
        children: [
          Text(
            'Your call',
            style: callJourneyHeading(context, 14).copyWith(color: ink),
          ),
          // On the side's own tint, the pill sits on white.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              side.wire,
              style: callJourneyHeading(context, 12).copyWith(color: ink),
            ),
          ),
          if (price != null)
            Text('at $price', style: callJourneyBody(13).copyWith(color: ink)),
        ],
      );
    } else {
      fill = AppColors.primaryContainer;
      spoken = 'A free dare to $handle. No call, no money.';
      content = _line(
        context,
        icon: CallResponseIcons.dare,
        ink: AppColors.pinkInk,
        children: [
          Text(
            'Free dare to $handle',
            style: callJourneyBody(
              13,
            ).copyWith(color: AppColors.pinkInk, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    return Semantics(
      liveRegion: true,
      label: spoken,
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('response-locking'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: content,
      ),
    );
  }

  Widget _line(
    BuildContext context, {
    required String icon,
    required Color ink,
    required List<Widget> children,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      BasilIcon(icon, size: 18, color: ink),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        ),
      ),
    ],
  );
}

/// Your own call is never answered from here: it says so, with the art.
class _OwnCallState extends StatelessWidget {
  const _OwnCallState();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('response-own-call'),
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ChumbucketStateArt(ChumbucketStateArtwork.record, size: 112),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            'That’s your call',
            textAlign: TextAlign.center,
            style: callJourneyHeading(context, 20),
          ),
        ),
        const SizedBox(height: 6),
        // One line, and it asks for nothing the one button doesn't do.
        Text(
          'Only others can back or fade it.',
          textAlign: TextAlign.center,
          style: callJourneyBody(13),
        ),
        const SizedBox(height: 18),
        CallJourneyButton(
          label: 'Got it',
          primary: true,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );
}

class _QuietLine extends StatelessWidget {
  const _QuietLine(this.text, {required this.icon});
  final String text;
  final String icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      BasilIcon(icon, size: 16, color: AppColors.textMuted),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: callJourneyBody(12))),
    ],
  );
}
