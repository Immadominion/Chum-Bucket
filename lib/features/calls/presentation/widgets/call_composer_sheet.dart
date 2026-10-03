/// Free-call review. The provider remains responsible for locking it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/analytics/analytics_event.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/features/panta_trading/presentation/panta_market_link.dart';

Future<CallFeedEntry?> showCallComposer({
  required BuildContext context,
  required VenueMarket market,
  MarketSnapshot? snapshot,
  SharePriceSnapshot? sharePrice,
  Side? initialSide,
  String? parentCallId,
  String? headline,
  CallComposerDraft? initialDraft,
  ValueChanged<CallComposerDraft>? onSignInRequired,
  Future<SharePriceSnapshot?> Function()? refreshPrice,
  VoidCallback? onAlreadyCalled,
  String? note,
  AnalyticsSurface? surface,
  bool askForNotifications = true,
  bool compact = false,
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
        initialDraft: initialDraft,
        onSignInRequired: onSignInRequired,
        refreshPrice: refreshPrice,
        onAlreadyCalled: onAlreadyCalled,
        note: note,
        surface: surface,
        askForNotifications: askForNotifications,
        compact: compact,
      ),
);

/// What the composer holds before it is locked: kept on the phone when the
/// person must sign in first, and handed back to reopen the composer after.
/// Never locked on its own.
class CallComposerDraft {
  const CallComposerDraft({
    required this.marketId,
    required this.side,
    this.thesis,
    this.visibility = CallVisibility.public,
    this.confidence,
  });

  final String marketId;
  final Side side;
  final String? thesis;
  final CallVisibility visibility;
  final double? confidence;
}

class CallComposerSheet extends StatefulWidget {
  final VenueMarket market;
  final MarketSnapshot? snapshot;
  final SharePriceSnapshot? sharePrice;
  final Side? initialSide;
  final String? parentCallId;
  final String? headline;

  /// Restores a draft composed before sign-in (side, reason, visibility).
  final CallComposerDraft? initialDraft;

  /// Signed out: instead of the sign-in prompt, the form is shown and Lock
  /// hands the draft here (the sheet closes). Onboarding saves it and asks
  /// for sign-in at that moment.
  final ValueChanged<CallComposerDraft>? onSignInRequired;

  /// Re-reads the venue price once when it is missing or stale at Lock.
  final Future<SharePriceSnapshot?> Function()? refreshPrice;

  /// The server says this person already has a live call on this market.
  final VoidCallback? onAlreadyCalled;

  /// A note above the form ("Signed in as @ada. Lock it when you're ready.").
  final String? note;

  /// Where the call was made, for analytics.
  final AnalyticsSurface? surface;

  /// After a lock, explain-then-ask for notifications (lockdown's in-context
  /// ask). Onboarding passes false: its "You're on record" step asks there.
  final bool askForNotifications;

  /// Onboarding's one-tap confirm: the question, the side and Lock. No
  /// reason, visibility, confidence or rules (all still defaults: public,
  /// no reason, no confidence); the full composer is everywhere else.
  final bool compact;
  const CallComposerSheet({
    super.key,
    required this.market,
    this.snapshot,
    this.sharePrice,
    this.initialSide,
    this.parentCallId,
    this.headline,
    this.initialDraft,
    this.onSignInRequired,
    this.refreshPrice,
    this.onAlreadyCalled,
    this.note,
    this.surface,
    this.askForNotifications = true,
    this.compact = false,
  });
  @override
  State<CallComposerSheet> createState() => _CallComposerSheetState();
}

class _CallComposerSheetState extends State<CallComposerSheet> {
  late Side? _side = widget.initialDraft?.side ?? widget.initialSide;
  late final _thesis = TextEditingController(text: widget.initialDraft?.thesis);
  late bool _useConfidence = widget.initialDraft?.confidence != null;
  late double _confidence = widget.initialDraft?.confidence ?? .6;
  late CallVisibility _visibility =
      widget.initialDraft?.visibility ?? CallVisibility.public;
  late SharePriceSnapshot? _sharePrice = widget.sharePrice;
  bool _priceRefreshed = false;
  bool _refreshing = false;
  String? _error;
  String? _notice;

  /// Offer "Pick another market" (onboarding): stale price or a refusal.
  bool _offerAnother = false;
  @override
  void dispose() {
    _thesis.dispose();
    super.dispose();
  }

  /// Compact mode's single line: the side, Panta's price, and that it's free.
  String _compactLine(Side side) {
    final price = _sharePrice?.priceFor(side);
    final at =
        price == null
            ? ''
            : ' at ${CallsFormat.displayPrice(price)} USDC/share';
    return 'You’re calling ${side.wire}$at. Free, and it goes on your record.';
  }

