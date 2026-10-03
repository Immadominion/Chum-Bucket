/// One run of onboarding: which steps it shows, where it is, and the real
/// data each optional step needs (onboarding spec §4.3, §6, §7, §12).
///
/// Steps are recomputed from what is true right now ([computeSteps]) every
/// time data arrives or the session changes. An optional step whose data
/// turns out too thin (or slow, or offline) drops out; if the person is
/// already on it, the run moves on with `outcome: auto_skipped`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';

/// How a run hands back to the app.
enum FlowExit {
  /// Replace the flow with Home.
  home,

  /// Close the flow (it was pushed over Home: the setup card, A2c).
  pop,
}

/// One market C offers, with the fresh Panta price it will be called at.
class FirstCallMarket {
  const FirstCallMarket({
    required this.market,
    required this.sharePrice,
    this.snapshot,
  });
  final VenueMarket market;
  final SharePriceSnapshot sharePrice;
  final MarketSnapshot? snapshot;
}

/// Why sign-in is being asked for, which picks A1's title.
enum SignInReason { call, follow, none }

class OnboardingFlowController extends ChangeNotifier {
  OnboardingFlowController({
    required OnboardingRun run,
    required this.app,
    required this.calls,
    this.session,
    PeopleSuggestionsRepository? suggestions,
    OnboardingStep? resumeAt,
    this.sessionEnded = false,
    this.onExit,
    DateTime Function()? clock,
    this.topicsBudget = const Duration(seconds: 5),
    this.peopleBudget = const Duration(seconds: 5),
    this.firstCallBudget = const Duration(seconds: 6),
  }) : _suggestions =
           suggestions ??
           (calls.repository is PeopleSuggestionsRepository
               ? calls.repository as PeopleSuggestionsRepository
               : null),
       _clock = clock ?? DateTime.now,
       _resumeAt = resumeAt,
       _startRun = run;

  final OnboardingRun _startRun;

  /// The run the current step belongs to. "I already have an account" turns
  /// a first run into a returning one; Back turns it back.
  OnboardingRun get run => _history.isEmpty ? _startRun : _history.last.run;
  final OnboardingController app;
  final CallsProvider calls;
  final ChumbucketSession? session;
  final PeopleSuggestionsRepository? _suggestions;
  final OnboardingStep? _resumeAt;

  /// B1 arrived from a failed or expired restore.
  final bool sessionEnded;

  /// Called once when the run ends.
  final void Function(FlowExit exit)? onExit;
  final DateTime Function() _clock;
  final Duration topicsBudget;
  final Duration peopleBudget;
  final Duration firstCallBudget;

  DateTime get now => _clock();
  AnalyticsRecorder get _analytics => app.analytics;

  bool _disposed = false;
  bool _started = false;
  bool _exited = false;
  late final DateTime _startedAt = now;

  final List<({OnboardingStep step, OnboardingRun run})> _history = [];
  bool _forward = true;
  bool _busy = false;

  StepData _topicsData = StepData.loading;
  StepData _peopleData = StepData.loading;
  StepData _firstCallData = StepData.loading;

  List<TopicCount> _topics = const [];
  final Set<String> _selectedTopics = {};
  List<PersonSuggestion> _people = const [];
  List<PersonSuggestion> _friends = const [];
  final Set<String> _selectedPeople = {};
  final Set<String> _selectedFriends = {};
  bool _friendsLoaded = false;
  List<FirstCallMarket> _firstCallMarkets = const [];
  List<TopCall> _answerable = const [];
  bool _firstCallRefreshing = false;

  CallFeedEntry? _lockedEntry;
  bool _alreadyMode = false;
  bool? _pushLive;
  bool _handleClaimLater = false;
  String? _accountKind;
  FollowsApplied? _applied;
  int _stepsShown = 0;
  int _stepsSkipped = 0;
  final Set<OnboardingStep> _offered = {};

  // ── What screens read ─────────────────────────────────────────────────────

  OnboardingStep get current => _history.last.step;
  bool get forward => _forward;
  bool get busy => _busy;

  /// Back would leave the run (the app at the root of a first run, or the
  /// flow when it was pushed over Home).
  bool get atRoot =>
      !_busy &&
      current != OnboardingStep.onRecord &&
      !(current == OnboardingStep.username && session?.needsUsername == true) &&
      _backTarget() == null;

