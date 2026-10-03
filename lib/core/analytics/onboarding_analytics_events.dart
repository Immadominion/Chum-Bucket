/// Typed constructors for the onboarding funnel (onboarding spec §13.4).
///
/// Same rules as `analytics_events.dart`: no free text, no handle, no name, no
/// thesis, no wallet, no email. Every value is a bool, a finite number or a
/// short whitespace-free token, and [AnalyticsPrivacyGuard] still checks each
/// one before a sink sees it. Feature enums are passed as their wire tokens so
/// `lib/core` imports no feature.
///
/// Funnel to read: `onboarding_step_viewed{welcome}` → `…completed{welcome,
/// get_started}` → topics → first call opened → `sign_in_started` →
/// `sign_in_completed` → `username_claimed` → `call_created{surface:
/// onboarding}` (activation) → `notification_permission_result{granted}`.
library;

import 'package:chumbucket/core/analytics/analytics_event.dart';

int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

/// Property keys used only by the onboarding events. Ids reuse
/// [AnalyticsProps] so a person id is one dimension everywhere.
abstract final class OnboardingProps {
  static const String entry = 'entry';
  static const String step = 'step';
  static const String index = 'index';
  static const String total = 'total';
  static const String available = 'available';
  static const String reason = 'reason';
  static const String selectedCount = 'selectedCount';
  static const String source = 'source';
  static const String count = 'count';
  static const String category = 'category';
  static const String selected = 'selected';
  static const String requested = 'requested';
  static const String succeeded = 'succeeded';
  static const String failed = 'failed';
  static const String kind = 'kind';
  static const String method = 'method';
  static const String context = 'context';
  static const String lastUsed = 'lastUsed';
  static const String account = 'account';
  static const String path = 'path';
  static const String usedSuggestion = 'usedSuggestion';
  static const String suggestionSource = 'suggestionSource';
  static const String attempts = 'attempts';
  static const String trigger = 'trigger';
  static const String result = 'result';
  static const String stage = 'stage';
  static const String madeCall = 'madeCall';
  static const String follows = 'follows';
  static const String stepsShown = 'stepsShown';
  static const String stepsSkipped = 'stepsSkipped';
  static const String durationMs = 'durationMs';
  static const String mode = 'mode';
  static const String pushLive = 'pushLive';
  static const String suggestions = 'suggestions';
  static const String friends = 'friends';
  static const String markets = 'markets';
  static const String answerable = 'answerable';
}

AnalyticsEvent _repeatable(
  AnalyticsEventName name,
  Map<String, Object?> props,
  List<Object?> parts,
  int? occurredAtMs,
) {
  final at = occurredAtMs ?? _now();
  return AnalyticsEvent.internal(
    name: name,
    props: props,
    dedupeParts: [...parts, at],
    dedupePolicy: AnalyticsDedupePolicy.perOccurrence,
    occurredAtMs: at,
  );
}

abstract final class OnboardingAnalyticsEvents {
  /// The flow began. [entry]: `welcome`, `welcome_back`, `upgrade`,
  /// `home_card`, `resume`, `claim`.
  static AnalyticsEvent started({required String entry, int? occurredAtMs}) =>
      _repeatable(
        AnalyticsEventName.onboardingStarted,
        {OnboardingProps.entry: entry},
        [entry],
        occurredAtMs,
      );

