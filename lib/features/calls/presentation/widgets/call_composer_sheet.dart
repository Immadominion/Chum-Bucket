/// Free-call review. The provider remains responsible for locking it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

Future<CallFeedEntry?> showCallComposer({
  required BuildContext context,
  required VenueMarket market,
  MarketSnapshot? snapshot,
  SharePriceSnapshot? sharePrice,
  Side? initialSide,
  String? parentCallId,
  String? headline,
}) => showChumbucketWavySheet<CallFeedEntry>(
  context: context,
  builder:
      (_) => CallComposerSheet(
        market: market,
        snapshot: snapshot,
        sharePrice: sharePrice,
        initialSide: initialSide,
        parentCallId: parentCallId,
        headline: headline,
      ),
);

class CallComposerSheet extends StatefulWidget {
  final VenueMarket market;
  final MarketSnapshot? snapshot;
  final SharePriceSnapshot? sharePrice;
  final Side? initialSide;
  final String? parentCallId;
  final String? headline;
  const CallComposerSheet({
    super.key,
    required this.market,
    this.snapshot,
    this.sharePrice,
    this.initialSide,
    this.parentCallId,
    this.headline,
  });
  @override
  State<CallComposerSheet> createState() => _CallComposerSheetState();
}

class _CallComposerSheetState extends State<CallComposerSheet> {
  late Side? _side = widget.initialSide;
  final _thesis = TextEditingController();
  bool _useConfidence = false;
  double _confidence = .6;
  CallVisibility _visibility = CallVisibility.public;
  String? _error;
  @override
  void dispose() {
    _thesis.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final provider = context.read<CallsProvider>();
    if (provider.isSubmitting) return;
    if (widget.market.venue == MarketVenue.panta &&
        !(widget.sharePrice?.isUsableAt(DateTime.now()) ?? false)) {
      setState(
        () =>
            _error =
                'Panta prices are missing or stale. Refresh this market before calling.',
      );
      return;
    }
    final side = _side;
    if (side == null) {
      setState(() => _error = 'Pick a side first.');
      return;
    }
    setState(() => _error = null);
    try {
      final entry = await provider.createCall(
        CreateCallInput(
          marketId: widget.market.id,
          side: side,
          confidence: _useConfidence ? _confidence : null,
          thesis: _thesis.text.trim().isEmpty ? null : _thesis.text.trim(),
          visibility: _visibility,
          snapshotId: widget.snapshot?.id,
          parentCallId: widget.parentCallId,
        ),
      );
      if (mounted) Navigator.of(context).pop(entry);
    } on CallsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<CallsProvider>(
    builder:
        (context, provider, _) => CallJourneySheet(
          title: widget.headline ?? 'Make your call',
          busy: provider.isSubmitting,
          body:
              !provider.isSignedIn
                  ? SingleChildScrollView(
                    child: CallsSignedOutView(
                      onSignIn: () => requestCallSignIn(context),
                    ),
                  )
                  : _form(provider),
        ),
  );

  Widget _form(CallsProvider provider) {
    final market = widget.market;
    final open = market.status.acceptsNewCalls;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (market.venue.isDemo)
                  const CallJourneyNote(
                    'DEMO DATA · Sample market, not a live call.',
                  ),
                Text(
                  'Your opinion. On the record.',
                  style: callJourneyBody(12),
                ),
                const SizedBox(height: 12),
                Text(market.question, style: callJourneyHeading(context, 22)),
                const SizedBox(height: 16),
                if (!open) ...[
                  Text(
                    market.status.label,
                    style: callJourneyHeading(context, 18),
                  ),
                  const CallJourneyNote(
                    'This market is not accepting new calls. Your draft is kept here; nothing changes a call you already locked.',
                  ),
                ],
                CallJourneySides(
                  market: market,
                  side: _side,
                  onChanged:
                      open && !provider.isSubmitting
                          ? (side) => setState(() => _side = side)
                          : null,
                ),
                const SizedBox(height: 10),
                Text(
                  _side == null
                      ? 'Choose your YES or NO.'
                      : 'You’re calling ${_side!.wire}. No money involved.',
                  style: callJourneyBody(),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your reason (optional)',
                  style: callJourneyHeading(context, 14),
                ),
                const SizedBox(height: 8),
                CallJourneyReason(
                  controller: _thesis,
                  enabled: !provider.isSubmitting,
                ),
                CallJourneyVisibility(
                  value: _visibility,
                  onChanged:
                      provider.isSubmitting
                          ? null
                          : (value) => setState(() => _visibility = value),
                ),
                const SizedBox(height: 12),
                CallJourneyConfidence(
                  enabled: _useConfidence,
                  confidence: _confidence,
                  onToggle:
                      provider.isSubmitting
                          ? null
                          : (value) => setState(() => _useConfidence = value),
                  onChanged:
                      provider.isSubmitting
                          ? null
                          : (value) => setState(() => _confidence = value),
                ),
                const Divider(height: 32),
                CallJourneyFact(
                  'Closes',
                  market.closesAtUtc == null
                      ? 'No close time published'
                      : CallsFormat.timestampUtc(market.closesAtUtc!),
                ),
                Text(
                  market.venue == MarketVenue.panta
                      ? '${CallsFormat.nativePrices(widget.sharePrice)} · ${SharePriceSnapshot.attribution}'
                          '${widget.sharePrice == null ? '' : ' · Observed ${CallsFormat.timestampUtc(widget.sharePrice!.observedAtUtc)}'} · Indicative, not a trade quote'
                      : widget.snapshot == null
                      ? 'No venue price published — your call locks without one.'
                      : 'Venue price: Yes ${CallsFormat.probability(widget.snapshot!.yesProbability)} · No ${CallsFormat.probability(widget.snapshot!.noProbability)} · ${CallsFormat.dataAge(widget.snapshot!.ageAt(DateTime.now()))}',
                  style: callJourneyBody(12),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Read the market rules',
                    style: callJourneyHeading(context, 14),
                  ),
                  children: [
                    SelectableText(market.rulesText, style: callJourneyBody()),
                    if (market.resolutionSource != null)
                      CallJourneyFact(
                        'Resolution source',
                        market.resolutionSource!,
                      ),
                  ],
                ),
                const CallJourneyNote(
                  'Your side, reason and timestamp can’t be edited after locking.',
                  icon: 'lock-outline',
                ),
                Text(
                  'This is a free call. No money, no wallet, nothing to fund.',
                  style: callJourneyBody(12),
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
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: CallJourneyButton(
              label:
                  _side == null
                      ? 'Lock my call'
                      : 'Lock my ${_side!.wire} call',
              primary: true,
              busy: provider.isSubmitting,
              onPressed:
                  _side == null || provider.isSubmitting ? null : _submit,
            ),
          ),
      ],
    );
  }
}