  bool get canGoBack => !_busy && current.hasBackArrow && _backTarget() != null;
  List<OnboardingStep> get steps => computeSteps(_inputs);
  ({int index, int total})? get progress => progressOf(current, steps);

  StepData get topicsData => _topicsData;
  StepData get peopleData => _peopleData;
  StepData get firstCallData => _firstCallData;
  List<TopicCount> get topics => _topics;
  Set<String> get selectedTopics => Set.unmodifiable(_selectedTopics);
  List<PersonSuggestion> get people => _people;
  List<PersonSuggestion> get friends => _friends;
  Set<String> get selectedPeople => Set.unmodifiable(_selectedPeople);
  Set<String> get selectedFriends => Set.unmodifiable(_selectedFriends);
  List<FirstCallMarket> get firstCallMarkets => _firstCallMarkets;
  List<TopCall> get answerable => _answerable;
  bool get firstCallRefreshing => _firstCallRefreshing;
  CallFeedEntry? get lockedEntry => _lockedEntry;
  bool get alreadyMode => _alreadyMode;
  bool get signedIn => session?.isReady ?? calls.isSignedIn;
  PendingCall? get pendingCall => app.pendingCall;

  SignInReason get signInReason {
    if (app.pendingCall != null) return SignInReason.call;
    if (app.pendingFollowIds.isNotEmpty) return SignInReason.follow;
    return SignInReason.none;
  }

  /// The one person a single pending follow names, for "Sign in to follow
  /// Ada". Null for more than one.
  String? get singlePendingFollowName {
    final ids = app.pendingFollowIds;
    if (ids.length != 1) return null;
    for (final p in [..._people, ..._friends]) {
      if (p.id == ids.single) {
        return shownName(
          displayName: p.person.displayName,
          handle: p.person.handle,
        );
      }
    }
    return null;
  }

  StepInputs get _inputs => _inputsFor(run);

  StepInputs _inputsFor(OnboardingRun run) => StepInputs(
    run: run,
    topics: _topicsData,
    people: _peopleData,
    firstCall: _firstCallData,
    signedIn: signedIn,
    needsUsername: session?.needsUsername ?? false,
    needsHandleClaim: session?.needsHandleClaim ?? false,
    handleClaimLater: _handleClaimLater,
    hasFriends: _friends.isNotEmpty,
    pendingCall: app.pendingCall != null,
    lockedCall: _lockedEntry != null,
    pendingFollows: app.pendingFollowIds.isNotEmpty,
    startAtWelcome: run == OnboardingRun.newUser,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    session?.removeListener(_onSession);
    calls.removeListener(_onCalls);
    super.dispose();
  }

  // ── Start ────────────────────────────────────────────────────────────────

  /// Sets up the run. Called while the host is first built, so everything
  /// that notifies (loads, analytics, the stored stage) happens just after.
  void start() {
    if (_started) return;
    _started = true;
    _selectedTopics.addAll(app.topics);
    _selectedPeople.addAll(app.pendingFollowIds);
    switch (run) {
      case OnboardingRun.newUser:
        break;
      case OnboardingRun.homeSetup:
        _firstCallData = StepData.unavailable;
      case OnboardingRun.upgrade:
        _peopleData = StepData.unavailable;
        _firstCallData = StepData.unavailable;
      case OnboardingRun.claimOnly:
      case OnboardingRun.welcomeBack:
        _topicsData = StepData.unavailable;
        _peopleData = StepData.unavailable;
        _firstCallData = StepData.unavailable;
    }
    final first = _firstStep();
    _history.add((step: first, run: _startRun));
    session?.addListener(_onSession);
    calls.addListener(_onCalls);
    _wasReady = session?.isReady ?? false;
    _wasNeedsUsername = session?.needsUsername ?? false;
    scheduleMicrotask(() {
      // A run that ended before it began shows nothing and records nothing.
      if (_disposed || _endedAtStart) return;
      unawaited(app.startRun(_entryToken()));
      _onEnter(first);
      switch (run) {
        case OnboardingRun.newUser:
          unawaited(_loadTopics());
          unawaited(_loadPeople());
          unawaited(_loadFirstCall());
        case OnboardingRun.homeSetup:
          unawaited(_loadTopics());
          unawaited(_loadPeople());
        case OnboardingRun.upgrade:
          unawaited(_loadTopics());
          if (signedIn) unawaited(_loadFriends());
        case OnboardingRun.claimOnly:
          if (signedIn) unawaited(_loadFriends());
        case OnboardingRun.welcomeBack:
          break;
      }
      _notify();
    });
  }

