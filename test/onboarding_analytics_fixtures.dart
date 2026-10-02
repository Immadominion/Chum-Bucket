/// One sample of every onboarding analytics event (onboarding spec §13.4),
/// shared by the analytics vocabulary, emission and retry tests.
library;

import 'package:chumbucket/core/analytics/analytics.dart';

/// The onboarding funnel's names, exactly as the spec writes them.
const Set<String> kOnboardingEventWires = {
  'onboarding_started',
  'onboarding_step_viewed',
  'onboarding_step_completed',
  'onboarding_welcome_live',
  'onboarding_topic_toggled',
  'onboarding_follow_toggled',
  'onboarding_follows_applied',
  'onboarding_first_call_opened',
  'onboarding_completed',
  'sign_in_started',
  'sign_in_completed',
  'sign_in_failed',
  'username_claimed',
  'notification_prompt_shown',
  'notification_permission_result',
  'session_restore',
};

Map<AnalyticsEventName, AnalyticsEvent> onboardingAnalyticsSamples({
  int? at,
}) => {
  AnalyticsEventName.onboardingStarted: OnboardingAnalyticsEvents.started(
    entry: 'welcome',
    occurredAtMs: at,
  ),
  AnalyticsEventName.onboardingStepViewed: OnboardingAnalyticsEvents.stepViewed(
    step: 'topics',
    index: 1,
    total: 4,
    available: true,
    occurredAtMs: at,
  ),
  AnalyticsEventName
      .onboardingStepCompleted: OnboardingAnalyticsEvents.stepCompleted(
    step: 'topics',
    outcome: 'continued',
    selectedCount: 2,
    occurredAtMs: at,
  ),
  AnalyticsEventName
      .onboardingWelcomeLive: OnboardingAnalyticsEvents.welcomeLive(
    source: 'top',
    count: 3,
    occurredAtMs: at,
  ),
  AnalyticsEventName
      .onboardingTopicToggled: OnboardingAnalyticsEvents.topicToggled(
    category: 'pop-culture',
    selected: true,
    occurredAtMs: at,
  ),
  AnalyticsEventName
      .onboardingFollowToggled: OnboardingAnalyticsEvents.followToggled(
    personId: 'user_ada',
    source: 'caller',
    selected: true,
    occurredAtMs: at,
  ),
  AnalyticsEventName
      .onboardingFollowsApplied: OnboardingAnalyticsEvents.followsApplied(
    requested: 2,
    succeeded: 2,
    failed: 0,
    occurredAtMs: at,
  ),
  AnalyticsEventName
      .onboardingFirstCallOpened: OnboardingAnalyticsEvents.firstCallOpened(
    kind: 'market',
    marketId: 'market_btc_150k',
    occurredAtMs: at,
  ),
  AnalyticsEventName.onboardingCompleted: OnboardingAnalyticsEvents.completed(
    path: 'newUser',
    madeCall: true,
    follows: 2,
    stepsShown: 6,
    stepsSkipped: 1,
    durationMs: 64000,
    occurredAtMs: at,
  ),
  AnalyticsEventName.signInStarted: OnboardingAnalyticsEvents.signInStarted(
    method: 'google',
    context: 'onboarding',
    lastUsed: false,
    occurredAtMs: at,
  ),
  AnalyticsEventName.signInCompleted: OnboardingAnalyticsEvents.signInCompleted(
    method: 'google',
    account: 'new',
    occurredAtMs: at,
  ),
  AnalyticsEventName.signInFailed: OnboardingAnalyticsEvents.signInFailed(
    method: 'wallet',
    reason: 'declined',
    occurredAtMs: at,
  ),
  AnalyticsEventName.usernameClaimed: OnboardingAnalyticsEvents.usernameClaimed(
    path: 'new',
    usedSuggestion: true,
    suggestionSource: 'x',
    attempts: 1,
    occurredAtMs: at,
  ),
  AnalyticsEventName.notificationPromptShown:
      OnboardingAnalyticsEvents.notificationPromptShown(
        trigger: 'first_call',
        occurredAtMs: at,
      ),
  AnalyticsEventName.notificationPermissionResult:
      OnboardingAnalyticsEvents.notificationPermissionResult(
        result: 'granted',
        stage: 'system',
        occurredAtMs: at,
      ),
  AnalyticsEventName.sessionRestore: OnboardingAnalyticsEvents.sessionRestore(
    result: 'restored',
    occurredAtMs: at,
  ),
};