// Presentation helpers local to the call journey; shared app primitives stay intact.
TextStyle callJourneyHeading(BuildContext context, double size) =>
    AppTextStyles.button(
      Theme.of(context).colorScheme,
    ).copyWith(fontSize: size, color: AppColors.textPrimary, height: 1.25);
TextStyle callJourneyBody([double size = 14]) => AppTextStyles.caption(
  const ColorScheme.light(),
).copyWith(fontSize: size, height: 1.5, color: AppColors.textSecondary);

class CallJourneySheet extends StatelessWidget {
  final String title;
  final Widget body;
  final bool busy;
  const CallJourneySheet({
    super.key,
    required this.title,
    required this.body,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) {
    // Use the existing header slot for dark, dynamically sized brand type.
    final width = (MediaQuery.sizeOf(context).width - 84.w).clamp(
      100.0,
      double.infinity,
    );
    final style = callJourneyHeading(context, 22);
    final painter = TextPainter(
      text: TextSpan(text: title, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width - 56);
    final headerHeight = (painter.height < 48 ? 48.0 : painter.height) + 76.h;
    painter.dispose();
    return PopScope(
      canPop: !busy,
      child: ChumbucketWavySheet(
        title: '',
        height: MediaQuery.sizeOf(context).height * .88,
        headerHeight: headerHeight / 1.h,
        headerLeading: SizedBox(
          width: width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: style)),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Close',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: busy ? null : () => Navigator.of(context).maybePop(),
                icon: const BasilIcon(
                  'cross-outline',
                  size: 22,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        body: DefaultTextStyle(style: callJourneyBody(), child: body),
      ),
    );
  }
}

class CallJourneyButton extends StatelessWidget {
  final String label;
  final String? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool busy;
  const CallJourneyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient:
          primary
              ? const LinearGradient(
                colors: [AppColors.lightPrimary, AppColors.primary],
              )
              : null,
      color: primary ? null : AppColors.surface,
      border: primary ? null : Border.all(color: AppColors.outlineVariant),
    ),
    child: TextButton(
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) ...[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
          ] else if (icon != null) ...[
            BasilIcon(icon!, size: 20, color: AppColors.textPrimary),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              busy ? 'Please wait…' : label,
              textAlign: TextAlign.center,
              style: callJourneyHeading(context, 14),
            ),
          ),
        ],
      ),
    ),
  );
}