  /// A step came on screen. [index]/[total] are 1-based positions among the
  /// progress steps of this run, absent for steps without progress.
  static AnalyticsEvent stepViewed({
    required String step,
    int? index,
    int? total,
    bool? available,
    String? reason,
    String? mode,
    String? path,
    bool? pushLive,
    int? suggestions,
    int? friends,
    int? markets,
    int? answerable,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.onboardingStepViewed,
    {
      OnboardingProps.step: step,
      OnboardingProps.index: index,
      OnboardingProps.total: total,
      OnboardingProps.available: available,
      OnboardingProps.reason: reason,
      OnboardingProps.mode: mode,
      OnboardingProps.path: path,
      OnboardingProps.pushLive: pushLive,
      OnboardingProps.suggestions: suggestions,
      OnboardingProps.friends: friends,
      OnboardingProps.markets: markets,
      OnboardingProps.answerable: answerable,
    },
    [step],
    occurredAtMs,
  );

  /// A step was left. [outcome] e.g. `continued`, `skipped`, `auto_skipped`,
  /// `get_started`, `have_account`, `locked`, `later`, `signed_in`,
  /// `not_now`, `claimed`, `switched_sign_in`.
  static AnalyticsEvent stepCompleted({
    required String step,
    required String outcome,
    String? reason,
    int? selectedCount,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.onboardingStepCompleted,
    {
      OnboardingProps.step: step,
      AnalyticsProps.outcome: outcome,
      OnboardingProps.reason: reason,
      OnboardingProps.selectedCount: selectedCount,
    },
    [step, outcome],
    occurredAtMs,
  );

  /// Which source filled Welcome's live strip: `top`, `feed`, `markets` or
  /// `none`, and how many real items it showed.
  static AnalyticsEvent welcomeLive({
    required String source,
    required int count,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.onboardingWelcomeLive,
    {OnboardingProps.source: source, OnboardingProps.count: count},
    [source],
    occurredAtMs,
  );

  /// [category] is the venue's category slug, e.g. `pop-culture`.
  static AnalyticsEvent topicToggled({
    required String category,
    required bool selected,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.onboardingTopicToggled,
    {OnboardingProps.category: category, OnboardingProps.selected: selected},
    [category, selected],
    occurredAtMs,
  );

  /// [source]: `caller` or `friend`.
  static AnalyticsEvent followToggled({
    required String personId,
    required String source,
    required bool selected,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.onboardingFollowToggled,
    {
      AnalyticsProps.personId: personId,
      OnboardingProps.source: source,
      OnboardingProps.selected: selected,
    },
    [personId, selected],
    occurredAtMs,
  );

  static AnalyticsEvent followsApplied({
    required int requested,
    required int succeeded,
    required int failed,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.onboardingFollowsApplied,
    {
      OnboardingProps.requested: requested,
      OnboardingProps.succeeded: succeeded,
      OnboardingProps.failed: failed,
    },
    [requested, succeeded],
    occurredAtMs,
  );

  /// [kind]: `market`, `back` or `fade`.
  static AnalyticsEvent firstCallOpened({
    required String kind,
    required String marketId,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.onboardingFirstCallOpened,
    {OnboardingProps.kind: kind, AnalyticsProps.marketId: marketId},
    [kind, marketId],
    occurredAtMs,
  );

  /// Once per app session: the flow finished.
  static AnalyticsEvent completed({
    required String path,
    required bool madeCall,
    required int follows,
    required int stepsShown,
    required int stepsSkipped,
    required int durationMs,
    int? occurredAtMs,
  }) => AnalyticsEvent.internal(
    name: AnalyticsEventName.onboardingCompleted,
    props: {
      OnboardingProps.path: path,
      OnboardingProps.madeCall: madeCall,
      OnboardingProps.follows: follows,
      OnboardingProps.stepsShown: stepsShown,
      OnboardingProps.stepsSkipped: stepsSkipped,
      OnboardingProps.durationMs: durationMs,
    },
    dedupeParts: [path],
    dedupePolicy: AnalyticsDedupePolicy.oncePerSession,
    occurredAtMs: occurredAtMs ?? _now(),
  );

  /// [method]: `wallet`, `google` or `x`. [context]: `onboarding`,
  /// `welcome_back`, `upgrade`.
  static AnalyticsEvent signInStarted({
    required String method,
    required String context,
    required bool lastUsed,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.signInStarted,
    {
      OnboardingProps.method: method,
      OnboardingProps.context: context,
      OnboardingProps.lastUsed: lastUsed,
    },
    [method, context],
    occurredAtMs,
  );

  /// [account]: `new`, `existing` or `carried_over`.
  static AnalyticsEvent signInCompleted({
    required String method,
    required String account,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.signInCompleted,
    {OnboardingProps.method: method, OnboardingProps.account: account},
    [method, account],
    occurredAtMs,
  );

  /// [reason]: `cancelled`, `declined`, `no_wallet`, `timeout`, `network`,
  /// `refused`.
  static AnalyticsEvent signInFailed({
    required String method,
    required String reason,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.signInFailed,
    {OnboardingProps.method: method, OnboardingProps.reason: reason},
    [method, reason],
    occurredAtMs,
  );

  /// Never the handle itself. [path]: `new` or `carried_over`.
  /// [suggestionSource]: `x`, `domain`, `google` or `none`.
  static AnalyticsEvent usernameClaimed({
    required String path,
    required bool usedSuggestion,
    required String suggestionSource,
    required int attempts,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.usernameClaimed,
    {
      OnboardingProps.path: path,
      OnboardingProps.usedSuggestion: usedSuggestion,
      OnboardingProps.suggestionSource: suggestionSource,
      OnboardingProps.attempts: attempts,
    },
    [path],
    occurredAtMs,
  );

  static AnalyticsEvent notificationPromptShown({
    required String trigger,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.notificationPromptShown,
    {OnboardingProps.trigger: trigger},
    [trigger],
    occurredAtMs,
  );

  /// [result]: `granted`, `denied`, `not_now`, `permanently_denied`.
  /// [stage]: `pre_prompt` or `system`.
  static AnalyticsEvent notificationPermissionResult({
    required String result,
    required String stage,
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.notificationPermissionResult,
    {OnboardingProps.result: result, OnboardingProps.stage: stage},
    [result, stage],
    occurredAtMs,
  );

  /// [result]: `restored`, `failed`, `timeout`, `none`.
  static AnalyticsEvent sessionRestore({
    required String result,
    String source = 'block_store',
    int? occurredAtMs,
  }) => _repeatable(
    AnalyticsEventName.sessionRestore,
    {OnboardingProps.result: result, OnboardingProps.source: source},
    [result],
    occurredAtMs,
  );
}
