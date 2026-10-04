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
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_refusals.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/features/panta_trading/presentation/panta_market_link.dart';
import 'package:chumbucket/features/trust/data/content_policy.dart';
import 'package:chumbucket/features/money/data/money_models.dart'
    show MoneyCallKind, MoneyCallState;
import 'package:chumbucket/features/money/money_call_controller.dart'
    show MoneyCallRequest;
import 'package:chumbucket/features/money/money_controller.dart';
import 'package:chumbucket/features/money/presentation/money_amount_row.dart';
import 'package:chumbucket/features/money/presentation/money_call_sheet.dart'
    show runMoneyCall;

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
  MoneyAmount? initialAmount,
  bool allowMoney = true,
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
        initialAmount: initialAmount,
        allowMoney: allowMoney,
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

  /// Signed out: instead of the sign-in prompt, the form is shown and Call
  /// hands the draft here (the sheet closes). Onboarding saves it and asks
  /// for sign-in at that moment.
  final ValueChanged<CallComposerDraft>? onSignInRequired;

  /// Re-reads the venue price once when it is missing or stale at Call.
  final Future<SharePriceSnapshot?> Function()? refreshPrice;

  /// The server says this person already has a live call on this market.
  final VoidCallback? onAlreadyCalled;

  /// A note above the form ("Signed in as @ada.").
  final String? note;

  /// Where the call was made, for analytics.
  final AnalyticsSurface? surface;

  /// After a lock, explain-then-ask for notifications (lockdown's in-context
  /// ask). Onboarding passes false: its "You're on record" step asks there.
  final bool askForNotifications;

  /// Onboarding's one-tap confirm: the question, the side and Call. No
  /// reason, visibility, confidence or rules (all still defaults: public,
  /// no reason, no confidence); the full composer is everywhere else.
  final bool compact;

  /// The amount picked before the composer opened (market detail's row).
  final MoneyAmount? initialAmount;

  /// Calls with an amount, when money is on. Onboarding's first call stays
  /// free: it passes false (and compact never shows the row).
  final bool allowMoney;
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
    this.initialAmount,
    this.allowMoney = true,
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

  /// Reason, visibility, confidence and rules, behind one disclosure.
  late bool _more =
      widget.initialDraft?.thesis?.isNotEmpty == true ||
      widget.initialDraft?.confidence != null ||
      widget.initialDraft?.visibility == CallVisibility.followers;

  /// Offer "Pick another market" (onboarding): this market can't be called
  /// right now.
  bool _offerAnother = false;

  /// The amount on this call; set once money is known to be on.
  MoneyAmount? _amount;
  bool _moneyBusy = false;

  @override
  void dispose() {
    _thesis.dispose();
    super.dispose();
  }

  /// Money for this call, when it is on and this market can be traded.
  MoneyController? _money(BuildContext context, {bool listen = true}) {
    if (!widget.allowMoney || widget.compact || !widget.market.tradable) {
      return null;
    }
    final money = moneyOf(context, listen: listen);
    if (money != null) {
      _amount ??= widget.initialAmount ?? money.defaultAmount;
    }
    return money;
  }

  Future<void> _submitMoney(Side side, String thesis) async {
    final provider = context.read<CallsProvider>();
    final money = moneyOf(context, listen: false);
    final amount = _amount;
    if (money == null || amount == null || amount.isFree) return;
    setState(() => _error = null);
    final outcome = await runMoneyCall(
      context,
      MoneyCallRequest(
        kind: MoneyCallKind.own,
        marketId: widget.market.id,
        side: side,
        venueMarketId: widget.market.venueMarketId,
        question: widget.market.question,
        amountBaseUnits: amount.baseUnits!,
        confidence: _useConfidence ? _confidence : null,
        thesis: thesis.isEmpty ? null : thesis,
        visibility: _visibility,
      ),
      onBusy: (busy) {
        if (mounted) setState(() => _moneyBusy = busy);
      },
    );
    if (!mounted || outcome == null) return;
    if (outcome.error != null) {
      setState(() => _error = outcome.error);
      return;
    }
    final entry = outcome.call;
    if (entry == null) return;
    unawaited(money.remember(amount));
    final state = outcome.moneyCall?.state;
    if (state == MoneyCallState.funded || state == MoneyCallState.free) {
      provider.adoptCall(entry, surface: widget.surface);
    }
    Navigator.of(context).pop(entry);
  }

  /// Compact mode's single line: the side and its odds. That it's free is
  /// the [FreeMarker] in the button.
  String _compactLine(Side side) {
    final odds = CallsFormat.sideOdds(_sharePrice, side);
    return 'You’re calling ${side.wire}${odds == null ? '' : ' · $odds'}';
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
    if (provider.isSubmitting || _refreshing || _moneyBusy) return;
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
    final thesis = _thesis.text.trim();
    final problem = contentPolicyProblem(thesis, ContentField.thesis);
    if (problem != null) {
      setState(() {
        _more = true;
        _error = problem;
      });
      return;
    }
    if (!(_amount?.isFree ?? true) && _money(context, listen: false) != null) {
      await _submitMoney(side, thesis);
      return;
    }
    if (widget.market.venue == MarketVenue.panta &&
        !(_sharePrice?.isUsableAt(DateTime.now()) ?? false)) {
      final refresh = widget.refreshPrice;
      if (refresh != null && !_priceRefreshed) {
        // Quietly, once. The server reads Panta's price itself when the one
        // it holds has lapsed, so a lapsed price is never the person's
        // problem: this only keeps the price on the buttons current.
        setState(() {
          _refreshing = true;
          _error = null;
        });
        SharePriceSnapshot? fresh;
        try {
          fresh = await refresh();
        } catch (_) {
          fresh = null;
        }
        if (!mounted) return;
        setState(() {
          _refreshing = false;
          _priceRefreshed = true;
          if (fresh != null) _sharePrice = fresh;
        });
      }
    }
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
        surface: widget.surface,
      );
      if (!mounted) return;
      if (_amount case final amount? when amount.isFree) {
        unawaited(moneyOf(context, listen: false)?.remember(amount));
      }
      // Outlives this sheet: the in-context notification ask comes after it.
      final root = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop(entry);
      if (widget.askForNotifications && root.mounted) {
        unawaited(PushRegistration.afterSocialAction(root));
      }
    } on CallsException catch (e) {
      if (!mounted) return;
      final refusal = classifyCallRefusal(e);
      final already = widget.onAlreadyCalled;
      if (already != null && refusal == CallRefusal.alreadyOnRecord) {
        Navigator.of(context).pop();
        already();
        return;
      }
      setState(() {
        _error = callRefusalMessage(e);
        _offerAnother =
            refusal == CallRefusal.priceUnavailable ||
            refusal == CallRefusal.closed ||
            refusal == CallRefusal.other;
      });
    } catch (_) {
      // Never a spinner with no way out: whatever failed, say so.
      if (mounted) setState(() => _error = kCallUnexpectedFailure);
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<CallsProvider>(
    builder:
        (context, provider, _) => CallJourneySheet(
          title: widget.headline ?? 'Make your call',
          busy: provider.isSubmitting || _moneyBusy,
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

  /// Each side's odds now, on its button: Panta's price as a percent (USDC
  /// and SOL markets alike), or a legacy venue's probability.
  Map<Side, String>? _sideSubs() {
    final market = widget.market;
    if (market.venue == MarketVenue.panta) {
      final price = _usablePrice();
      if (price == null) return null;
      return {
        for (final side in Side.values)
          if (CallsFormat.sideOdds(price, side) case final odds?)
            side: odds,
      };
    }
    final snapshot = widget.snapshot;
    if (snapshot == null) return null;
    return {
      Side.yes: CallsFormat.probability(snapshot.yesProbability),
      Side.no: CallsFormat.probability(snapshot.noProbability),
    };
  }

  SharePriceSnapshot? _usablePrice() {
    final price = _sharePrice;
    if (price == null || !price.isUsableAt(DateTime.now())) return null;
    return price;
  }

  Widget _form(CallsProvider provider) {
    final market = widget.market;
    final open = market.status.acceptsNewCalls;
    final busy = provider.isSubmitting || _refreshing || _moneyBusy;
    final money = _money(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (market.venue.isDemo) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DemoVenueBadge(venue: market.venue),
                  ),
                  const SizedBox(height: 10),
                ],
                if (widget.note != null)
                  CallJourneyNote(widget.note!, icon: 'user-outline'),
                Text(market.question, style: callJourneyHeading(context, 22)),
                const SizedBox(height: 16),
                if (!open)
                  CallJourneyNote(
                    '${market.status.label} · no new calls here.',
                    icon: 'lock-time-outline',
                    quiet: true,
                  ),
                CallJourneySides(
                  market: market,
                  side: _side,
                  subs: widget.compact ? null : _sideSubs(),
                  onChanged:
                      open && !busy
                          ? (side) => setState(() {
                            _side = side;
                            _error = null;
                          })
                          : null,
                ),
                // The chosen side already shows on its button and on Call,
                // so the full composer says nothing more once one is picked.
                if (_side == null || widget.compact) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _side == null
                          ? 'Choose your YES or NO.'
                          : _compactLine(_side!),
                      style: callJourneyBody(),
                    ),
                  ),
                ] else
                  const SizedBox(height: 6),
                if (!widget.compact) ...[
                  const SizedBox(height: 4),
                  _MoreOptionsToggle(
                    open: _more,
                    onTap: () => setState(() => _more = !_more),
                  ),
                  if (_more) ..._moreOptions(provider, market),
                ],
              ],
            ),
          ),
        ),
        if (open)
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
                if (money != null) ...[
                  MoneyAmountRow.of(
                    money,
                    value: _amount!,
                    enabled: !busy,
                    onChanged:
                        (amount) => setState(() {
                          _amount = amount;
                          _error = null;
                        }),
                  ),
                  const SizedBox(height: 12),
                  // Free: the ink button with its Free marker. An amount:
                  // pink, "Call YES · $5".
                  MoneyCallButton(
                    label: _side == null ? 'Call it' : 'Call ${_side!.wire}',
                    amount: _amount!,
                    busy: busy,
                    onPressed: _side == null || busy ? null : _submit,
                  ),
                ] else
                  // A free call: the solid ink button, Free marker inside.
                  CallJourneyButton(
                    label: _side == null ? 'Call it' : 'Call ${_side!.wire}',
                    primary: true,
                    free: true,
                    busy: busy,
                    onPressed: _side == null || busy ? null : _submit,
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

  List<Widget> _moreOptions(CallsProvider provider, VenueMarket market) {
    final busy = provider.isSubmitting || _refreshing;
    return [
      const SizedBox(height: 4),
      CallJourneyReason(controller: _thesis, enabled: !busy),
      CallJourneyVisibility(
        value: _visibility,
        onChanged: busy ? null : (value) => setState(() => _visibility = value),
      ),
      const SizedBox(height: 4),
      CallJourneyConfidence(
        enabled: _useConfidence,
        confidence: _confidence,
        onToggle:
            busy ? null : (value) => setState(() => _useConfidence = value),
        onChanged: busy ? null : (value) => setState(() => _confidence = value),
      ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const BasilIcon(
          'book-check-outline',
          size: 20,
          color: AppColors.textPrimary,
        ),
        title: Text('Market rules', style: callJourneyHeading(context, 14)),
        children: [
          SelectableText(market.rulesText, style: callJourneyBody()),
          if (market.closesAtUtc != null)
            CallJourneyFact(
              'Closes',
              CallsFormat.timestampUtc(market.closesAtUtc!),
            ),
          // Panta's public page, never its authenticated API URL.
          if (market.venue == MarketVenue.panta &&
              market.venueMarketId.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: PantaMarketLink(
                venueMarketId: market.venueMarketId,
                label: 'Prices and result by Panta',
                style: callJourneyBody(12),
              ),
            )
          else if (market.resolutionSource != null)
            CallJourneyFact('Resolution source', market.resolutionSource!),
        ],
      ),
    ];
  }
}

