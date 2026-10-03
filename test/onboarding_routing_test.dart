// The entry table (onboarding spec §3) and the step machine (§4.3, §12):
// pure functions, so every branch is a unit test rather than a device run.
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 2, 12);

OnboardingEntry _decide({
  bool peopleFirst = true,
  bool deepLink = false,
  EntrySessionState session = EntrySessionState.none,
  bool needsHandleClaim = false,
  bool handleClaimDeferred = false,
  OnboardingStatus status = OnboardingStatus.fresh,
  DateTime? stageAt,
  bool restoring = false,
  bool restoreFailed = false,
  bool legacyWallet = false,
  bool upgradeSeen = false,
  bool signedInBefore = false,
}) => decideEntry(
  EntryInputs(
    peopleFirst: peopleFirst,
    deepLinkPending: deepLink,
    session: session,
    needsHandleClaim: needsHandleClaim,
    handleClaimDeferred: handleClaimDeferred,
    status: status,
    stageUpdatedAt: stageAt,
    restoreInProgress: restoring,
    restoreFailed: restoreFailed,
    legacyWalletSignedIn: legacyWallet,
    upgradeIntroSeen: upgradeSeen,
    signedInHereBefore: signedInBefore,
    now: _now,
  ),
);

void main() {
  group('decideEntry: every row of §3, first match wins', () {
    test('row 0: the legacy (challenge) build keeps its own door', () {
      expect(
        _decide(peopleFirst: false, session: EntrySessionState.ready),
        OnboardingEntry.legacy,
      );
    });

    test('row 1: a shared link opens over Home, never behind Welcome', () {
      expect(_decide(deepLink: true), OnboardingEntry.deepLink);
      // Whatever else is true: a ready account, a first run, a returning phone.
      for (final session in EntrySessionState.values) {
        expect(
          _decide(deepLink: true, session: session, signedInBefore: true),
          OnboardingEntry.deepLink,
          reason: '$session',
        );
      }
    });

    test(
      'row 2: ready with no @username goes Home, then Pick your @username',
      () {
        expect(
          _decide(session: EntrySessionState.ready, needsHandleClaim: true),
          OnboardingEntry.homeThenClaim,
        );
        // "Later" on this install: just Home.
        expect(
          _decide(
            session: EntrySessionState.ready,
            needsHandleClaim: true,
            handleClaimDeferred: true,
          ),
          OnboardingEntry.home,
        );
      },
    );

    test('row 3: a run cut short within 24 hours resumes at its stage', () {
      expect(
        _decide(
          session: EntrySessionState.ready,
          status: OnboardingStatus.inProgress,
          stageAt: _now.subtract(const Duration(hours: 23)),
        ),
        OnboardingEntry.resume,
      );
      // Older than a day, or a stage from the future (a clock change): Home.
      expect(
        _decide(
          session: EntrySessionState.ready,
          status: OnboardingStatus.inProgress,
          stageAt: _now.subtract(const Duration(hours: 25)),
        ),
        OnboardingEntry.home,
      );
      expect(
        _decide(
          session: EntrySessionState.ready,
          status: OnboardingStatus.inProgress,
          stageAt: _now.add(const Duration(minutes: 5)),
        ),
        OnboardingEntry.home,
      );
    });

    test(
      'row 4: an established account goes Home, whatever this phone did',
      () {
        for (final status in OnboardingStatus.values) {
          expect(
            _decide(session: EntrySessionState.ready, status: status),
            OnboardingEntry.home,
            reason: '$status',
          );
        }
      },
    );

    test('row 5: a session with no account yet claims its @username', () {
      expect(
        _decide(session: EntrySessionState.needsAccount),
        OnboardingEntry.claimUsername,
      );
    });

    test(
      'row 6: a stored session the server is slow on goes Home, reconnecting',
      () {
        expect(
          _decide(session: EntrySessionState.unconfirmed, signedInBefore: true),
          OnboardingEntry.homeReconnecting,
        );
        // Never new-user screens for someone with a stored session.
        expect(
          _decide(session: EntrySessionState.unconfirmed),
          isNot(OnboardingEntry.welcome),
        );
      },
    );

    test('row 7: a Block Store restore holds the splash (B2)', () {
      expect(_decide(restoring: true), OnboardingEntry.restoring);
      expect(
        _decide(restoring: true, legacyWallet: true, signedInBefore: true),
        OnboardingEntry.restoring,
      );
    });

    test('row 8: an old wallet profile sees What\'s new once', () {
      expect(_decide(legacyWallet: true), OnboardingEntry.upgrade);
      expect(
        _decide(legacyWallet: true, upgradeSeen: true),
        OnboardingEntry.home,
      );
      // Before Welcome back: the wallet profile is the warmer audience.
      expect(
        _decide(legacyWallet: true, signedInBefore: true),
        OnboardingEntry.upgrade,
      );
    });

    test('row 9: a phone that signed in before gets Welcome back', () {
      expect(_decide(signedInBefore: true), OnboardingEntry.welcomeBack);
      // Including after a deliberate sign-out from a completed run.
      expect(
        _decide(signedInBefore: true, status: OnboardingStatus.completed),
        OnboardingEntry.welcomeBack,
      );
      // A failed restore, or a stored session the server refused.
      expect(_decide(restoreFailed: true), OnboardingEntry.welcomeBack);
      expect(
        _decide(session: EntrySessionState.refused),
        OnboardingEntry.welcomeBack,
      );
    });

    test('row 10: someone who chose to look around goes Home signed out', () {
      for (final status in [
        OnboardingStatus.completed,
        OnboardingStatus.lookedAround,
        OnboardingStatus.deferred,
      ]) {
        expect(
          _decide(status: status),
          OnboardingEntry.homeSignedOut,
          reason: '$status',
        );
      }
    });

    test('row 11: otherwise, the first run starts at Welcome', () {
      expect(_decide(), OnboardingEntry.welcome);
      // A run interrupted signed out starts again at Welcome.
      expect(
        _decide(
          status: OnboardingStatus.inProgress,
          stageAt: _now.subtract(const Duration(minutes: 3)),
        ),
        OnboardingEntry.welcome,
      );
    });

    test('a returning or signed-in person never lands on Welcome', () {
      for (final session in EntrySessionState.values) {
        for (final before in [true, false]) {
          for (final legacy in [true, false]) {
            final entry = _decide(
              session: session,
              signedInBefore: before,
              legacyWallet: legacy,
            );
            if (session != EntrySessionState.none || before || legacy) {
              expect(
                entry,
                isNot(OnboardingEntry.welcome),
                reason: '$session before=$before legacy=$legacy',
              );
            }
          }
        }
      }
    });
  });

  group('OnboardingStatus wire values', () {
    test('round-trip, and anything unknown is a fresh install', () {
      for (final s in OnboardingStatus.values) {
        expect(OnboardingStatus.fromWire(s.wire), s);
      }
      expect(OnboardingStatus.fromWire('nonsense'), OnboardingStatus.fresh);
      expect(OnboardingStatus.fromWire(null), OnboardingStatus.fresh);
    });
  });

  group('computeSteps: steps follow what is real right now (§4.3)', () {
    const all = StepData.available;
    const none = StepData.unavailable;

    test('a first run with real data everywhere, signed out', () {
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.newUser,
            topics: all,
            people: all,
            firstCall: all,
          ),
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.topics,
          OnboardingStep.people,
          OnboardingStep.firstCall,
          OnboardingStep.signIn,
        ],
      );
    });

    test('thin data skips the step for you; loading keeps it', () {
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.newUser,
            topics: none,
            people: none,
            firstCall: none,
          ),
        ),
        [OnboardingStep.welcome, OnboardingStep.signIn],
      );
      expect(
        computeSteps(const StepInputs(run: OnboardingRun.newUser)),
        contains(OnboardingStep.people),
      );
    });

    test("2 Oct production: T shown, P skipped (one caller), C shown", () {
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.newUser,
            topics: all,
            people: none,
            firstCall: all,
          ),
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.topics,
          OnboardingStep.firstCall,
          OnboardingStep.signIn,
        ],
      );
    });

    test('signed in already: no Sign in step', () {
      final steps = computeSteps(
        const StepInputs(
          run: OnboardingRun.newUser,
          topics: all,
          people: all,
          firstCall: all,
          signedIn: true,
        ),
      );
      expect(steps, isNot(contains(OnboardingStep.signIn)));
    });

    test('after sign-in: username, friends, the waiting call, then R', () {
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.newUser,
            topics: none,
            people: none,
            firstCall: all,
            needsUsername: true,
            hasFriends: true,
            pendingCall: true,
          ),
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.firstCall,
          OnboardingStep.username,
          OnboardingStep.friends,
          OnboardingStep.resumeCall,
        ],
      );
      // Once locked, R ends the run — and C stays in it even if its data
      // later turned thin, so Back still has somewhere to go.
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.newUser,
            firstCall: none,
            signedIn: true,
            lockedCall: true,
          ),
        ),
        [
          OnboardingStep.welcome,
          OnboardingStep.topics,
          OnboardingStep.people,
          OnboardingStep.firstCall,
          OnboardingStep.onRecord,
        ],
      );
    });

    test('a carried-over profile picks a username unless it said Later', () {
      final base = const StepInputs(
        run: OnboardingRun.claimOnly,
        signedIn: true,
        needsHandleClaim: true,
      );
      expect(computeSteps(base), [OnboardingStep.username]);
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.newUser,
            signedIn: true,
            needsHandleClaim: true,
            handleClaimLater: true,
            topics: none,
            people: none,
            firstCall: none,
          ),
        ),
        [OnboardingStep.welcome],
      );
    });

    test('Welcome back never shows Topics, People or First call', () {
      for (final data in StepData.values) {
        final steps = computeSteps(
          StepInputs(
            run: OnboardingRun.welcomeBack,
            topics: data,
            people: data,
            firstCall: data,
            needsHandleClaim: true,
            signedIn: true,
          ),
        );
        expect(steps, [OnboardingStep.welcomeBack, OnboardingStep.username]);
      }
    });

    test('What\'s new: username, friends, then topics; never C', () {
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.upgrade,
            topics: all,
            firstCall: all,
            needsHandleClaim: true,
            signedIn: true,
            hasFriends: true,
          ),
        ),
        [
          OnboardingStep.upgrade,
          OnboardingStep.username,
          OnboardingStep.friends,
          OnboardingStep.topics,
        ],
      );
    });

    test('Make Home yours: T, P, and sign-in only for waiting follows', () {
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.homeSetup,
            topics: all,
            people: all,
          ),
        ),
        [OnboardingStep.topics, OnboardingStep.people],
      );
      expect(
        computeSteps(
          const StepInputs(
            run: OnboardingRun.homeSetup,
            topics: all,
            people: all,
            pendingFollows: true,
          ),
        ),
        [OnboardingStep.topics, OnboardingStep.people, OnboardingStep.signIn],
      );
    });
  });

  group('progress: one segment per step kind in this run', () {
    test('sign-in and username share Account; friends share People', () {
      final steps = [
        OnboardingStep.welcome,
        OnboardingStep.topics,
        OnboardingStep.people,
        OnboardingStep.firstCall,
        OnboardingStep.signIn,
        OnboardingStep.username,
        OnboardingStep.friends,
      ];
      expect(progressSegments(steps), [
        ProgressSegment.topics,
        ProgressSegment.people,
        ProgressSegment.firstCall,
        ProgressSegment.account,
      ]);
      expect(progressOf(OnboardingStep.topics, steps), (index: 1, total: 4));
      expect(progressOf(OnboardingStep.username, steps), (index: 4, total: 4));
      expect(progressOf(OnboardingStep.friends, steps), (index: 2, total: 4));
    });

    test('W1, B1, U1 and R carry no progress bar', () {
      final steps = computeSteps(
        const StepInputs(run: OnboardingRun.newUser, lockedCall: true),
      );
      for (final s in [
        OnboardingStep.welcome,
        OnboardingStep.welcomeBack,
        OnboardingStep.upgrade,
        OnboardingStep.onRecord,
        OnboardingStep.resumeCall,
      ]) {
        expect(progressOf(s, steps), isNull, reason: '$s');
      }
    });

    test('a skipped step leaves no gap in the count', () {
      final steps = computeSteps(
        const StepInputs(
          run: OnboardingRun.newUser,
          topics: StepData.available,
          people: StepData.unavailable,
          firstCall: StepData.available,
        ),
      );
      expect(progressOf(OnboardingStep.firstCall, steps), (index: 2, total: 3));
    });

    test('back arrows on T, P, C, A1 and A2 only', () {
      expect(
        [
          for (final s in OnboardingStep.values)
            if (s.hasBackArrow) s,
        ],
        [
          OnboardingStep.topics,
          OnboardingStep.people,
          OnboardingStep.firstCall,
          OnboardingStep.signIn,
          OnboardingStep.username,
        ],
      );
    });
  });

  group('nextStep', () {
    test('moves along the run, and ends after its last step', () {
      final steps = [
        OnboardingStep.welcome,
        OnboardingStep.topics,
        OnboardingStep.signIn,
      ];
      expect(nextStep(OnboardingStep.welcome, steps), OnboardingStep.topics);
      expect(nextStep(OnboardingStep.signIn, steps), isNull);
    });

    test('from a step that just dropped out, to the next one still in', () {
      // People turned out too thin while on screen.
      final steps = [
        OnboardingStep.welcome,
        OnboardingStep.topics,
        OnboardingStep.firstCall,
        OnboardingStep.signIn,
      ];
      expect(nextStep(OnboardingStep.people, steps), OnboardingStep.firstCall);
    });
  });
}
