/// Back and Fade review the viewer's own free call. Challenge sends an invitation.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

/// Preselection never submits. A successful Back/Fade returns its resultingCall.
Future<CallResponseResult?> showCallResponseSheet({
  required BuildContext context,
  required CallFeedEntry entry,
  CallResponseKind? initialKind,
}) => showChumbucketWavySheet<CallResponseResult>(
  context: context,
  builder: (_) => CallResponseSheet(entry: entry, initialKind: initialKind),
);

class CallResponseSheet extends StatefulWidget {
  final CallFeedEntry entry;
  final CallResponseKind? initialKind;
  const CallResponseSheet({super.key, required this.entry, this.initialKind});
  @override
  State<CallResponseSheet> createState() => _CallResponseSheetState();
}

class _CallResponseSheetState extends State<CallResponseSheet> {
  late CallResponseKind _kind = widget.initialKind ?? CallResponseKind.back;
  final _note = TextEditingController();
  bool _useConfidence = false;
  double _confidence = .6;
  CallVisibility _visibility = CallVisibility.public;
  String? _error;
  Side get _side =>
      _kind == CallResponseKind.fade
          ? widget.entry.call.side.opposite
          : widget.entry.call.side;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final provider = context.read<CallsProvider>();
    if (provider.isSubmitting) return;
    setState(() => _error = null);
    try {
      final result = await provider.respondToCall(
        RespondToCallInput(
          targetCallId: widget.entry.call.id,
          kind: _kind,
          confidence:
              _kind.createsOwnCall && _useConfidence ? _confidence : null,
          thesis: _note.text.trim().isEmpty ? null : _note.text.trim(),
          visibility: _visibility,
        ),
      );
      if (!mounted) return;
      final root = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop(result);
      if (root.mounted) unawaited(PushRegistration.afterSocialAction(root));
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<CallsProvider>(
    builder:
        (context, provider, _) => CallJourneySheet(
          title:
              _kind == CallResponseKind.challenge
                  ? 'Dare them to call it'
                  : '${_kind.label} this call',
          busy: provider.isSubmitting,
          body:
              !provider.isSignedIn
                  ? SingleChildScrollView(
                    child: CallsSignedOutView(
                      message:
                          'Sign in to answer. Your draft stays here. Calling is free.',
                      onSignIn: () => requestCallSignIn(context),
                    ),
                  )
                  : _form(provider),
        ),
  );

  Widget _form(CallsProvider provider) {
    final entry = widget.entry;
    final closed = !entry.market.status.acceptsNewCalls;
    final alreadyCalled =
        entry.viewerHasCalled ||
        provider.marketDetail(entry.market.id)?.viewerHasCalled == true;
    final blocked = _kind.createsOwnCall && (closed || alreadyCalled);
    final busy = provider.isSubmitting;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (entry.market.venue.isDemo)
                  const CallJourneyNote(
                    'DEMO DATA · Sample market, not a live call.',
                  ),
                CallJourneyPerson(
                  person: entry.author,
                  subtitle:
                      '@${entry.author.handle} called ${entry.call.side.wire}',
                ),
                const SizedBox(height: 12),
                Text(
                  entry.market.question,
                  style: callJourneyHeading(context, 22),
                ),
                if (entry.call.thesis?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(entry.call.thesis!, style: callJourneyBody()),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final kind in CallResponseKind.values)
                      CallJourneyChoice(
                        label: kind.label,
                        // Back locks their side, Fade the other; a challenge
                        // is an invitation and takes no side here.
                        side: switch (kind) {
                          CallResponseKind.back => entry.call.side,
                          CallResponseKind.fade => entry.call.side.opposite,
                          _ => null,
                        },
                        selected: _kind == kind,
                        onTap:
                            busy || (closed && kind.createsOwnCall)
                                ? null
                                : () => setState(() => _kind = kind),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (closed)
                  CallJourneyNote(
                    '${entry.market.status.label}. You can still send a dare, but no new call can be locked here.',
                  ),
                if (_kind.createsOwnCall) ...[
                  CallJourneySides(
                    market: entry.market,
                    side: _side,
                    onChanged:
                        busy || blocked
                            ? null
                            : (side) => setState(
                              () =>
                                  _kind =
                                      side == entry.call.side
                                          ? CallResponseKind.back
                                          : CallResponseKind.fade,
                            ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${_kind == CallResponseKind.back ? 'Backing' : 'Fading'} @${entry.author.handle} · You’re calling ${_side.wire}.',
                      style: callJourneyHeading(context, 16),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _kind == CallResponseKind.back
                        ? 'Makes your OWN call on the same side. It does not copy their position. No money involved.'
                        : 'Makes your OWN call on the opposite side. No money involved.',
                    style: callJourneyBody(12),
                  ),
                  if (alreadyCalled)
                    const CallJourneyNote(
                      'You’re already on record for this market. Your existing call can’t be changed, and a second call can’t be locked.',
                    ),
                ] else
                  const CallJourneyNote(
                    'No escrow. Nothing is locked up, nothing is staked, and no transaction is created. This sends a free dare, not a bet or a call of your own.',
                  ),
                const SizedBox(height: 16),
                Text(
                  _kind.createsOwnCall
                      ? 'Your reason (optional)'
                      : 'Your invitation (optional)',
                  style: callJourneyHeading(context, 14),
                ),
                const SizedBox(height: 8),
                CallJourneyReason(
                  controller: _note,
                  enabled: !busy,
                  hint:
                      _kind.createsOwnCall
                          ? 'What are you seeing?'
                          : 'Invite them to take a side',
                ),
                if (_kind.createsOwnCall) ...[
                  CallJourneyVisibility(
                    value: _visibility,
                    onChanged:
                        busy
                            ? null
                            : (value) => setState(() => _visibility = value),
                  ),
                  const SizedBox(height: 12),
                  CallJourneyConfidence(
                    enabled: _useConfidence,
                    confidence: _confidence,
                    onToggle:
                        busy
                            ? null
                            : (value) => setState(() => _useConfidence = value),
                    onChanged:
                        busy
                            ? null
                            : (value) => setState(() => _confidence = value),
                  ),
                ],
                const Divider(height: 32),
                CallJourneyFact(
                  'Original call locked',
                  entry.call.lockedAtUtc.toIso8601String(),
                ),
                CallJourneyFact(
                  'Closes',
                  entry.market.closesAtUtc == null
                      ? 'No close time published'
                      : CallsFormat.timestampUtc(entry.market.closesAtUtc!),
                ),
                if (entry.market.venue == MarketVenue.panta) ...[
                  CallJourneyFact(
                    'Original price',
                    entry.call.entryPrice == null
                        ? 'Price not captured'
                        : CallsFormat.sharePrice(
                          entry.call.entryPrice!.priceFor(entry.call.side),
                        ),
                  ),
                  Text(
                    'Powered by Panta. The original price belongs to their call. Your call records its own price when locked; this is not a trade quote.',
                    style: callJourneyBody(12),
                  ),
                ],
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Read the market rules',
                    style: callJourneyHeading(context, 14),
                  ),
                  children: [
                    SelectableText(
                      entry.market.rulesText,
                      style: callJourneyBody(),
                    ),
                  ],
                ),
                if (_kind.createsOwnCall)
                  const CallJourneyNote(
                    'Your side, reason and timestamp can’t be edited after locking.',
                    icon: 'lock-outline',
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
            label:
                _kind == CallResponseKind.challenge
                    ? 'Send the dare'
                    : 'Lock my ${_side.wire} call',
            primary: true,
            busy: busy,
            onPressed: busy || blocked ? null : _submit,
          ),
        ),
      ],
    );
  }
}