  CallComposerDraft _draft(Side side) => CallComposerDraft(
    marketId: widget.market.id,
    side: side,
    thesis: _thesis.text.trim().isEmpty ? null : _thesis.text.trim(),
    visibility: _visibility,
    confidence: _useConfidence ? _confidence : null,
  );

  Future<void> _submit() async {
    final provider = context.read<CallsProvider>();
    if (provider.isSubmitting || _refreshing) return;
    final side = _side;
    if (side == null) {
      setState(() => _error = 'Pick a side first.');
      return;
    }
    final signIn = widget.onSignInRequired;
    if (!provider.isSignedIn && signIn != null) {
      // The draft stays on this phone; the price is read again after sign-in.
      final draft = _draft(side);
      Navigator.of(context).pop();
      signIn(draft);
      return;
    }
    if (widget.market.venue == MarketVenue.panta &&
        !(_sharePrice?.isUsableAt(DateTime.now()) ?? false)) {
      final refresh = widget.refreshPrice;
      if (refresh != null && !_priceRefreshed) {
        // Once, automatically. A fresh price is shown before any lock: the
        // person locks it with a fresh tap.
        setState(() {
          _refreshing = true;
          _error = null;
        });
        final fresh = await refresh();
        if (!mounted) return;
        final usable = fresh?.isUsableAt(DateTime.now()) ?? false;
        setState(() {
          _refreshing = false;
          _priceRefreshed = true;
          if (fresh != null) _sharePrice = fresh;
          _offerAnother = !usable;
          _notice =
              usable ? 'Panta sent a fresh price. Check it, then lock.' : null;
          _error =
              usable
                  ? null
                  : 'Panta hasn’t sent a fresh price for this market. Pick '
                      'another one, or try again in a minute.';
        });
        return;
      }
      setState(() {
        _offerAnother = true;
        _error =
            'Panta prices are missing or stale. Refresh this market before calling.';
      });
      return;
    }
    setState(() {
      _error = null;
      _notice = null;
    });
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
        surface: widget.surface,
      );
      if (!mounted) return;
      // Outlives this sheet: the in-context notification ask comes after it.
      final root = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop(entry);
      if (widget.askForNotifications && root.mounted) {
        unawaited(PushRegistration.afterSocialAction(root));
      }
    } on CallsException catch (e) {
      if (!mounted) return;
      final already = widget.onAlreadyCalled;
      if (already != null &&
          e is CallsRejectedException &&
          e.message.toLowerCase().contains('already have a live call')) {
        Navigator.of(context).pop();
        already();
        return;
      }
      setState(() {
        _error = e.message;
        _offerAnother = e is CallsRejectedException;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<CallsProvider>(
    builder:
        (context, provider, _) => CallJourneySheet(
          title: widget.headline ?? 'Make your call',
          busy: provider.isSubmitting,
          body:
              !provider.isSignedIn && widget.onSignInRequired == null
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (market.venue.isDemo)
                  const CallJourneyNote(
                    'DEMO DATA · Sample market, not a live call.',
                  ),
                if (widget.note != null)
                  CallJourneyNote(widget.note!, icon: 'user-outline'),
                if (!widget.compact) ...[
                  Text(
                    'Your opinion. On the record.',
                    style: callJourneyBody(12),
                  ),
                  const SizedBox(height: 12),
                ],
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
                      : widget.compact
                      ? _compactLine(_side!)
                      : 'You’re calling ${_side!.wire}. No money involved.',
                  style: callJourneyBody(),
                ),
                if (!widget.compact) ...[
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
                        ? '${CallsFormat.nativePrices(_sharePrice)} · ${SharePriceSnapshot.attribution}'
                            '${_sharePrice == null ? '' : ' · Observed ${CallsFormat.timestampUtc(_sharePrice!.observedAtUtc)}'} · Indicative, not a trade quote'
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
                      SelectableText(
                        market.rulesText,
                        style: callJourneyBody(),
                      ),
                      // Panta's public page, never its authenticated API URL.
                      if (market.venue == MarketVenue.panta &&
                          market.venueMarketId.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: PantaMarketLink(
                            venueMarketId: market.venueMarketId,
                            label: 'Resolved by Panta',
                            style: callJourneyBody(12),
                          ),
                        )
                      else if (market.resolutionSource != null)
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
                ],
                if (_notice != null)
                  Semantics(
                    liveRegion: true,
                    child: CallJourneyNote(_notice!, quiet: true),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CallJourneyButton(
                  label:
                      _side == null
                          ? 'Lock my call'
                          : 'Lock my ${_side!.wire} call',
                  primary: true,
                  busy: provider.isSubmitting || _refreshing,
                  onPressed:
                      _side == null || provider.isSubmitting || _refreshing
                          ? null
                          : _submit,
                ),
                if (_offerAnother && widget.refreshPrice != null)
                  ChumbucketTextAction(
                    label: 'Pick another market',
                    color: AppColors.pinkInk,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
              ],
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
  final bool showHeader;
  const CallJourneySheet({
    super.key,
    required this.title,
    required this.body,
    this.busy = false,
    this.showHeader = true,
  });
  @override
  Widget build(BuildContext context) {
    return ChumbucketWavySheet(
      title: title,
      canDismiss: !busy,
      showHeader: showHeader,
      body: DefaultTextStyle(style: callJourneyBody(), child: body),
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
  Widget build(BuildContext context) {
    // The primary action is the reference comp's button, shared app-wide.
    if (primary) {
      return ChumbucketPrimaryButton(
        label: label,
        onPressed: onPressed,
        busy: busy,
        busyLabel: 'Please wait…',
        leading:
            icon == null
                ? null
                : BasilIcon(icon!, size: 20, color: AppColors.onPrimary),
      );
    }
    // A secondary button is the same shape on white, so a pair of equal
    // actions ("Share link" / "Share image") still reads as one family.
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, ChumbucketPrimaryButton.height),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          foregroundColor: AppColors.textPrimary,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.outlineVariant, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ChumbucketPrimaryButton.radius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 18,
                height: 18,
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
                style: AppTextStyles.sheetAction.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CallJourneyNote extends StatelessWidget {
  final String text;
  final String icon;
  final bool error;

  /// A standing rule rather than news (the prototype's grey lock note).
  final bool quiet;
  const CallJourneyNote(
    this.text, {
    super.key,
    this.icon = 'info-circle-outline',
    this.error = false,
    this.quiet = false,
  });

  static const _quietFill = Color(0xFFECEFF2);
  static const _quietInk = Color(0xFF525D6E);

  @override
  Widget build(BuildContext context) {
    final ink =
        error
            ? AppColors.onErrorContainer
            : quiet
            ? _quietInk
            : AppColors.onPrimaryContainer;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(quiet ? 13 : 12),
      decoration: BoxDecoration(
        color:
            error
                ? AppColors.errorContainer
                : quiet
                ? _quietFill
                : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(quiet ? 13 : 14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BasilIcon(icon, size: quiet ? 17 : 20, color: ink),
          SizedBox(width: quiet ? 9 : 8),
          Expanded(
            child: Text(
              text,
              style: callJourneyBody(12).copyWith(color: ink, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
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
        final stacked =
            constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(12) > 18;
        // The prototype's evidence list: label left, value right in ink.
        final content = Text(
          value,
          textAlign: stacked ? TextAlign.start : TextAlign.end,
          style: callJourneyBody(
            12,
          ).copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        );
        if (stacked) {
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

  /// Beside the name, outside its tap target (Follow on a call).
  final Widget? trailing;
  const CallJourneyPerson({
    super.key,
    required this.person,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    final identity = _identity(context);
    if (trailing == null) return identity;
    return Row(
      children: [
        Expanded(child: identity),
        const SizedBox(width: 8),
        trailing!,
      ],
    );
  }

  Widget _identity(BuildContext context) => Semantics(
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

  /// When the choice is a side, it takes that side's colour once chosen —
  /// the prototype's green YES and slate NO. Other choices select in ink;
  /// brand pink stays for the call to action.
  final Side? side;
  const CallJourneyChoice({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.side,
  });

  static const _rule = Color(0xFFD6DCE1);

  @override
  Widget build(BuildContext context) {
    final (ink, fill) = switch (side) {
      Side.yes => (const Color(0xFF07644C), const Color(0xFFE6F6EF)),
      Side.no => (const Color(0xFF334155), const Color(0xFFEEF0F4)),
      null => (AppColors.textPrimary, const Color(0xFFF1F2F4)),
    };
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          backgroundColor: selected ? fill : AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(
            color: selected ? ink : _rule,
            width: selected ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: callJourneyHeading(
                  context,
                  14,
                ).copyWith(color: selected ? ink : AppColors.textPrimary),
              ),
            ),
            if (selected && side != null) ...[
              const SizedBox(width: 6),
              BasilIcon('check-outline', size: 16, color: ink),
            ],
          ],
        ),
      ),
    );
  }
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
                side: option,
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
