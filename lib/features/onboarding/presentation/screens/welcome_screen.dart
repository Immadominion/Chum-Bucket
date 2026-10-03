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
import 'package:chumbucket/features/onboarding/presentation/widgets/welcome_phone.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_styles.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';

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
  WelcomeFeed? _resolved;

  /// While the phone has nothing to show (offline, or the API is down), the
  /// sources are asked again on this beat until something answers.
  static const _retryEvery = Duration(seconds: 15);
  Timer? _retry;

  /// A retry is in flight: the empty state stays up while the sources answer
  /// again (inside a fresh budget), and what comes back then reaches the
  /// phone. Deciding at once would read the sources mid-request and settle
  /// on empty again, every time.
  bool _retrying = false;

  void _startBudget() {
    _budget?.cancel();
    _budgetSpent = false;
    _budget = Timer(widget.stripBudget, () {
      if (mounted) setState(() => _budgetSpent = true);
    });
  }

  @override
  void initState() {
    super.initState();
    _startBudget();
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

  void _scheduleRetry() {
    if (_retrying || (_retry?.isActive ?? false)) return;
    _retry = Timer(_retryEvery, () {
      if (!mounted) return;
      final calls = context.read<CallsProvider>();
      setState(() {
        _retrying = true;
        _startBudget();
      });
      unawaited(calls.loadTopCalls(force: true));
      if (calls.feedMode == CallFeedMode.global) {
        unawaited(calls.loadFeed(force: true));
      }
      unawaited(calls.loadOpenMarkets(force: true));
    });
  }

  @override
  void dispose() {
    _retry?.cancel();
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

  /// The phone's feed, or null while sources are still answering (inside
  /// the budget). Once resolved with something it does not change under the
  /// reader; resolved empty, it is asked again on [_retryEvery].
  WelcomeFeed? _feed(CallsProvider c, DateTime now) {
    final done = _resolved;
    if (done != null && !_retrying) return done;
    final top = _topSettled(c) ? (c.topCalls ?? const <TopCall>[]) : null;
    final feed =
        _feedSettled(c) && c.feedMode == CallFeedMode.global ? c.feed : null;
    final markets = _marketsSettled(c) ? c.openMarkets : null;
    final all = top != null && feed != null && markets != null;
    if (!all && !_budgetSpent) return done;
    _retrying = false;
    final chosen = chooseWelcomeFeed(
      top: top,
      feed: feed,
      markets: markets,
      now: now,
    );
    _resolved = chosen;
    context.read<CallsProvider>().analytics.record(
      OnboardingAnalyticsEvents.welcomeLive(
        source: chosen.source,
        count: chosen.items.length,
      ),
    );
    return chosen;
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
    final feed = _feed(calls, now);
    final offline = calls.isOffline;
    if (feed != null && feed.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleRetry();
      });
    }
    // The line under the title says what the phone shows: people's calls,
    // or (when nobody has called anything yet) markets.
    final tagline =
        feed != null && !feed.isEmpty && !feed.hasCalls
            ? OnboardingCopy.welcomeTaglineMarkets
            : OnboardingCopy.welcomeTagline;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Brand coral at the top, dissolving into the page behind the phone.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.lightPrimary,
                    AppColors.primary,
                    AppColors.background,
                  ],
                  stops: [0, .26, .58],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(OnbSpace.gutter, 10, 6, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // The wordmark gives way (scales down) before Sign in
                      // does: at 320dp and large text both no longer fit.
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: ExcludeSemantics(child: OnbWordmark()),
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('welcome-have-account'),
                        onPressed: flow.haveAccount,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size(64, 48),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text(OnboardingCopy.welcomeSignInShort),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  // The phone's stage runs behind the headline; the phone has
                  // fully dissolved by the time the title starts.
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: 150,
                        child: OnbReveal(
                          duration: const Duration(milliseconds: 520),
                          rise: 28,
                          child: WelcomePhone(
                            key: const ValueKey('welcome-live-strip'),
                            clearBottom: 96,
                            feed: feed,
                            offline: offline,
                            now: now,
                            onOpenCall: _openCall,
                            onOpenMarket: _openMarket,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            OnbSpace.gutter + 4,
                            0,
                            OnbSpace.gutter + 4,
                            12,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OnbReveal(
                                delay: const Duration(milliseconds: 120),
                                // A heading, read first; clamped like every
                                // onboarding title so no word breaks mid-word.
                                child: Semantics(
                                  header: true,
                                  child: Text(
                                    OnboardingCopy.welcomeTitle,
                                    textAlign: TextAlign.center,
                                    textScaler: MediaQuery.textScalerOf(
                                      context,
                                    ).clamp(
                                      maxScaleFactor: OnbTitle.maxTitleScale,
                                    ),
                                    style: const TextStyle(
                                      fontFamily: 'PPNeueMachina',
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      height: 1.12,
                                      letterSpacing: -.8,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OnbReveal(
                                delay: const Duration(milliseconds: 180),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 240),
                                  child: Text(
                                    tagline,
                                    key: ValueKey(tagline),
                                    textAlign: TextAlign.center,
                                    style: OnbText.body.copyWith(
                                      color: AppColors.textSecondary,
                                      fontSize: 16,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              OnbReveal(
                                delay: const Duration(milliseconds: 240),
                                child: ChumbucketPrimaryButton(
                                  key: const ValueKey('welcome-get-started'),
                                  label: OnboardingCopy.welcomeCta,
                                  onPressed:
                                      () =>
                                          flow.advance(outcome: 'get_started'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
