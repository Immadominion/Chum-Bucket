/// Back / Fade / Challenge.
///
/// The copy here is load-bearing, because these three are easy to mistake for
/// things they are not:
///
/// * **Back** is not copy-trading. It creates *your own* immutable call on the
///   same side, at today's price, under your name.
/// * **Fade** is the same thing on the opposite side.
/// * **Challenge** creates no call for you at all. It is a targeted invitation
///   for the other person to go on record — with no escrow, no stake and no
///   transaction of any kind.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/challenge_button.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

/// Opens the answer sheet. Resolves to what the response produced, or null.
Future<CallResponseResult?> showCallResponseSheet({
  required BuildContext context,
  required CallFeedEntry entry,
  CallResponseKind? initialKind,
}) {
  return showChumbucketWavySheet<CallResponseResult>(
    context: context,
    builder: (_) => CallResponseSheet(entry: entry, initialKind: initialKind),
  );
}

class CallResponseSheet extends StatefulWidget {
  final CallFeedEntry entry;
  final CallResponseKind? initialKind;

  const CallResponseSheet({super.key, required this.entry, this.initialKind});

  @override
  State<CallResponseSheet> createState() => _CallResponseSheetState();
}

class _CallResponseSheetState extends State<CallResponseSheet> {
  late CallResponseKind _kind = widget.initialKind ?? CallResponseKind.back;
  final TextEditingController _note = TextEditingController();
  bool _useConfidence = false;
  double _confidence = 0.6;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Side get _resultingSide =>
      _kind == CallResponseKind.fade
          ? widget.entry.call.side.opposite
          : widget.entry.call.side;

