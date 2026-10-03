/// Onboarding's app-wide state: what this install has done, the topics it
/// chose, and what is waiting on a sign-in (follows, a draft call). Provided
/// above Home so the flow, Home's "Make Home yours" card, Markets' "For you"
/// and Settings all read one source (onboarding spec §12).
///
/// The per-run step machine is `OnboardingFlowController`; this class only
/// remembers.
library;

import 'package:flutter/foundation.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';

/// What applying the follows chosen before sign-in came to.
class FollowsApplied {
  const FollowsApplied({
    required this.requested,
    required this.succeeded,
    required this.failed,
  });

  final int requested;
  final List<String> succeeded;
  final List<String> failed;
}

/// What Home should do the first time it shows after a run.
class HomeArrival {
  const HomeArrival({
    this.followed = 0,
    this.failed = 0,
    this.madeCall = false,
    this.restored = false,
    this.restoredAs,
  });

  /// Follows applied during the run, and those that could not be.
  final int followed;
  final int failed;
  final bool madeCall;

  /// The session came back from the phone's backup (B2), and as whom: the
  /// @handle the server confirmed, or null to just say "Welcome back."
  final bool restored;
  final String? restoredAs;
}

class OnboardingController extends ChangeNotifier {
  OnboardingController({
    OnboardingStore store = const OnboardingStore(),
    DateTime Function()? clock,
    AnalyticsRecorder? analytics,
  }) : _store = store,
       _clock = clock ?? DateTime.now,
       _analytics = analytics;

  final OnboardingStore _store;
  final DateTime Function() _clock;
  final AnalyticsRecorder? _analytics;

  AnalyticsRecorder get analytics => _analytics ?? AnalyticsRecorder.instance;
  DateTime get now => _clock();

  bool _disposed = false;
  Future<void>? _loading;
  bool _loaded = false;
  OnboardingRecord _record = const OnboardingRecord();
  Set<String> _topics = const {};
  PendingFollows? _pendingFollows;
  PendingCall? _pendingCall;
  bool _legacyCompleted = false;
  bool _homeCardCountedThisSession = false;
  HomeArrival? _arrival;
  Future<FollowsApplied?>? _applying;

  bool get loaded => _loaded;
  OnboardingRecord get record => _record;
  OnboardingStatus get status => _record.status;

  /// Chosen topic slugs.
  Set<String> get topics => _topics;

  /// People chosen while signed out, waiting for sign-in.
  Set<String> get pendingFollowIds =>
      _pendingFollows?.isLiveAt(now) == true
          ? _pendingFollows!.ids.toSet()
          : const {};

  /// The call composed while signed out, if still within its 24 hours.
  PendingCall? get pendingCall =>
      _pendingCall?.isLiveAt(now) == true ? _pendingCall : null;