class CallJourneyNote extends StatelessWidget {
  final String text;
  final String icon;
  final bool error;
  const CallJourneyNote(
    this.text, {
    super.key,
    this.icon = 'info-circle-outline',
    this.error = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? AppColors.errorContainer : AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BasilIcon(
          icon,
          size: 20,
          color:
              error ? AppColors.onErrorContainer : AppColors.onPrimaryContainer,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: callJourneyBody(12).copyWith(
              color:
                  error
                      ? AppColors.onErrorContainer
                      : AppColors.onPrimaryContainer,
            ),
          ),
        ),
      ],
    ),
  );
}

class CallJourneyFact extends StatelessWidget {
  final String label;
  final String value;
  const CallJourneyFact(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Text(label, style: callJourneyBody(12));
        final content = Text(
          value,
          style: callJourneyBody(12).copyWith(color: AppColors.textPrimary),
        );
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(12) > 18) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 4), content],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 112, child: heading),
            const SizedBox(width: 12),
            Expanded(child: content),
          ],
        );
      },
    ),
  );
}

class CallJourneyPerson extends StatelessWidget {
  final Person person;
  final String? subtitle;
  final VoidCallback? onTap;
  const CallJourneyPerson({
    super.key,
    required this.person,
    this.subtitle,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            AppAvatar(
              initials: person.initials,
              imageUrl: person.avatarUrl,
              size: 44,
              backgroundColor: AppColors.primaryContainer,
              textColor: AppColors.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.displayName,
                    style: callJourneyHeading(context, 16),
                  ),
                  Text(
                    subtitle ?? '@${person.handle}',
                    style: callJourneyBody(12),
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

class CallJourneyChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const CallJourneyChoice({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        backgroundColor:
            selected ? AppColors.primaryContainer : AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.outlineVariant,
          width: selected ? 2 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: callJourneyHeading(context, 14),
      ),
    ),
  );
}

class CallJourneySides extends StatelessWidget {
  final VenueMarket market;
  final Side? side;
  final ValueChanged<Side>? onChanged;
  const CallJourneySides({
    super.key,
    required this.market,
    required this.side,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          for (final option in Side.values) ...[
            if (option != Side.values.first) const SizedBox(width: 8),
            Expanded(
              child: CallJourneyChoice(
                label: option.wire,
                selected: side == option,
                onTap: onChanged == null ? null : () => onChanged!(option),
              ),
            ),
          ],
        ],
      ),
      for (final option in market.outcomes)
        if (option.label.toUpperCase() != option.side.wire)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(option.label, style: callJourneyBody(12)),
            ),
          ),
    ],
  );
}

class CallJourneyReason extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  const CallJourneyReason({
    super.key,
    required this.controller,
    this.enabled = true,
    this.hint = 'What are you seeing?',
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    maxLines: 3,
    maxLength: kThesisMaxLength,
    inputFormatters: [LengthLimitingTextInputFormatter(kThesisMaxLength)],
    textCapitalization: TextCapitalization.sentences,
    style: callJourneyBody().copyWith(color: AppColors.textPrimary),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: callJourneyBody(),
      counterStyle: callJourneyBody(12),
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
  );
}

class CallJourneyVisibility extends StatelessWidget {
  final CallVisibility value;
  final ValueChanged<CallVisibility>? onChanged;
  const CallJourneyVisibility({super.key, required this.value, this.onChanged});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Who can see it', style: callJourneyHeading(context, 14)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in CallVisibility.values)
            CallJourneyChoice(
              label: option.label,
              selected: value == option,
              onTap: onChanged == null ? null : () => onChanged!(option),
            ),
        ],
      ),
    ],
  );
}

class CallJourneyConfidence extends StatelessWidget {
  final bool enabled;
  final double confidence;
  final ValueChanged<bool>? onToggle;
  final ValueChanged<double>? onChanged;
  const CallJourneyConfidence({
    super.key,
    required this.enabled,
    required this.confidence,
    this.onToggle,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Add your confidence (optional)',
          style: callJourneyHeading(context, 14),
        ),
        subtitle: Text(
          'Self-reported, separate from venue prices.',
          style: callJourneyBody(12),
        ),
        value: enabled,
        onChanged: onToggle,
        activeTrackColor: AppColors.primary,
      ),
      if (enabled) ...[
        Text(
          CallsFormat.probability(confidence),
          style: callJourneyHeading(context, 18),
        ),
        Slider(
          value: confidence,
          min: .05,
          max: .99,
          divisions: 94,
          activeColor: AppColors.primary,
          label: CallsFormat.probability(confidence),
          onChanged: onChanged,
        ),
      ],
    ],
  );
}