  Future<void> _submit() async {
    final provider = context.read<CallsProvider>();
    final note = _note.text.trim();
    setState(() => _error = null);
    try {
      final result = await provider.respondToCall(
        RespondToCallInput(
          targetCallId: widget.entry.call.id,
          kind: _kind,
          confidence:
              _kind == CallResponseKind.challenge || !_useConfidence
                  ? null
                  : _confidence,
          thesis: note.isEmpty ? null : note,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on CallsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return ChumbucketWavySheet(
      title: 'Answer ${entry.author.displayName}',
      subtitle: entry.market.question,
      height: MediaQuery.sizeOf(context).height * 0.84,
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          if (!provider.isSignedIn) {
            return const CallsSignedOutView(
              message:
                  'Sign in to answer. Backing, fading and challenging are all '
                  'free — there is no wallet in this loop.',
            );
          }
          final marketClosed = !entry.market.status.acceptsNewCalls;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
                  children: [
                    _TheirCall(entry: entry),
                    SizedBox(height: 16.h),
                    for (final kind in CallResponseKind.values) ...[
                      _KindOption(
                        kind: kind,
                        entry: entry,
                        selected: _kind == kind,
                        // Back and Fade mint a new call, so they need an open
                        // market. A challenge is just an invitation.
                        disabled: marketClosed && kind.createsOwnCall,
                        onTap: () => setState(() => _kind = kind),
                      ),
                      SizedBox(height: 10.h),
                    ],
                    if (marketClosed)
                      CallsNotice(
                        icon: 'lock-time-outline',
                        color: AppColors.warning,
                        message:
                            '${entry.market.status.label}. You can still send a '
                            'challenge, but no new call can be locked here.',
                      ),
                    SizedBox(height: 6.h),
                    if (_kind.createsOwnCall) ...[
                      _ResultBanner(
                        side: _resultingSide,
                        label: entry.market.labelFor(_resultingSide),
                      ),
                      SizedBox(height: 14.h),
                      _ConfidenceToggle(
                        enabled: _useConfidence,
                        confidence: _confidence,
                        onToggle: (v) => setState(() => _useConfidence = v),
                        onChanged: (v) => setState(() => _confidence = v),
                      ),
                    ] else
                      _NoEscrowBanner(person: entry.author.displayName),
                    SizedBox(height: 14.h),
                    TextField(
                      controller: _note,
                      maxLines: 3,
                      maxLength: kThesisMaxLength,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(kThesisMaxLength),
                      ],
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            _kind == CallResponseKind.challenge
                                ? 'Say what you\'re daring them to call (optional)'
                                : 'Your reasoning (optional)',
                        hintStyle: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13.sp,
                        ),
                        filled: true,
                        fillColor: AppColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: const BorderSide(
                            color: AppColors.outlineVariant,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      SizedBox(height: 10.h),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 13.sp,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 18.h),
                child: ChallengeButton(
                  label: switch (_kind) {
                    CallResponseKind.back => 'Lock my call on the same side',
                    CallResponseKind.fade => 'Lock my call on the other side',
                    CallResponseKind.challenge => 'Send the challenge',
                  },
                  blurRadius: false,
                  enabled:
                      !provider.isSubmitting &&
                      !(marketClosed && _kind.createsOwnCall),
                  isLoading: provider.isSubmitting,
                  createNewChallenge: _submit,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TheirCall extends StatelessWidget {
  final CallFeedEntry entry;

  const _TheirCall({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Their call',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SideChip(
                side: entry.call.side,
                label: entry.market.labelFor(entry.call.side),
              ),
              if (entry.call.entryPrice != null)
                Text(
                  'Called at ${CallsFormat.sharePrice(entry.call.entryPrice!.priceFor(entry.call.side))} · ${SharePriceSnapshot.attribution}',
                ),
              if (entry.call.entryProbability != null)
                CallBadge(
                  label:
                      'Locked at ${CallsFormat.probability(entry.call.entryProbability)}',
                  color: AppColors.textSecondary,
                  icon: 'lock-outline',
                ),
              CallBadge(
                label: CallsFormat.relative(entry.call.createdAtUtc),
                color: AppColors.textSecondary,
                icon: 'clock-outline',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KindOption extends StatelessWidget {
  final CallResponseKind kind;
  final CallFeedEntry entry;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _KindOption({
    required this.kind,
    required this.entry,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  String get _explanation => switch (kind) {
    CallResponseKind.back =>
      'Makes your OWN call on the same side, at today\'s price. It does not '
          'copy their position and there is nothing to fund.',
    CallResponseKind.fade =>
      'Makes your OWN call on the opposite side, at today\'s price. Free, and '
          'locked the moment you send it.',
    CallResponseKind.challenge =>
      'Dares ${entry.author.displayName} to go on record. No call is created '
          'for you, and nothing is escrowed.',
  };

  String get _icon => switch (kind) {
    CallResponseKind.back => 'arrow-up-outline',
    CallResponseKind.fade => 'exchange-outline',
    CallResponseKind.challenge => 'fire-outline',
  };

  @override
  Widget build(BuildContext context) {
    final color = disabled ? AppColors.textTertiary : AppColors.textPrimary;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: !disabled,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(16.r),
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color:
                  selected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.outlineVariant,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BasilIcon(
                  _icon,
                  size: 18.w,
                  color: selected ? AppColors.primary : color,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind.label,
                        style: TextStyle(
                          color: selected ? AppColors.primary : color,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        _explanation,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.sp,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final Side side;
  final String label;

  const _ResultBanner({required this.side, required this.label});

  @override
  Widget build(BuildContext context) {
    // Wrap rather than Row: the venue's own outcome label can be long, and it
    // must never be clipped — it is what the responder is going on record for.
    return Wrap(
      spacing: 8.w,
      runSpacing: 6.h,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'You will be on record for:',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
        ),
        SideChip(side: side, label: label),
      ],
    );
  }
}

class _NoEscrowBanner extends StatelessWidget {
  final String person;

  const _NoEscrowBanner({required this.person});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          BasilIcon(
            'info-circle-outline',
            size: 16.w,
            color: AppColors.textSecondary,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              'No escrow. Nothing is locked up, nothing is staked, and no '
              'transaction is created. $person just gets an invitation to call it.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.sp,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfidenceToggle extends StatelessWidget {
  final bool enabled;
  final double confidence;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onChanged;

  const _ConfidenceToggle({
    required this.enabled,
    required this.confidence,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Add your confidence (optional)',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Switch(
              value: enabled,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
              onChanged: onToggle,
            ),
          ],
        ),
        if (enabled)
          Slider(
            value: confidence,
            min: 0.05,
            max: 0.99,
            divisions: 94,
            activeColor: AppColors.primary,
            label: CallsFormat.probability(confidence),
            onChanged: onChanged,
          ),
      ],
    );
  }
}
