/// C "Make your first call" (onboarding spec §6): answer a named person's
/// live call, or call one of up to three real markets with a fresh Panta
/// price. No wallet, amount or deposit anywhere. Signed out, Lock keeps the
/// draft on the phone and asks for sign-in; after sign-in the composer
/// reopens with it and Lock needs a fresh tap (the price may have moved).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_format.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';

class FirstCallScreen extends StatefulWidget {
  const FirstCallScreen({super.key, this.resume = false});

  /// After sign-in: reopen the saved draft for a fresh Lock.
  final bool resume;

  @override
  State<FirstCallScreen> createState() => _FirstCallScreenState();
}

class _FirstCallScreenState extends State<FirstCallScreen> {
  bool _opening = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    if (widget.resume) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resumeDraft());
      });
    }
  }

  OnboardingFlowController get _flow =>
      context.read<OnboardingFlowController>();
  CallsProvider get _calls => context.read<CallsProvider>();

  String? get _signedInNote {
    final flow = _flow;
    if (!flow.signedIn) return null;
    return OnboardingCopy.callSignedInNote(flow.session?.handle);
  }

  Future<SharePriceSnapshot?> _refreshPrice(String marketId) async =>
      (await _calls.loadMarketDetail(marketId, force: true))?.sharePrice;

  Future<void> _alreadyCalled(String marketId) async {
    final detail = await _calls.loadMarketDetail(marketId, force: true);
    final own = detail?.viewerCall;
    if (!mounted) return;
    if (own != null) {
      await _flow.locked(own, already: true);
    } else {
      setState(() => _notice = OnboardingCopy.callStale);
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// A market row: the composer, signed in or not.
  Future<void> _compose(
    VenueMarket market, {
    SharePriceSnapshot? sharePrice,
    MarketSnapshot? snapshot,
    PendingCall? draft,
    Side? side,
  }) async {
    final flow = _flow;
    if (draft == null) {
      _calls.analytics.record(
        OnboardingAnalyticsEvents.firstCallOpened(
          kind: 'market',
          marketId: market.id,
        ),
      );
    }
    final entry = await showCallComposer(
      context: context,
      market: market,
      sharePrice: sharePrice,
      snapshot: snapshot,
      surface: AnalyticsSurface.onboarding,
      // "You're on record" asks about notifications, once.
      askForNotifications: false,
      compact: true,
      initialSide: side,
      note: draft != null ? _signedInNote : null,
      initialDraft:
          draft == null
              ? null
              : CallComposerDraft(
                marketId: draft.marketId,
                side: draft.side,
                thesis: draft.thesis,
                visibility: draft.visibility,
                confidence: draft.confidence,
              ),
      refreshPrice: () => _refreshPrice(market.id),
      onAlreadyCalled: () => unawaited(_alreadyCalled(market.id)),
      onSignInRequired:
          flow.signedIn
              ? null
              : (d) => unawaited(
                flow.saveDraftAndSignIn(
                  PendingCall(
                    kind: PendingCallKind.call,
                    marketId: d.marketId,
                    side: d.side,
                    thesis: d.thesis,
                    visibility: d.visibility,
                    confidence: d.confidence,
                    question: market.question,
                    savedAt: flow.now.toUtc().millisecondsSinceEpoch,
                  ),
                ),
              ),
    );
    if (entry != null && mounted) await flow.locked(entry);
  }

  /// YES or NO on a deck card. Signed out, the pick is kept on the phone
  /// and sign-in comes straight away (no sheet first); signed in, a one-tap
  /// confirm with that side chosen.
  Future<void> _pick(FirstCallMarket item, Side side) async {
    final flow = _flow;
    if (!flow.signedIn) {
      _calls.analytics.record(
        OnboardingAnalyticsEvents.firstCallOpened(
          kind: 'market',
          marketId: item.market.id,
        ),
      );
      await flow.saveDraftAndSignIn(
        PendingCall(
          kind: PendingCallKind.call,
          marketId: item.market.id,
          side: side,
          question: item.market.question,
          savedAt: flow.now.toUtc().millisecondsSinceEpoch,
        ),
      );
      return;
    }
    await _compose(
      item.market,
      sharePrice: item.sharePrice,
      snapshot: item.snapshot,
      side: side,
    );
  }

  /// Back or Fade on someone's live call.
  Future<void> _respond(TopCall top, CallResponseKind kind) async {
    final flow = _flow;
    final entry = entryOfTopCall(top);
    if (flow.signedIn && top.author.id == _calls.viewerUserId) {
      setState(() => _notice = OnboardingCopy.callOwnDraft);
      return;
    }
    if (!flow.signedIn) {
      await flow.saveDraftAndSignIn(
        PendingCall(
          kind:
              kind == CallResponseKind.fade
                  ? PendingCallKind.fade
                  : PendingCallKind.back,
          marketId: top.market.id,
          side:
              kind == CallResponseKind.fade
                  ? top.call.side.opposite
                  : top.call.side,
          targetCallId: top.call.id,
          question: top.market.question,
          savedAt: flow.now.toUtc().millisecondsSinceEpoch,
        ),
      );
      return;
    }
    _calls.analytics.record(
      OnboardingAnalyticsEvents.firstCallOpened(
        kind: kind.wire,
        marketId: top.market.id,
      ),
    );
    await _openResponse(entry, kind);
  }

  Future<void> _openResponse(
    CallFeedEntry entry,
    CallResponseKind kind, {
    bool resumed = false,
  }) async {
    final result = await showCallResponseSheet(
      context: context,
      entry: entry,
      initialKind: kind,
      surface: AnalyticsSurface.onboarding,
      askForNotifications: false,
      note: resumed ? _signedInNote : null,
    );
    final own = result?.resultingCall;
    if (own != null && mounted) await _flow.locked(own);
  }

  /// After sign-in: reopen the draft, checked against the server first.
  Future<void> _resumeDraft() => _guard(() async {
    final flow = _flow;
    final draft = flow.pendingCall;
    if (draft == null) {
      flow.advance(outcome: 'later');
      return;
    }
    final detail = await _calls.loadMarketDetail(draft.marketId, force: true);
    if (!mounted) return;
    final own = detail?.viewerCall;
    if (own != null) {
      // Already on record for this market (another phone, or before).
      await flow.locked(own, already: true);
      return;
    }
    if (detail == null || !isCallReadyMarket(detail.market, flow.now)) {
      await flow.app.clearDraft();
      if (mounted) {
        setState(() => _notice = OnboardingCopy.callPickAnother);
      }
      return;
    }
    if (draft.kind == PendingCallKind.call) {
      await _compose(
        detail.market,
        sharePrice: detail.sharePrice,
        snapshot: detail.snapshot,
        draft: draft,
      );
      return;
    }
    final target = await _calls.loadCall(
      draft.targetCallId!,
      reportOpen: false,
    );
    if (!mounted) return;
    if (target == null) {
      await flow.app.clearDraft();
      if (mounted) setState(() => _notice = OnboardingCopy.callPickAnother);
      return;
    }
    if (target.entry.author.id == _calls.viewerUserId) {
      // Signed in as the person who made it: there is nothing to answer.
      await flow.app.clearDraft();
      if (mounted) setState(() => _notice = OnboardingCopy.callOwnDraft);
      return;
    }
    await _openResponse(
      target.entry,
      draft.kind == PendingCallKind.fade
          ? CallResponseKind.fade
          : CallResponseKind.back,
      resumed: true,
    );
  });

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<OnboardingFlowController>();
    final loading =
        flow.firstCallData == StepData.loading ||
        (flow.firstCallRefreshing &&
            flow.firstCallMarkets.isEmpty &&
            flow.answerable.isEmpty);
    final markets = flow.firstCallMarkets;
    final answerable = flow.answerable;
    final draft = widget.resume ? flow.pendingCall : null;

    return OnboardingScaffold(
      onBack: flow.canGoBack && !widget.resume ? flow.back : null,
      progress: widget.resume ? null : flow.progress,
      busy: _opening,
      announce: OnboardingCopy.callTitle,
      // After sign-in there is no Back/progress row above the title: give it
      // the air that row gives every other step.
      contentPadding:
          widget.resume
              ? const EdgeInsets.fromLTRB(16, 32, 16, 24)
              : const EdgeInsets.fromLTRB(16, 8, 16, 24),
      actions: [
        OnbTextAction(
          key: const ValueKey('first-call-later'),
          label: OnboardingCopy.callLater,
          onPressed: _opening ? null : flow.callLater,
        ),
      ],
      children: [
        const OnbTitle(OnboardingCopy.callTitle),
        const SizedBox(height: 8),
        const OnbBody(OnboardingCopy.callBody),
        if (_notice != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: OnbIconLine(
              icon: 'info-circle-outline',
              text: _notice!,
              color: AppColors.onWarningContainer,
            ),
          ),
        ],
        if (draft != null) ...[
          const SizedBox(height: 16),
          DraftCallCard(
            draft: draft,
            // Put away without locking? It is one tap from the composer.
            onOpen: _opening ? null : _resumeDraft,
          ),
        ],
        if (loading) ...[
          const SizedBox(height: 24),
          const _MarketsSkeleton(),
        ] else ...[
          if (answerable.isNotEmpty) ...[
            const SizedBox(height: 24),
            _SectionHeading(OnboardingCopy.callAnswerHeader),
            const SizedBox(height: 12),
            for (final top in answerable) ...[
              _AnswerCard(
                top: top,
                enabled: !_opening,
                onBack:
                    () => _guard(() => _respond(top, CallResponseKind.back)),
                onFade:
                    () => _guard(() => _respond(top, CallResponseKind.fade)),
              ),
              const SizedBox(height: 12),
            ],
            Text(OnboardingCopy.callAnswerHelper, style: OnbText.meta),
          ],
          if (markets.isNotEmpty) ...[
            const SizedBox(height: 20),
            OnbFullBleed(
              child: _MarketDeck(
                markets: markets,
                enabled: !_opening,
                onPick: (item, side) => _guard(() => _pick(item, side)),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: OnbText.section));
}

/// A named person's live call, with Back and Fade as equal, neutral actions.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.top,
    required this.onBack,
    required this.onFade,
    required this.enabled,
  });

  final TopCall top;
  final VoidCallback onBack;
  final VoidCallback onFade;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final author = top.author;
    final name = shownName(
      displayName: author.displayName,
      handle: author.handle,
    );
    final handle = visibleHandle(author.handle);
    final side = top.call.side.wire;
    final thesis = top.call.thesis?.trim();
    final stack =
        MediaQuery.sizeOf(context).width < 300 ||
        MediaQuery.textScalerOf(context).scale(10) > 15;
    final back = _ResponseButton(
      key: ValueKey('answer-back-${top.call.id}'),
      icon: 'add-outline',
      label: OnboardingCopy.callBack,
      onPressed: enabled ? onBack : null,
    );
    final fade = _ResponseButton(
      key: ValueKey('answer-fade-${top.call.id}'),
      icon: 'exchange-outline',
      label: OnboardingCopy.callFade,
      onPressed: enabled ? onFade : null,
    );
    return OnbSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Semantics(
              label:
                  '${OnboardingCopy.welcomeCardCalled(name, side)} on '
                  '${top.market.question}.',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        OnbAvatar(
                          name: name,
                          imageUrl: author.avatarUrl,
                          size: 36,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: OnbText.name),
                              if (handle != null)
                                Text('@$handle', style: OnbText.small),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SidePill(
                      side: top.call.side,
                      label: OnboardingCopy.calledSide(side),
                    ),
                    const SizedBox(height: 10),
                    Text(top.market.question, style: OnbText.question),
                    if (thesis != null && thesis.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        thesis,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: OnbText.small.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (stack) ...[
            back,
            const SizedBox(height: 8),
            fade,
          ] else
            Row(
              children: [
                Expanded(child: back),
                const SizedBox(width: 8),
                Expanded(child: fade),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResponseButton extends StatelessWidget {
  const _ResponseButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      backgroundColor: const Color(0xFFFAFAFA),
      foregroundColor: AppColors.textPrimary,
      side: const BorderSide(color: Color(0xFFE3E5E8)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BasilIcon(icon, size: 18, color: AppColors.textPrimary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, style: OnbText.name.copyWith(fontSize: 14)),
        ),
      ],
    ),
  );
}

/// The call saved on this phone, waiting for a signed-in Lock.
class DraftCallCard extends StatelessWidget {
  const DraftCallCard({super.key, required this.draft, this.onOpen});
  final PendingCall draft;

  /// After sign-in: reopens the draft in the composer (it may have been put
  /// away without locking). Null on the sign-in screen.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => OnbSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidePill(side: draft.side),
        if (draft.question != null) ...[
          const SizedBox(height: 10),
          Text(draft.question!, style: OnbText.question),
        ],
        const SizedBox(height: 10),
        OnbIconLine(
          icon: 'mobile-phone-outline',
          text: OnboardingCopy.signInDraftNote,
        ),
        if (onOpen != null) ...[
          const SizedBox(height: 8),
          ChumbucketPrimaryButton(
            key: const ValueKey('draft-review'),
            label: OnboardingCopy.pendingCallCta,
            onPressed: onOpen,
          ),
        ],
      ],
    ),
  );
}

