/// Which steps a run shows, computed from what is true right now (onboarding
/// spec §4.3, §12). Pure: the flow recomputes it whenever data arrives or the
/// session changes, so "signed in from a Welcome card removes Sign in" and
/// "friends found after sign-in insert Friends" need no special cases.
library;

enum OnboardingStep {
  /// W1 "Call it before it happens."
  welcome('welcome'),

  /// B1 "Welcome back".
  welcomeBack('welcome_back'),

  /// U1 "Chumbucket is now about calls".
  upgrade('upgrade'),

  /// T "What are you into?"
  topics('topics'),

  /// P "Follow people who call it".
  people('people'),

  /// C "Make your first call".
  firstCall('first_call'),

  /// A1 "Sign in to …".
  signIn('sign_in'),

  /// A2 "Claim your @username" / A2c "Pick your @username".
  username('username'),

  /// P, friends variant: after sign-in, when the account has friends here.
  friends('friends'),

  /// C again, after sign-in, with the saved draft reopened for a fresh Lock.
  resumeCall('resume_call'),

  /// R "You're on record".
  onRecord('on_record');

  const OnboardingStep(this.wire);

  /// Analytics token.
  final String wire;

  /// One progress segment each: Topics, People, First call, Account. Account
  /// is sign-in and username together.
  ProgressSegment? get segment => switch (this) {
    OnboardingStep.topics => ProgressSegment.topics,
    OnboardingStep.people || OnboardingStep.friends => ProgressSegment.people,
    OnboardingStep.firstCall => ProgressSegment.firstCall,
    OnboardingStep.signIn || OnboardingStep.username => ProgressSegment.account,
    _ => null,
  };

  /// Steps with a back arrow (system Back goes to the previous step too).
  bool get hasBackArrow => switch (this) {
    OnboardingStep.topics ||
    OnboardingStep.people ||
    OnboardingStep.firstCall ||
    OnboardingStep.signIn ||
    OnboardingStep.username => true,
    _ => false,
  };
}

enum ProgressSegment { topics, people, firstCall, account }

/// Whether an optional step has the real data it needs (§4.3).
enum StepData {
  /// Still loading, inside its budget: the step stays in the run and shows
  /// skeletons if reached.
  loading,
  available,

  /// Too thin, failed, offline or out of time: the step is skipped for you.
  unavailable,
}

/// What kind of run this is.
enum OnboardingRun {
  /// First run: W1, then the optional steps, then the account.
  newUser,

  /// "I already have an account", a signed-out returning phone, or a failed
  /// restore: B1, then a username if the account has none. No T, P or C.
  welcomeBack,

  /// An existing wallet profile on its first launch of the calls app (U1).
  upgrade,

  /// Home's "Make Home yours" card: T then P, then sign-in only if follows
  /// are waiting on it.
  homeSetup,

  /// A session with no username yet (A2, or A2c over Home).
  claimOnly,
}

class StepInputs {
  const StepInputs({
    required this.run,
    this.topics = StepData.loading,
    this.people = StepData.loading,
    this.firstCall = StepData.loading,
    this.signedIn = false,
    this.needsUsername = false,
    this.needsHandleClaim = false,
    this.handleClaimLater = false,
    this.hasFriends = false,
    this.pendingCall = false,
    this.lockedCall = false,
    this.pendingFollows = false,
    this.startAtWelcome = true,
  });

  final OnboardingRun run;
  final StepData topics;
  final StepData people;
  final StepData firstCall;

  /// `session.isReady`.
  final bool signedIn;

  /// A session with no account yet (A2).
  final bool needsUsername;

  /// An account with no @username yet (A2c).
  final bool needsHandleClaim;

  /// "Later" was chosen on A2c during this run.
  final bool handleClaimLater;

  /// The signed-in account has friends from the old app.
  final bool hasFriends;

  /// A draft call is saved on this phone, waiting for a signed-in Lock.
  final bool pendingCall;

  /// A call was locked during this run.
  final bool lockedCall;

  /// Follows chosen while signed out, waiting for sign-in.
  final bool pendingFollows;

  /// W1 is the first step of a new-user run (false when the run began
  /// somewhere else, e.g. resumed past it).
  final bool startAtWelcome;
}

List<OnboardingStep> computeSteps(StepInputs i) {
  bool shown(StepData data) => data != StepData.unavailable;
  final username =
      i.needsUsername || (i.needsHandleClaim && !i.handleClaimLater);
  final steps = <OnboardingStep>[];
  switch (i.run) {
    case OnboardingRun.newUser:
      if (i.startAtWelcome) steps.add(OnboardingStep.welcome);
      if (shown(i.topics)) steps.add(OnboardingStep.topics);
      if (shown(i.people)) steps.add(OnboardingStep.people);
      if (shown(i.firstCall) || i.lockedCall) {
        steps.add(OnboardingStep.firstCall);
      }
      if (!i.signedIn && !i.needsUsername) steps.add(OnboardingStep.signIn);
      if (username) steps.add(OnboardingStep.username);
      if (i.hasFriends) steps.add(OnboardingStep.friends);
      if (i.pendingCall) steps.add(OnboardingStep.resumeCall);
      if (i.lockedCall) steps.add(OnboardingStep.onRecord);
    case OnboardingRun.welcomeBack:
      steps.add(OnboardingStep.welcomeBack);
      if (username) steps.add(OnboardingStep.username);
    case OnboardingRun.upgrade:
      steps.add(OnboardingStep.upgrade);
      if (username) steps.add(OnboardingStep.username);
      if (i.hasFriends) steps.add(OnboardingStep.friends);
      if (shown(i.topics)) steps.add(OnboardingStep.topics);
    case OnboardingRun.homeSetup:
      if (shown(i.topics)) steps.add(OnboardingStep.topics);
      if (shown(i.people)) steps.add(OnboardingStep.people);
      if (i.pendingFollows && !i.signedIn && !i.needsUsername) {
        steps.add(OnboardingStep.signIn);
      }
      if (i.needsUsername) steps.add(OnboardingStep.username);
    case OnboardingRun.claimOnly:
      steps.add(OnboardingStep.username);
      if (i.hasFriends) steps.add(OnboardingStep.friends);
  }
  return steps;
}

/// The progress segments of a run, in order, one per distinct segment.
List<ProgressSegment> progressSegments(List<OnboardingStep> steps) {
  final out = <ProgressSegment>[];
  for (final step in steps) {
    final segment = step.segment;
    if (segment != null && !out.contains(segment)) out.add(segment);
  }
  return out;
}

/// "Step i of n" for [step] in [steps], or null when the step has no
/// progress bar (W1, B1, U1, R and the reopened composer).
({int index, int total})? progressOf(
  OnboardingStep step,
  List<OnboardingStep> steps,
) {
  final segment = step.segment;
  if (segment == null) return null;
  final segments = progressSegments(steps);
  final at = segments.indexOf(segment);
  if (at < 0) return null;
  return (index: at + 1, total: segments.length);
}

/// The step after [current] in [steps], or null at the end of the run. When
/// [current] has dropped out of the run (its data turned out too thin), the
/// next step is the first one that came after it in [order].
OnboardingStep? nextStep(
  OnboardingStep current,
  List<OnboardingStep> steps, {
  List<OnboardingStep> order = OnboardingStep.values,
}) {
  final at = steps.indexOf(current);
  if (at >= 0) return at + 1 < steps.length ? steps[at + 1] : null;
  final rank = order.indexOf(current);
  for (final step in steps) {
    if (order.indexOf(step) > rank) return step;
  }
  return null;
}
