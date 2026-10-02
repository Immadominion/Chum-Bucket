/// Where a cold start goes (onboarding spec §3). A pure function of what the
/// splash knows, so every row is a unit test rather than a device run.
///
/// The first matching row wins. Rows, in order:
///
/// | # | Condition | Entry |
/// |---|---|---|
/// | 0 | the legacy (challenge) build | [OnboardingEntry.legacy] |
/// | 1 | a shared call/person/market link is pending | [OnboardingEntry.deepLink] |
/// | 2 | ready, no @username, A2c not deferred on this install | [OnboardingEntry.homeThenClaim] |
/// | 3 | ready, onboarding in progress with a stage < 24 h old | [OnboardingEntry.resume] |
/// | 4 | ready | [OnboardingEntry.home] |
/// | 5 | a session with no account yet (never claimed) | [OnboardingEntry.claimUsername] |
/// | 6 | a stored session the server has not confirmed (slow/offline) | [OnboardingEntry.homeReconnecting] |
/// | 7 | a Block Store restore is running | [OnboardingEntry.restoring] |
/// | 8 | a legacy wallet profile, no account session, U1 unseen | [OnboardingEntry.upgrade] |
/// | 8b| a legacy wallet profile that chose "Not now" on U1 | [OnboardingEntry.home] |
/// | 9 | this phone has signed in before (or a restore just failed) | [OnboardingEntry.welcomeBack] |
/// | 10| onboarding completed, looked around, or deferred by a link | [OnboardingEntry.homeSignedOut] |
/// | 11| otherwise | [OnboardingEntry.welcome] |
library;

/// What the account session looks like at the moment of deciding.
enum EntrySessionState {
  /// No Supabase session at all.
  none,

  /// A verified session and a canonical account.
  ready,

  /// A verified session, and the server said there is no account behind it
  /// yet: the person still claims a @username (A2).
  needsAccount,

  /// A stored session whose `auth.whoami` has not answered in time, or failed
  /// on the network. Never shown new-user screens.
  unconfirmed,

  /// A stored session the server refused (expired, revoked). Treated as
  /// signed out; the person signs in again.
  refused,
}

/// Onboarding's own progress, persisted per install (§12).
enum OnboardingStatus {
  fresh('new'),
  inProgress('in_progress'),
  completed('completed'),
  deferred('deferred'),
  lookedAround('lookedAround');

  const OnboardingStatus(this.wire);
  final String wire;

  static OnboardingStatus fromWire(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => OnboardingStatus.fresh,
  );
}

enum OnboardingEntry {
  /// The challenge build: the original wallet-only door and name gate.
  legacy,

  /// Open the shared link over Home; onboarding is deferred.
  deepLink,

  /// Home, then "Pick your @username" (A2c) full-screen on top.
  homeThenClaim,

  /// Back into the flow at its stored stage.
  resume,

  home,

  /// "Claim your @username" (A2) for a session with no account yet.
  claimUsername,

  /// Home, saying it is reconnecting.
  homeReconnecting,

  /// Hold on the splash while the backed-up session is adopted (B2).
  restoring,

  /// "Chumbucket is now about calls" (U1) for an existing wallet profile.
  upgrade,

  /// "Welcome back" (B1).
  welcomeBack,

  /// Home, signed out.
  homeSignedOut,

  /// "Call it before it happens." (W1), the first run.
  welcome,
}

/// How long an in-progress stage stays resumable (§3 row 3).
const Duration kResumeWindow = Duration(hours: 24);

class EntryInputs {
  const EntryInputs({
    this.peopleFirst = true,
    this.deepLinkPending = false,
    this.session = EntrySessionState.none,
    this.needsHandleClaim = false,
    this.handleClaimDeferred = false,
    this.status = OnboardingStatus.fresh,
    this.stageUpdatedAt,
    this.restoreInProgress = false,
    this.restoreFailed = false,
    this.legacyWalletSignedIn = false,
    this.upgradeIntroSeen = false,
    this.signedInHereBefore = false,
    required this.now,
  });

  /// The calls build (`CALL_RECEIPT_EXPERIENCE`). False is the legacy build.
  final bool peopleFirst;
  final bool deepLinkPending;
  final EntrySessionState session;

  /// Ready, and the server said the account has no @username.
  final bool needsHandleClaim;

  /// "Later" was chosen on A2c on this install.
  final bool handleClaimDeferred;
  final OnboardingStatus status;
  final DateTime? stageUpdatedAt;
  final bool restoreInProgress;

  /// A Block Store restore was attempted and did not come back signed in.
  final bool restoreFailed;

  /// The old app's wallet session (`MwaAuthProvider.isAuthenticated`).
  final bool legacyWalletSignedIn;
  final bool upgradeIntroSeen;

  /// `lastSignInMethod != null`: someone signed in on this phone before.
  final bool signedInHereBefore;
  final DateTime now;
}

OnboardingEntry decideEntry(EntryInputs i) {
  if (!i.peopleFirst) return OnboardingEntry.legacy;
  if (i.deepLinkPending) return OnboardingEntry.deepLink;
  if (i.session == EntrySessionState.ready) {
    if (i.needsHandleClaim && !i.handleClaimDeferred) {
      return OnboardingEntry.homeThenClaim;
    }
    final stageAt = i.stageUpdatedAt;
    if (i.status == OnboardingStatus.inProgress &&
        stageAt != null &&
        !stageAt.isAfter(i.now) &&
        i.now.difference(stageAt) < kResumeWindow) {
      return OnboardingEntry.resume;
    }
    return OnboardingEntry.home;
  }
  if (i.session == EntrySessionState.needsAccount) {
    return OnboardingEntry.claimUsername;
  }
  if (i.session == EntrySessionState.unconfirmed) {
    return OnboardingEntry.homeReconnecting;
  }
  if (i.restoreInProgress) return OnboardingEntry.restoring;
  if (i.legacyWalletSignedIn) {
    return i.upgradeIntroSeen ? OnboardingEntry.home : OnboardingEntry.upgrade;
  }
  if (i.signedInHereBefore ||
      i.restoreFailed ||
      i.session == EntrySessionState.refused) {
    return OnboardingEntry.welcomeBack;
  }
  if (i.status == OnboardingStatus.completed ||
      i.status == OnboardingStatus.lookedAround ||
      i.status == OnboardingStatus.deferred) {
    return OnboardingEntry.homeSignedOut;
  }
  return OnboardingEntry.welcome;
}
