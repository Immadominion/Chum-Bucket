/// W1 "Call it before it happens." (onboarding spec §6): proves the product
/// is alive with real calls from production, says what it is in three lines,
/// says money once, plainly, and gets out of the way.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/live_call_strip.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';

/// How long the strip may show skeletons before it uses what has answered.
const Duration kLiveStripBudget = Duration(seconds: 6);

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.stripBudget = kLiveStripBudget});

  final Duration stripBudget;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _scroll = ScrollController();
  final _stripScroll = ScrollController();
  Timer? _budget;
  bool _budgetSpent = false;
  bool _feedRequested = false;
  bool _marketsRequested = false;
  LiveStrip? _resolved;

  @override
  void initState() {
    super.initState();
    _budget = Timer(widget.stripBudget, () {
      if (mounted) setState(() => _budgetSpent = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final calls = context.read<CallsProvider>();
      unawaited(calls.loadTopCalls());
      if (calls.feedMode == CallFeedMode.global) {
        _feedRequested = true;
        unawaited(calls.loadFeed());
      }
      _marketsRequested = true;
      unawaited(calls.loadOpenMarkets());
    });
  }

  @override
  void dispose() {
    _budget?.cancel();
    _scroll.dispose();
    _stripScroll.dispose();
    super.dispose();
  }

  bool _topSettled(CallsProvider c) =>
      !c.supportsPeople ||
      (!c.isLoadingTopCalls && (c.topCalls != null || c.topCallsError != null));

  bool _feedSettled(CallsProvider c) =>
      !_feedRequested ||
      switch (c.feedState) {
        CallsLoadState.ready ||
        CallsLoadState.empty ||
        CallsLoadState.error ||
        CallsLoadState.offline => true,
        _ => false,
      };

  bool _marketsSettled(CallsProvider c) =>
      _marketsRequested && !c.isLoadingOpenMarkets;

  /// The strip, or null while a higher-priority source is still answering
  /// (inside the budget). Once resolved it does not change under the reader.
  LiveStrip? _strip(CallsProvider c, DateTime now) {
    if (_resolved != null) return _resolved;
    final top = _topSettled(c) ? (c.topCalls ?? const <TopCall>[]) : null;
    final feed =
        _feedSettled(c) && c.feedMode == CallFeedMode.global ? c.feed : null;
    final markets = _marketsSettled(c) ? c.openMarkets : null;
    final strip = chooseLiveStrip(
      top: top,
      feed: feed,
      markets: markets,
      now: now,
    );
    final decided = switch (strip.source) {
      LiveStripSource.top => true,
      LiveStripSource.feed => top != null || _budgetSpent,
      LiveStripSource.markets => (top != null && feed != null) || _budgetSpent,
      LiveStripSource.none =>
        (top != null && feed != null && markets != null) || _budgetSpent,
    };
    if (!decided) return null;
    _resolved = strip;
    context.read<CallsProvider>().analytics.record(
      OnboardingAnalyticsEvents.welcomeLive(
        source: strip.source.wire,
        count: strip.items.length,
      ),
    );
    return strip;
  }

  void _openCall(CallFeedEntry entry) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CallDetailScreen(callId: entry.call.id),
    ),
  );

  void _openMarket(VenueMarket market) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MarketDetailScreen(marketId: market.id),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final flow = context.read<OnboardingFlowController>();
    final calls = context.watch<CallsProvider>();
    final now = flow.now;
    final strip = _strip(calls, now);
    final largeText = MediaQuery.textScalerOf(context).scale(10) > 13;
    final offline =
        calls.isOffline &&
        (strip == null || strip.isEmpty) &&
        calls.feed.isEmpty &&
        calls.openMarkets.isEmpty;

    return OnboardingScaffold(
      controller: _scroll,
      announce: OnboardingCopy.welcomeTitle,
      header: const OnboardingBrandBand(artwork: ChumbucketStateArtwork.calls),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      actions: [
        ChumbucketPrimaryButton(
          key: const ValueKey('welcome-get-started'),
          label: OnboardingCopy.welcomeCta,
          onPressed: () => flow.advance(outcome: 'get_started'),
        ),
        const SizedBox(height: 4),
        OnbTextAction(
          key: const ValueKey('welcome-have-account'),
          label: OnboardingCopy.welcomeSignIn,
          onPressed: flow.haveAccount,
        ),
      ],
      // At large text the venue line moves into the page, so the sticky
      // area stays two actions tall.
      footer:
          largeText
              ? null
              : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  OnboardingCopy.welcomeFooter,
                  textAlign: TextAlign.center,
                  style: OnbText.meta,
                ),
              ),
      children: [
        const OnbReveal(child: OnbTitle(OnboardingCopy.welcomeTitle)),
        const SizedBox(height: 8),
        const OnbReveal(
          delay: Duration(milliseconds: 60),
          child: OnbBody(OnboardingCopy.welcomeBody),
        ),
        if (offline) ...[
          const SizedBox(height: 20),
          const OnbIconLine(
            key: ValueKey('welcome-offline'),
            icon: 'cloud-off-outline',
            text: OnboardingCopy.welcomeOffline,
          ),
        ] else if (strip == null) ...[
          const SizedBox(height: 24),
          _StripHeading(text: OnboardingCopy.welcomeLiveCalls, loading: true),
          const SizedBox(height: 12),
          const OnbFullBleed(child: LiveStripSkeleton()),
        ] else if (!strip.isEmpty) ...[
          const SizedBox(height: 24),
          _StripHeading(
            text:
                strip.source == LiveStripSource.markets
                    ? OnboardingCopy.welcomeLiveMarkets
                    : OnboardingCopy.welcomeLiveCalls,
          ),
          const SizedBox(height: 12),
          OnbFullBleed(
            child: LiveCallStrip(
              key: const ValueKey('welcome-live-strip'),
              strip: strip,
              controller: _stripScroll,
              now: now,
              onOpenCall: _openCall,
              onOpenMarket: _openMarket,
            ),
          ),
        ],
        const SizedBox(height: 28),
        const HowItWorksList(),
        const SizedBox(height: 24),
        const OnbIconLine(
          key: ValueKey('welcome-money'),
          icon: 'info-circle-outline',
          text: OnboardingCopy.welcomeMoney,
        ),
        if (largeText) ...[
          const SizedBox(height: 16),
          Text(OnboardingCopy.welcomeFooter, style: OnbText.meta),
        ],
      ],
    );
  }
}

class _StripHeading extends StatelessWidget {
  const _StripHeading({required this.text, this.loading = false});
  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        if (!loading) ...[
          ExcludeSemantics(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF07644C),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(text, style: OnbText.section)),
      ],
    ),
  );
}