/// "More options", the one disclosure the full composer keeps its extras
/// behind.
class _MoreOptionsToggle extends StatelessWidget {
  const _MoreOptionsToggle({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      key: const ValueKey('composer-more-options'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        foregroundColor: AppColors.pinkInk,
      ),
      iconAlignment: IconAlignment.end,
      icon: BasilIcon(
        open ? 'caret-up-outline' : 'caret-down-outline',
        size: 18,
        color: AppColors.pinkInk,
      ),
      label: Semantics(
        expanded: open,
        child: Text(
          'More options',
          style: callJourneyHeading(
            context,
            13,
          ).copyWith(color: AppColors.pinkInk),
        ),
      ),
    ),
  );
}

/// A refusal or failure, beside the button that caused it. Announced.
class CallInlineError extends StatelessWidget {
  const CallInlineError(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      key: const ValueKey('call-inline-error'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const BasilIcon(
            'info-triangle-outline',
            size: 18,
            color: AppColors.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: callJourneyBody(
                13,
              ).copyWith(color: AppColors.onErrorContainer, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
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

  /// A free call's action: solid ink, never pink (pink is money), with the
  /// [FreeMarker] beside the label.
  final bool free;
  const CallJourneyButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.busy = false,
    this.free = false,
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
        neutral: free,
        trailing: free ? const FreeMarker(onDark: true) : null,
        semanticsLabel: free ? '$label, ${FundingState.none.label}' : null,
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
            // Decorative beside the name: initials keep their size at
            // large text instead of overflowing the circle.
            MediaQuery.withNoTextScaling(
              child: AppAvatar(
                initials: person.initials,
                imageUrl: person.avatarUrl,
                size: 44,
                backgroundColor: AppColors.primaryContainer,
                textColor: AppColors.onPrimaryContainer,
              ),
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

  /// A second, smaller line: what this side costs now.
  final String? sub;

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
    this.sub,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
            if (sub != null)
              Text(
                sub!,
                textAlign: TextAlign.center,
                style: callJourneyBody(12).copyWith(
                  color: selected ? ink : AppColors.textMuted,
                  height: 1.3,
                ),
              ),
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

  /// What each side costs now, shown on its button.
  final Map<Side, String>? subs;

  /// List the market's own outcome words under the buttons.
  final bool showOutcomeLabels;
  const CallJourneySides({
    super.key,
    required this.market,
    required this.side,
    this.onChanged,
    this.subs,
    this.showOutcomeLabels = true,
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
                sub: subs?[option],
                selected: side == option,
                onTap: onChanged == null ? null : () => onChanged!(option),
              ),
            ),
          ],
        ],
      ),
      if (showOutcomeLabels)
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
  final bool autofocus;
  const CallJourneyReason({
    super.key,
    required this.controller,
    this.enabled = true,
    this.hint = 'What are you seeing?',
    this.autofocus = false,
  });
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    autofocus: autofocus,
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
          'Add your confidence',
          style: callJourneyHeading(context, 14),
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