class _MarketsSkeleton extends StatelessWidget {
  const _MarketsSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: OnboardingCopy.callLoading,
    child: ExcludeSemantics(
      child: OnbSurface(
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: 22),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OnbSkeleton(height: 36, width: 36, radius: 11),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OnbSkeleton(),
                        SizedBox(height: 6),
                        OnbSkeleton(width: 160),
                        SizedBox(height: 14),
                        OnbSkeleton(height: 38, radius: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The first call as a deck: one real market per card, swiped sideways, with
/// two big answers. Panta's live price is on each answer.
class _MarketDeck extends StatefulWidget {
  const _MarketDeck({
    required this.markets,
    required this.enabled,
    required this.onPick,
  });

  final List<FirstCallMarket> markets;
  final bool enabled;
  final void Function(FirstCallMarket item, Side side) onPick;

  @override
  State<_MarketDeck> createState() => _MarketDeckState();
}

class _MarketDeckState extends State<_MarketDeck> {
  final _pages = PageController(viewportFraction: .88);
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markets = widget.markets;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // Tall phones get a tall card, which also brings YES/NO down to the
    // thumb; the shadow gets room below so it is never cut.
    final screen = MediaQuery.sizeOf(context).height;
    final height =
        (screen * .5).clamp(350.0, 480.0) + 60 * (scale - 1).clamp(0, 1.5);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _pages,
            itemCount: markets.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder:
                (context, i) => AnimatedBuilder(
                  animation: _pages,
                  builder: (context, child) {
                    final page =
                        _pages.hasClients && _pages.position.haveDimensions
                            ? (_pages.page ?? _page.toDouble())
                            : _page.toDouble();
                    final d = (page - i).abs().clamp(0.0, 1.0);
                    return Transform.scale(scale: 1 - .06 * d, child: child);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 6, 28),
                    child: _DeckCard(
                      key: ValueKey('first-call-${markets[i].market.id}'),
                      item: markets[i],
                      enabled: widget.enabled,
                      onPick: (side) => widget.onPick(markets[i], side),
                    ),
                  ),
                ),
          ),
        ),
        if (markets.length > 1) ...[
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < markets.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color:
                          i == _page
                              ? AppColors.primary
                              : const Color(0xFFD8DADD),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DeckCard extends StatelessWidget {
  static double _questionSize(String q) =>
      q.length <= 48
          ? 31
          : q.length <= 80
          ? 27
          : q.length <= 120
          ? 23
          : 20;

  const _DeckCard({
    super.key,
    required this.item,
    required this.enabled,
    required this.onPick,
  });

  final FirstCallMarket item;
  final bool enabled;
  final void Function(Side side) onPick;

  @override
  Widget build(BuildContext context) {
    final market = item.market;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14111827),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MarketGlyph(market: market),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${marketCategoryLabel(market.category)} · '
                  '${OnbFormat.closesLine(market)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OnbText.meta,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // The question owns the card: set large and centred, sized to its
          // length so a short question never floats in empty space.
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                market.question,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'PPNeueMachina',
                  fontSize: _questionSize(market.question),
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AnswerButton(
                  side: Side.yes,
                  price: CallsFormat.odds(item.sharePrice.yesPrice),
                  enabled: enabled,
                  onTap: () => onPick(Side.yes),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AnswerButton(
                  side: Side.no,
                  price: CallsFormat.odds(item.sharePrice.noPrice),
                  enabled: enabled,
                  onTap: () => onPick(Side.no),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.side,
    required this.price,
    required this.enabled,
    required this.onTap,
  });

  final Side side;
  /// The side's odds, already a percent ("62%"), or null.
  final String? price;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final yes = side == Side.yes;
    final ink = yes ? const Color(0xFF07644C) : const Color(0xFF334155);
    final fill = yes ? const Color(0xFFE6F6EF) : const Color(0xFFEEF0F4);
    return Semantics(
      button: true,
      label:
          'Call ${side.wire}'
          '${price == null ? '' : ', $price'}',
      excludeSemantics: true,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('deck-${side.wire.toLowerCase()}'),
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onTap : null,
          // 68dp, taller when large text needs it.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  side.wire,
                  style: TextStyle(
                    fontFamily: 'PPNeueMachina',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
                if (price != null)
                  Text(
                    price!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ink.withValues(alpha: .75),
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