  String _entryToken() => switch (run) {
    OnboardingRun.newUser => _resumeAt == null ? 'welcome' : 'resume',
    OnboardingRun.welcomeBack => 'welcome_back',
    OnboardingRun.upgrade => 'upgrade',
    OnboardingRun.homeSetup => 'home_card',
    OnboardingRun.claimOnly => 'claim',
  };

  /// The run had nothing left to show when it started (it is finishing).
  /// The host draws the bare canvas rather than flash a step on the way out.
  bool get endedAtStart => _endedAtStart;
  bool _endedAtStart = false;

  OnboardingStep _endAtStart(OnboardingStep placeholder) {
    _endedAtStart = true;
    scheduleMicrotask(() {
      if (!_disposed) unawaited(finish());
    });
    return placeholder;
  }

  OnboardingStep _firstStep() {
    final resume = _resumeAt;
    if (resume != null && run == OnboardingRun.newUser) {
      // A stage that no longer applies (e.g. sign-in, now signed in) resumes
      // at the next one that does. Nothing after it — the run was cut short
      // on "You're on record", or its draft has gone — means the run is over:
      // Home, never Welcome again for someone already signed in.
      final list = computeSteps(_inputs);
      if (list.contains(resume)) return resume;
      return nextStep(resume, list) ?? _endAtStart(resume);
    }
    final list = computeSteps(_inputs);
    if (list.isEmpty) {
      // Nothing left to ask (e.g. the username was claimed meanwhile).
      return _endAtStart(switch (run) {
        OnboardingRun.welcomeBack => OnboardingStep.welcomeBack,
        OnboardingRun.upgrade => OnboardingStep.upgrade,
        OnboardingRun.newUser => OnboardingStep.welcome,
        _ => OnboardingStep.username,
      });
    }
    return list.first;
  }

  // ── Navigation ───────────────────────────────────────────────────────────

