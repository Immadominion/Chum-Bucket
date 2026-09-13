/// The composer: pick a side, optionally state confidence, optionally write a
/// thesis, lock it.
///
/// Three things are deliberately not here: an amount field, a wallet prompt,
/// and the crowd's split. The venue's own price IS shown, attributed and aged,
/// because that is the number the call gets stamped with — but how other
/// Chumbucket users called it stays hidden until this call is locked.
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

/// Opens the composer. Resolves to the locked call, or null if dismissed.
Future<CallFeedEntry?> showCallComposer({
  required BuildContext context,
  required VenueMarket market,
  MarketSnapshot? snapshot,
  Side? initialSide,
  String? parentCallId,
  String? headline,
}) {
  return showChumbucketWavySheet<CallFeedEntry>(
    context: context,
    builder:
        (_) => CallComposerSheet(
          market: market,
          snapshot: snapshot,
          initialSide: initialSide,
          parentCallId: parentCallId,
          headline: headline,
        ),
  );
}

class CallComposerSheet extends StatefulWidget {
  final VenueMarket market;
  final MarketSnapshot? snapshot;
  final Side? initialSide;
  final String? parentCallId;
  final String? headline;

  const CallComposerSheet({
    super.key,
    required this.market,
    this.snapshot,
    this.initialSide,
    this.parentCallId,
    this.headline,
  });

  @override
  State<CallComposerSheet> createState() => _CallComposerSheetState();
}

class _CallComposerSheetState extends State<CallComposerSheet> {
  late Side? _side = widget.initialSide;
  final TextEditingController _thesis = TextEditingController();
  bool _useConfidence = false;
  double _confidence = 0.6;
  CallVisibility _visibility = CallVisibility.public;
  String? _error;

  @override
  void dispose() {
    _thesis.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final side = _side;
    if (side == null) {
      setState(() => _error = 'Pick a side first.');
      return;
    }
    final provider = context.read<CallsProvider>();
    final thesis = _thesis.text.trim();
    setState(() => _error = null);
    try {
      final entry = await provider.createCall(
        CreateCallInput(
          marketId: widget.market.id,
          side: side,
          confidence: _useConfidence ? _confidence : null,
          thesis: thesis.isEmpty ? null : thesis,
          visibility: _visibility,
          snapshotId: widget.snapshot?.id,
          parentCallId: widget.parentCallId,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(entry);
    } on CallsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final market = widget.market;
    return ChumbucketWavySheet(
      title: widget.headline ?? 'Go on record',
      subtitle: market.question,
      height: MediaQuery.sizeOf(context).height * 0.82,
      body: Consumer<CallsProvider>(
        builder: (context, provider, _) {
          if (!provider.isSignedIn) {
            return const CallsSignedOutView();
          }
          if (!market.status.acceptsNewCalls) {
            return CallsStateView(
              icon: 'lock-time-outline',
              accent: AppColors.warning,
              title: market.status.label,
              message:
                  'This market is not accepting new calls. Nothing you do here '
                  'changes a call you already locked.',
            );
          }
          return _form(context, provider);
        },
      ),
    );
  }

  Widget _form(BuildContext context, CallsProvider provider) {
    final market = widget.market;
    final snapshot = widget.snapshot;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
            children: [
              if (market.venue.isDemo)
                Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: CallsNotice.demoData(),
                ),
              _label('Your call'),
              SizedBox(height: 8.h),
              Row(
                children: [
                  for (final outcome in market.outcomes) ...[
                    Expanded(
                      child: SideChip(
                        side: outcome.side,
                        label: outcome.label,
                        selected: _side == outcome.side,
                        onTap: () => setState(() => _side = outcome.side),
                      ),
                    ),
                    if (outcome != market.outcomes.last) SizedBox(width: 10.w),
                  ],
                ],
              ),
              SizedBox(height: 8.h),
              // The venue's price, attributed and aged. This is what the call
              // gets stamped with — it is NOT how the crowd here called it.
              Text(
                snapshot == null
                    ? 'No venue price published — your call locks without one.'
                    : 'Venue price: Yes ${CallsFormat.probability(snapshot.yesProbability)} · '
                        'No ${CallsFormat.probability(snapshot.noProbability)} · '
                        '${CallsFormat.dataAge(snapshot.ageAt(DateTime.now()))}',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12.sp,
                  height: 1.35,
                ),
              ),
              SizedBox(height: 20.h),

              _OptionalSection(
                title: 'How sure are you?',
                subtitle: 'Optional. Yours, self-reported — nobody else\'s number.',
                enabled: _useConfidence,
                onChanged: (v) => setState(() => _useConfidence = v),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      CallsFormat.probability(_confidence),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Slider(
                      value: _confidence,
                      min: 0.05,
                      max: 0.99,
                      divisions: 94,
                      activeColor: AppColors.primary,
                      label: CallsFormat.probability(_confidence),
                      onChanged: (v) => setState(() => _confidence = v),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16.h),
              _label('Why? (optional)'),
              SizedBox(height: 8.h),
              TextField(
                controller: _thesis,
                maxLines: 4,
                maxLength: kThesisMaxLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kThesisMaxLength),
                ],
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'One or two lines. You can\'t edit this later.',
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
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),

              _label('Who can see it'),
              SizedBox(height: 8.h),
              Row(
                children: [
                  for (final option in CallVisibility.values) ...[
                    Expanded(
                      child: _VisibilityChip(
                        option: option,
                        selected: _visibility == option,
                        onTap: () => setState(() => _visibility = option),
                      ),
                    ),
                    if (option != CallVisibility.values.last)
                      SizedBox(width: 10.w),
                  ],
                ],
              ),

              SizedBox(height: 16.h),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(14.r),
                ),
                child: Text(
                  'This is a free call. No money, no wallet, nothing to fund. '
                  'Once you lock it, the side and the timestamp can never change.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                ),
              ),

              if (_error != null) ...[
                SizedBox(height: 12.h),
                Text(
                  _error!,
                  style: TextStyle(color: AppColors.error, fontSize: 13.sp),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 18.h),
          child: ChallengeButton(
            label: 'Lock my call',
            blurRadius: false,
            enabled: _side != null && !provider.isSubmitting,
            isLoading: provider.isSubmitting,
            createNewChallenge: _submit,
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color: AppColors.textPrimary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _OptionalSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Widget child;

  const _OptionalSection({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: enabled,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.primary,
              onChanged: onChanged,
            ),
          ],
        ),
        if (enabled) child,
      ],
    );
  }
}

class _VisibilityChip extends StatelessWidget {
  final CallVisibility option;
  final bool selected;
  final VoidCallback onTap;

  const _VisibilityChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          decoration: BoxDecoration(
            color:
                selected
                    ? AppColors.primary.withValues(alpha: 0.10)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.outlineVariant,
            ),
          ),
          child: Text(
            option.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