  /// The old carousel was completed on this install (read only).
  bool get legacyOnboardingCompleted => _legacyCompleted;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Reads everything once. Safe to call repeatedly.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final results = await Future.wait<Object?>([
      _store.readRecord(),
      _store.readTopics(),
      _store.readPendingFollows(now),
      _store.readPendingCall(now),
      _store.legacyOnboardingCompleted(),
    ]);
    if (_disposed) return;
    _record = results[0] as OnboardingRecord;
    _topics = (results[1] as List<String>).toSet();
    _pendingFollows = results[2] as PendingFollows?;
    _pendingCall = results[3] as PendingCall?;
    _legacyCompleted = results[4] as bool;
    _loaded = true;
    _notify();
  }

  Future<void> _save(OnboardingRecord next) async {
    _record = next;
    _notify();
    await _store.writeRecord(next);
  }

  int get _nowMs => now.toUtc().millisecondsSinceEpoch;

  // ── The run ──────────────────────────────────────────────────────────────

  Future<void> startRun(String entry) async {
    analytics.record(OnboardingAnalyticsEvents.started(entry: entry));
    if (_record.status == OnboardingStatus.completed) return;
    await _save(
      _record.copyWith(
        status: OnboardingStatus.inProgress,
        startedAt: _record.startedAt ?? _nowMs,
      ),
    );
  }

  /// Remembers where a run is, so it can resume after process death.
  Future<void> setStage(OnboardingStep step) async {
    if (_record.status != OnboardingStatus.inProgress) return;
    await _save(_record.copyWith(stage: step.wire, stageAt: _nowMs));
  }

  Future<void> complete({HomeArrival? arrival}) async {
    if (arrival != null) _arrival = arrival;
    await _save(
      _record.copyWith(
        status: OnboardingStatus.completed,
        clearStage: true,
        completedAt: _nowMs,
      ),
    );
  }

  /// "Not now" on sign-in: browse signed out. Home offers the setup card.
  Future<void> lookAround({HomeArrival? arrival}) async {
    if (arrival != null) _arrival = arrival;
    await _save(
      _record.copyWith(status: OnboardingStatus.lookedAround, clearStage: true),
    );
  }

  /// A shared link opened first: onboarding waits (Home's card offers it).
  Future<void> defer() async {
    if (_record.status != OnboardingStatus.fresh) return;
    await _save(_record.copyWith(status: OnboardingStatus.deferred));
  }

  Future<void> markUpgradeIntroSeen() =>
      _save(_record.copyWith(upgradeIntroSeen: true));

  Future<void> deferHandleClaim() =>
      _save(_record.copyWith(handleClaimDeferred: true));

  /// What Home should do on its next first frame (switch to Following, show
  /// the follows snackbar). Read once.
  HomeArrival? takeArrival() {
    final arrival = _arrival;
    _arrival = null;
    return arrival;
  }

  void setArrival(HomeArrival arrival) => _arrival = arrival;

  // ── Topics ───────────────────────────────────────────────────────────────

  Future<void> setTopics(Iterable<String> slugs) async {
    _topics = slugs.map((s) => s.trim().toLowerCase()).toSet();
    _notify();
    await _store.writeTopics(_topics.toList()..sort());
    await _save(_record.copyWith(forYouPending: _topics.isNotEmpty));
  }

  /// Markets opened on "For you" once; from now on it remembers its filter.
  Future<void> consumeForYou() async {
    if (!_record.forYouPending) return;
    await _save(_record.copyWith(forYouPending: false));
  }

  // ── Pending follows ──────────────────────────────────────────────────────

  Future<void> setPendingFollows(Iterable<String> ids) async {
    final list = ids.toSet().toList()..sort();
    _pendingFollows = list.isEmpty ? null : PendingFollows(list, _nowMs);
    _notify();
    await _store.writePendingFollows(_pendingFollows);
  }

  /// Applies the follows chosen before sign-in, once the account is ready.
  /// Exactly once: concurrent callers share one attempt, and each person is
  /// followed through the server's idempotent follow. A failure is retried
  /// once; what still fails is reported, not retried forever.
  Future<FollowsApplied?> applyPendingFollows(CallsProvider calls) =>
      _applying ??= _apply(calls).whenComplete(() => _applying = null);

  Future<FollowsApplied?> _apply(CallsProvider calls) async {
    final ids = pendingFollowIds.toList()..sort();
    if (ids.isEmpty || !calls.isSignedIn) return null;
    final succeeded = <String>[];
    final failed = <String>[];
    for (final id in ids) {
      if (id == calls.viewerUserId) {
        succeeded.add(id);
        continue;
      }
      var done = false;
      for (var attempt = 0; attempt < 2 && !done; attempt++) {
        try {
          await calls.followPersonById(id);
          done = true;
        } on CallsRejectedException {
          // A refusal (the person is gone, or it is the viewer) will refuse
          // again; it is not retried.
          break;
        } catch (_) {
          // Network or server: try once more.
        }
      }
      (done ? succeeded : failed).add(id);
    }
    _pendingFollows = null;
    _notify();
    await _store.writePendingFollows(null);
    analytics.record(
      OnboardingAnalyticsEvents.followsApplied(
        requested: ids.length,
        succeeded: succeeded.length,
        failed: failed.length,
      ),
    );
    return FollowsApplied(
      requested: ids.length,
      succeeded: succeeded,
      failed: failed,
    );
  }

  // ── The draft call ───────────────────────────────────────────────────────

  Future<void> saveDraft(PendingCall call) async {
    _pendingCall = call;
    _notify();
    await _store.writePendingCall(call);
  }

  Future<void> clearDraft() async {
    if (_pendingCall == null) return;
    _pendingCall = null;
    _notify();
    await _store.writePendingCall(null);
  }

  // ── Home's "Make Home yours" card (K1) ───────────────────────────────────

  static const int maxHomeCardShows = 3;
  static const int maxHomeCardDeclines = 2;

  /// Shown to people who skipped setting Home up: a link opened first, they
  /// chose to look around, or they skipped topics and people both. At most
  /// three sessions; gone after "Not now" twice or once set up.
  bool get homeCardEligible {
    if (!_loaded || _homeCardHiddenThisSession) return false;
    final skipped =
        _record.status == OnboardingStatus.deferred ||
        _record.status == OnboardingStatus.lookedAround ||
        _record.setupSkipped;
    return skipped &&
        !_record.homeCardDone &&
        _record.homeCardDeclines < maxHomeCardDeclines &&
        (_record.homeCardShows < maxHomeCardShows ||
            _homeCardCountedThisSession);
  }

  bool _homeCardHiddenThisSession = false;

  /// Counts this app session as one showing (at most once per session).
  Future<void> noteHomeCardShown() async {
    if (_homeCardCountedThisSession) return;
    _homeCardCountedThisSession = true;
    await _save(_record.copyWith(homeCardShows: _record.homeCardShows + 1));
  }

  Future<void> declineHomeCard() async {
    _homeCardHiddenThisSession = true;
    await _save(
      _record.copyWith(homeCardDeclines: _record.homeCardDeclines + 1),
    );
  }

  /// "Set up" ran to the end: the card is done for good.
  Future<void> finishHomeCard() async {
    _homeCardHiddenThisSession = true;
    await _save(_record.copyWith(homeCardDone: true));
  }

  /// Topics and people were both offered in a run and both skipped.
  Future<void> noteSetupSkipped() =>
      _save(_record.copyWith(setupSkipped: true));

  // ── Sign-out ─────────────────────────────────────────────────────────────

  /// What waited on the account goes; topics and the status stay.
  Future<void> clearForSignOut() async {
    _pendingFollows = null;
    _pendingCall = null;
    _arrival = null;
    _notify();
    await _store.clearForSignOut();
  }

  /// For screens that need the store directly (the flow's own reads).
  OnboardingStore get store => _store;

  /// Records one onboarding analytics event. Never throws.
  void track(AnalyticsEvent event) => analytics.record(event);
}