  void setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    _notify();
  }

  /// Leaves [current] with [outcome] and goes to the next step of the run, or
  /// ends the run.
  void advance({String outcome = 'continued', String? reason, int? count}) {
    if (_exited) return;
    final leaving = current;
    _analytics.record(
      OnboardingAnalyticsEvents.stepCompleted(
        step: leaving.wire,
        outcome: outcome,
        reason: reason,
        selectedCount: count,
      ),
    );
    if (outcome == 'auto_skipped') _stepsSkipped++;
    final next = nextStep(leaving, steps);
    if (next == null) {
      unawaited(finish());
      return;
    }
    _go(next, forward: true);
  }

  /// Jumps to [step] (e.g. sign-in after a draft, R after a lock).
  void goTo(OnboardingStep step) {
    if (_exited || current == step) return;
    _go(step, forward: true);
  }

  void _go(OnboardingStep step, {required bool forward, OnboardingRun? inRun}) {
    _forward = forward;
    _history.add((step: step, run: inRun ?? run));
    _onEnter(step);
    _notify();
  }

  /// "I already have an account" on Welcome: Welcome back (B1). Back returns
  /// to Welcome.
  void haveAccount() {
    _analytics.record(
      OnboardingAnalyticsEvents.stepCompleted(
        step: current.wire,
        outcome: 'have_account',
      ),
    );
    _go(
      OnboardingStep.welcomeBack,
      forward: true,
      inRun: OnboardingRun.welcomeBack,
    );
  }

  /// The history entry Back returns to: the latest earlier step that still
  /// belongs to its run (sign-in drops out once signed in).
  int? _backTarget() {
    for (var i = _history.length - 2; i >= 0; i--) {
      final entry = _history[i];
      final valid = computeSteps(_inputsFor(entry.run));
      if (valid.contains(entry.step)) return i;
    }
    return null;
  }

  /// System Back or the arrow. False when the route itself should pop (the
  /// root step: the app exits).
  bool back() {
    if (_busy) return true;
    if (current == OnboardingStep.onRecord) {
      unawaited(finish());
      return true;
    }
    if (current == OnboardingStep.username && session?.needsUsername == true) {
      // Leaving "Claim your @username" abandons that sign-in.
      unawaited(switchSignIn());
      return true;
    }
    final target = _backTarget();
    if (target == null) return _history.length > 1;
    _history.removeRange(target + 1, _history.length);
    _forward = false;
    _onEnter(current, revisit: true);
    _notify();
    return true;
  }

  void _onEnter(OnboardingStep step, {bool revisit = false}) {
    unawaited(app.setStage(step));
    if (!revisit && _offered.add(step)) _stepsShown++;
    final p = progressOf(step, steps);
    // R's view is recorded once it knows whether pushes are live
    // ([notePushState]).
    if (step != OnboardingStep.onRecord) {
      _recordStepViewed(step, p);
    }
    if (step == OnboardingStep.firstCall || step == OnboardingStep.resumeCall) {
      unawaited(refreshFirstCall());
    }
    _skipIfUnavailable();
  }

  void _recordStepViewed(OnboardingStep step, ({int index, int total})? p) {
    _analytics.record(
      OnboardingAnalyticsEvents.stepViewed(
        step: step.wire,
        index: p?.index,
        total: p?.total,
        available: switch (step) {
          OnboardingStep.topics => _topicsData == StepData.available,
          OnboardingStep.people => _peopleData == StepData.available,
          OnboardingStep.firstCall => _firstCallData == StepData.available,
          _ => null,
        },
        reason: step == OnboardingStep.signIn ? signInReason.name : null,
        suggestions: step == OnboardingStep.people ? _people.length : null,
        friends: step == OnboardingStep.friends ? _friends.length : null,
        markets:
            step == OnboardingStep.firstCall ? _firstCallMarkets.length : null,
        answerable:
            step == OnboardingStep.firstCall ? _answerable.length : null,
        path:
            step == OnboardingStep.username
                ? (session?.needsUsername == true ? 'new' : 'carried_over')
                : null,
      ),
    );
  }

  /// When the step on screen has turned out to have nothing real to show.
  void _skipIfUnavailable() {
    final step = current;
    final data = switch (step) {
      OnboardingStep.topics => _topicsData,
      OnboardingStep.people => _peopleData,
      OnboardingStep.firstCall => _firstCallData,
      _ => null,
    };
    if (data != StepData.unavailable) return;
    // On a later frame: never navigate in the middle of a build.
    scheduleMicrotask(() {
      if (_disposed || _exited || current != step) return;
      advance(outcome: 'auto_skipped', reason: 'thin_data');
    });
  }

  // ── Data: topics ─────────────────────────────────────────────────────────

  /// Resolves when [done] is true or [budget] passes. True when done.
  Future<bool> _waitFor(bool Function() done, Duration budget) async {
    if (done()) return true;
    final completer = Completer<bool>();
    void check() {
      if (!completer.isCompleted && done()) completer.complete(true);
    }

    calls.addListener(check);
    final timer = Timer(budget, () {
      if (!completer.isCompleted) completer.complete(false);
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      calls.removeListener(check);
    }
  }

  bool _catalogRequested = false;

  /// Loads the open catalog once (it is shared with Markets and Welcome) and
  /// waits for it, at most [budget].
  Future<void> _ensureCatalog(Duration budget) async {
    if (!_catalogRequested) {
      _catalogRequested = true;
      unawaited(calls.loadOpenMarkets());
    }
    await _waitFor(() => !calls.isLoadingOpenMarkets, budget);
  }

  Future<void> _loadTopics() async {
    await _ensureCatalog(topicsBudget);
    if (_disposed) return;
    final ok = !calls.isLoadingOpenMarkets;
    final topics =
        ok ? topicsFrom(calls.openMarkets, now) : const <TopicCount>[];
    _topics = topics;
    _topicsData =
        ok && topicsWorthShowing(topics)
            ? StepData.available
            : StepData.unavailable;
    // Topics chosen earlier that no longer have open markets stay chosen —
    // they come back with the markets — but only live ones are shown.
    _notify();
    _skipIfUnavailable();
  }

  void toggleTopic(String slug) {
    final selected = !_selectedTopics.contains(slug);
    selected ? _selectedTopics.add(slug) : _selectedTopics.remove(slug);
    _analytics.record(
      OnboardingAnalyticsEvents.topicToggled(
        category: slug,
        selected: selected,
      ),
    );
    _notify();
  }

  /// Saves the choice and moves on.
  Future<void> completeTopics() async {
    final count =
        _selectedTopics.where((s) => _topics.any((t) => t.slug == s)).length;
    await app.setTopics(_selectedTopics);
    advance(outcome: count == 0 ? 'skipped' : 'continued', count: count);
  }

  // ── Data: people ─────────────────────────────────────────────────────────

  Future<PeopleSuggestions?> _fetchSuggestions(Duration budget) async {
    final repo = _suggestions;
    if (repo != null) {
      try {
        return await repo.fetchSuggestedPeople(limit: 10).timeout(budget);
      } on PeopleSuggestionsUnavailable {
        // Fall through to the composed list below.
      } on TimeoutException {
        return null;
      } catch (_) {
        return null;
      }
    }
    if (!calls.supportsPeople) return null;
    try {
      await Future.wait([
        calls.loadTopCalls(),
        calls.loadLeaderboard(LeaderboardWindow.all),
      ]).timeout(budget);
    } catch (_) {
      // Whatever arrived is used below.
    }
    return PeopleSuggestions(
      friends: const [],
      people: composeSuggestions(
        allTime: calls.leaderboard(LeaderboardWindow.all),
        top: calls.topCalls ?? const [],
        viewerUserId: calls.viewerUserId,
        now: now,
      ),
      servedAt: now.toUtc().millisecondsSinceEpoch,
    );
  }

  List<PersonSuggestion> _showable(List<PersonSuggestion> list) => [
    for (final p in list)
      if (p.id != calls.viewerUserId &&
          isShowablePerson(
            displayName: p.person.displayName,
            handle: p.person.handle,
          ))
        p,
  ];

  Future<void> _loadPeople() async {
    final result = await _fetchSuggestions(peopleBudget);
    if (_disposed) return;
    _people = _showable(result?.people ?? const []);
    if (signedIn) {
      _friends = _showable(result?.friends ?? const []);
      _friendsLoaded = true;
    }
    _selectedPeople.removeWhere(
      (id) =>
          !_people.any((p) => p.id == id) && !app.pendingFollowIds.contains(id),
    );
    _peopleData =
        peopleWorthShowing(suggestions: _people.length, friends: 0)
            ? StepData.available
            : StepData.unavailable;
    _notify();
    _skipIfUnavailable();
  }

  /// After sign-in: the account's friends from the old app, for the friends
  /// variant of P. Never preselected (a deliberate change from spec §6 P):
  /// the old client wrote those rows and accepted them both ways without
  /// asking (prod readiness M10), so they are not consent to follow anyone.
  Future<void> _loadFriends() async {
    if (_friendsLoaded) return;
    _friendsLoaded = true;
    final result = await _fetchSuggestions(peopleBudget);
    if (_disposed) return;
    _friends =
        _showable(
          result?.friends ?? const [],
        ).where((f) => !f.person.viewerIsFollowing).toList();
    _notify();
  }

  void togglePerson(String id, {required bool friend}) {
    final set = friend ? _selectedFriends : _selectedPeople;
    final selected = !set.contains(id);
    selected ? set.add(id) : set.remove(id);
    _analytics.record(
      OnboardingAnalyticsEvents.followToggled(
        personId: id,
        source: friend ? 'friend' : 'caller',
        selected: selected,
      ),
    );
    if (!friend && !signedIn) unawaited(app.setPendingFollows(_selectedPeople));
    _notify();
  }

  void setAllPeople(bool selected, {required bool friend}) {
    final set = friend ? _selectedFriends : _selectedPeople;
    final ids = (friend ? _friends : _people).map((p) => p.id);
    selected ? set.addAll(ids) : set.removeAll(ids);
    if (!friend && !signedIn) unawaited(app.setPendingFollows(_selectedPeople));
    _notify();
  }

  /// Continue on P (callers or friends).
  Future<void> completePeople({required bool friend}) async {
    final chosen = (friend ? _selectedFriends : _selectedPeople).toSet();
    if (chosen.isNotEmpty) {
      await app.setPendingFollows({...app.pendingFollowIds, ...chosen});
      if (signedIn) unawaited(_applyFollows());
    }
    if (!friend && chosen.isEmpty && _topicsSkipped) {
      unawaited(app.noteSetupSkipped());
    }
    advance(
      outcome: chosen.isEmpty ? 'skipped' : 'continued',
      count: chosen.length,
    );
  }

  bool get _topicsSkipped =>
      _topicsData == StepData.available && _selectedTopics.isEmpty;

  Future<void> _applyFollows() async {
    // The session says "ready" before the calls slice knows the account:
    // main.dart binds it in a ProxyProvider's update, on the next build. Wait
    // for that rather than find "signed out" and apply nothing.
    if (!calls.isSignedIn &&
        !await _waitFor(() => calls.isSignedIn, const Duration(seconds: 5))) {
      return;
    }
    if (_disposed) return;
    final result = await app.applyPendingFollows(calls);
    if (result == null || _disposed) return;
    final previous = _applied;
    _applied = FollowsApplied(
      requested: (previous?.requested ?? 0) + result.requested,
      succeeded: [...?previous?.succeeded, ...result.succeeded],
      failed: [...?previous?.failed, ...result.failed],
    );
    _notify();
  }

  FollowsApplied? get followsApplied => _applied;

  // ── Data: first call ─────────────────────────────────────────────────────

  Future<void> _loadFirstCall() async {
    await Future.wait([
      _ensureCatalog(firstCallBudget),
      if (calls.supportsPeople)
        calls.loadTopCalls().timeout(firstCallBudget, onTimeout: () {}),
    ]);
    if (_disposed) return;
    await _priceCandidates(firstCallBudget);
    if (_disposed) return;
    _firstCallData =
        _firstCallMarkets.isNotEmpty || _answerable.isNotEmpty
            ? StepData.available
            : StepData.unavailable;
    _notify();
    _skipIfUnavailable();
  }

  /// Loads fresh prices for the best-ranked candidates and keeps the first
  /// three whose Panta price is under ten minutes old.
  Future<void> _priceCandidates(Duration budget) async {
    // After sign-in the waiting draft has its own card: its market is not
    // offered a second time beside it (one call per market). Before sign-in
    // (Back from A1 to change the pick) everything stays on offer.
    final draftMarket = signedIn ? app.pendingCall?.marketId : null;
    final candidates =
        firstCallCandidates(
          calls.openMarkets,
          topics: _selectedTopics,
          now: now,
        ).where((m) => m.id != draftMarket).take(6).toList();
    final details = await Future.wait([
      for (final market in candidates)
        calls
            .loadMarketDetail(market.id, force: true)
            .timeout(budget, onTimeout: () => null)
            .catchError((Object _) => null),
    ]);
    final kept = <FirstCallMarket>[];
    for (var i = 0; i < candidates.length; i++) {
      final detail = details[i] ?? calls.marketDetail(candidates[i].id);
      final price = detail?.sharePrice;
      if (detail == null || price == null || !price.isUsableAt(now)) continue;
      if (!isCallReadyMarket(detail.market, now)) continue;
      if (detail.viewerHasCalled) continue;
      kept.add(
        FirstCallMarket(
          market: detail.market,
          sharePrice: price,
          snapshot: detail.snapshot,
        ),
      );
      if (kept.length == kFirstCallMarkets) break;
    }
    _firstCallMarkets = kept;
    _answerable = answerableCalls(
      (calls.topCalls ?? const <TopCall>[]).where(
        (t) => t.market.id != draftMarket,
      ),
      viewerUserId: calls.viewerUserId,
      preferredAuthors: {..._selectedPeople, ...app.pendingFollowIds},
      now: now,
    );
  }

  /// Re-ranks C for the topics just chosen and re-checks prices (they go
  /// stale in ten minutes).
  Future<void> refreshFirstCall() async {
    if (_firstCallRefreshing || _firstCallData == StepData.unavailable) return;
    if (run != OnboardingRun.newUser) return;
    _firstCallRefreshing = true;
    _notify();
    await _ensureCatalog(firstCallBudget);
    await _priceCandidates(firstCallBudget);
    _firstCallRefreshing = false;
    if (_disposed) return;
    if (current == OnboardingStep.firstCall &&
        _firstCallMarkets.isEmpty &&
        _answerable.isEmpty) {
      _firstCallData = StepData.unavailable;
    }
    _notify();
    _skipIfUnavailable();
  }

  // ── Drafts and locks ─────────────────────────────────────────────────────

  /// A signed-out Lock: keep the draft on the phone and ask for sign-in.
  Future<void> saveDraftAndSignIn(PendingCall draft) async {
    await app.saveDraft(draft);
    _analytics.record(
      OnboardingAnalyticsEvents.firstCallOpened(
        kind: draft.kind.wire,
        marketId: draft.marketId,
      ),
    );
    if (signedIn) {
      goTo(OnboardingStep.resumeCall);
    } else {
      goTo(OnboardingStep.signIn);
    }
  }

  /// A call was locked: R shows the server's own record of it.
  Future<void> locked(CallFeedEntry entry, {bool already = false}) async {
    _lockedEntry = entry;
    _alreadyMode = already;
    await app.clearDraft();
    if (!already) {
      _analytics.record(
        OnboardingAnalyticsEvents.stepCompleted(
          step: current.wire,
          outcome: 'locked',
        ),
      );
    }
    goTo(OnboardingStep.onRecord);
  }

  /// R found out whether this server sends pushes (for its step_viewed).
  void notePushState({required bool live}) {
    if (_pushLive != null) return;
    _pushLive = live;
    if (current != OnboardingStep.onRecord) return;
    _analytics.record(
      OnboardingAnalyticsEvents.stepViewed(
        step: OnboardingStep.onRecord.wire,
        mode: _alreadyMode ? 'already' : 'new',
        pushLive: live,
      ),
    );
  }

  /// "I'll do this later" on C.
  void callLater() {
    if (current == OnboardingStep.resumeCall) {
      unawaited(app.clearDraft());
    }
    advance(outcome: 'later');
  }

  // ── Session ──────────────────────────────────────────────────────────────

  bool _wasReady = false;
  bool _wasNeedsUsername = false;

  void _onSession() {
    final s = session;
    if (s == null || _disposed || _exited) return;
    final ready = s.isReady;
    final needsUsername = s.needsUsername;
    if (needsUsername && !_wasNeedsUsername) {
      _accountKind = 'new';
    }
    if (ready && !_wasReady) {
      _accountKind ??= s.needsHandleClaim ? 'carried_over' : 'existing';
      final method = s.lastSignInMethod;
      if (method != null &&
          (current == OnboardingStep.signIn ||
              current == OnboardingStep.welcomeBack ||
              current == OnboardingStep.upgrade ||
              current == OnboardingStep.username)) {
        _analytics.record(
          OnboardingAnalyticsEvents.signInCompleted(
            method: method.wire,
            account: _accountKind!,
          ),
        );
      }
      unawaited(_applyFollows());
      if (run != OnboardingRun.welcomeBack && run != OnboardingRun.homeSetup) {
        unawaited(_loadFriends());
      }
    }
    _wasReady = ready;
    _wasNeedsUsername = needsUsername;

    // Sign-in finished on a step that was waiting for it. U1 never goes on
    // to make a new account: the screen handles a wallet with no profile.
    final waitingUpgrade = run == OnboardingRun.upgrade && !ready;
    if ((ready || needsUsername) &&
        !waitingUpgrade &&
        (current == OnboardingStep.signIn ||
            current == OnboardingStep.welcomeBack ||
            current == OnboardingStep.upgrade)) {
      scheduleMicrotask(() {
        if (_disposed || _exited) return;
        if (current == OnboardingStep.signIn ||
            current == OnboardingStep.welcomeBack ||
            current == OnboardingStep.upgrade) {
          advance(outcome: 'signed_in');
        }
      });
    } else if (ready &&
        !s.needsHandleClaim &&
        current == OnboardingStep.username) {
      // Claimed (or it turned out to be claimed already): on with the run.
      scheduleMicrotask(() {
        if (_disposed || _exited || current != OnboardingStep.username) return;
        advance(outcome: 'claimed');
      });
    }
    _notify();
  }

  void _onCalls() {
    // Price ages and the viewer change under C; nothing to do eagerly.
  }

  /// A2c "Later": once per install; Profile keeps its row.
  Future<void> claimLater() async {
    _handleClaimLater = true;
    await app.deferHandleClaim();
    advance(outcome: 'later');
  }

  /// A2's "Use a different sign-in": back to the doors.
  Future<void> switchSignIn() async {
    _analytics.record(
      OnboardingAnalyticsEvents.stepCompleted(
        step: OnboardingStep.username.wire,
        outcome: 'switched_sign_in',
      ),
    );
    await session?.signOut();
    if (_disposed || _exited) return;
    final door = _history.lastIndexWhere(
      (e) =>
          e.step == OnboardingStep.signIn ||
          e.step == OnboardingStep.welcomeBack ||
          e.step == OnboardingStep.upgrade,
    );
    if (door >= 0) {
      _history.removeRange(door + 1, _history.length);
      _forward = false;
      _onEnter(current, revisit: true);
      _notify();
    } else {
      _go(OnboardingStep.signIn, forward: true);
    }
  }

  // ── Ends ─────────────────────────────────────────────────────────────────

  /// The run is over: Home (or close, when it was pushed over Home).
  Future<void> finish() async {
    if (_exited) return;
    _exited = true;
    final arrival = HomeArrival(
      followed: _applied?.succeeded.length ?? 0,
      failed: _applied?.failed.length ?? 0,
      madeCall: _lockedEntry != null && !_alreadyMode,
    );
    if (run == OnboardingRun.homeSetup) {
      await app.finishHomeCard();
      app.setArrival(arrival);
    } else if (run == OnboardingRun.claimOnly) {
      app.setArrival(arrival);
    } else {
      await app.complete(arrival: arrival);
    }
    _analytics.record(
      OnboardingAnalyticsEvents.completed(
        path: run.name,
        madeCall: arrival.madeCall,
        follows: arrival.followed,
        stepsShown: _stepsShown,
        stepsSkipped: _stepsSkipped,
        durationMs: now.difference(_startedAt).inMilliseconds,
      ),
    );
    onExit?.call(
      run == OnboardingRun.homeSetup || run == OnboardingRun.claimOnly
          ? FlowExit.pop
          : FlowExit.home,
    );
  }

  /// "Not now" on sign-in, "Look around first" on B1, "Not now" on U1: Home,
  /// signed out. What was chosen stays for 24 hours (the draft) or 7 days
  /// (follows) and is offered again at the next sign-in.
  Future<void> lookAround({String outcome = 'not_now'}) async {
    if (_exited) return;
    _analytics.record(
      OnboardingAnalyticsEvents.stepCompleted(
        step: current.wire,
        outcome: outcome,
      ),
    );
    _exited = true;
    if (run == OnboardingRun.upgrade) {
      await app.markUpgradeIntroSeen();
      await app.complete();
    } else if (run == OnboardingRun.homeSetup) {
      app.setArrival(const HomeArrival());
    } else {
      await app.lookAround(arrival: const HomeArrival());
    }
    onExit?.call(run == OnboardingRun.homeSetup ? FlowExit.pop : FlowExit.home);
  }

  /// Sign-in methods, for "Last used" analytics from the panel.
  void signInStarted(SignInMethod method, {required bool lastUsed}) {
    _analytics.record(
      OnboardingAnalyticsEvents.signInStarted(
        method: method.wire,
        context: switch (run) {
          OnboardingRun.welcomeBack => 'welcome_back',
          OnboardingRun.upgrade => 'upgrade',
          _ => 'onboarding',
        },
        lastUsed: lastUsed,
      ),
    );
  }

  void signInFailed(SignInMethod method, String reason) {
    _analytics.record(
      OnboardingAnalyticsEvents.signInFailed(
        method: method.wire,
        reason: reason,
      ),
    );
  }
}
