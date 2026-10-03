// S0: the splash routes through the entry table to one destination, with no
// OS permission dialog on the way (onboarding spec §3, §6 S0, §8). Plus
// what onboarding leaves on Home and in Settings (§7 K1, §8.6).
import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/services/push_registration.dart';
import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_home.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_settings.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/sign_in_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/topics_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:chumbucket/shared/screens/splash/mwa_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'identity_fakes.dart';
import 'onboarding_scenes.dart';
import 'session_fakes.dart';

const _home = Key('home-under-test');

Future<OnboardingRig> _splash(
  WidgetTester tester, {
  OnboardingRig? rig,
  bool deepLink = false,
  SessionContinuity? continuity,
}) async {
  final r = rig ?? OnboardingRig(repo: OnboardingScene().repository());
  await tester.runAsync(r.start);
  addTearDown(r.dispose);
  await mountAt(
    tester,
    MwaSplashScreen(
      peopleFirst: true,
      deepLinkPending: () async => deepLink,
      minimumDuration: const Duration(milliseconds: 700),
      homeBuilder:
          (_) => const OnboardingHomeEffects(
            child: Scaffold(key: _home, body: SizedBox()),
          ),
      clock: () => r.clockNow,
    ),
    around:
        (app) =>
            continuity == null
                ? r.wrap(app)
                : Provider<SessionContinuity>.value(
                  value: continuity,
                  child: r.wrap(app),
                ),
  );
  // Work started on the rig's own (real) zone — a session adopting a
  // restored token — needs real turns of the event loop between frames.
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await settle(tester, const Duration(milliseconds: 500));
  return r;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('S0 routes once, to the table\'s destination', () {
    testWidgets('a first run lands on Welcome, with no OS dialog on the way', (
      tester,
    ) async {
      final rig = await _splash(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(rig.permission.requests, 0);
    });

    testWidgets('a shared link opens over Home; Welcome waits (deferred)', (
      tester,
    ) async {
      final rig = await _splash(tester, deepLink: true);
      expect(find.byKey(_home), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(rig.app.status, OnboardingStatus.deferred);
    });

    testWidgets('a ready account goes straight Home', (tester) async {
      final rig = await _splash(
        tester,
        rig: OnboardingRig(
          repo: OnboardingScene().repository(),
          signedIn: true,
          bff: OnboardingBff(handle: 'ada'),
        ),
      );
      expect(rig.session.isReady, isTrue);
      expect(find.byKey(_home), findsOneWidget);
      expect(rig.permission.requests, 0);
    });

    testWidgets('a phone that signed in before gets Welcome back', (
      tester,
    ) async {
      await _splash(
        tester,
        rig: OnboardingRig(
          repo: OnboardingScene().repository(),
          lastUsed: SignInMethod.wallet,
        ),
      );
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(find.text(OnboardingCopy.backTitle), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
    });

    testWidgets('someone who looked around goes Home signed out', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        OnboardingStore.recordKey: '{"v":2,"status":"lookedAround"}',
      });
      await _splash(tester);
      expect(find.byKey(_home), findsOneWidget);
    });

    testWidgets('a session with no account yet claims its @username', (
      tester,
    ) async {
      final rig = await _splash(
        tester,
        rig: OnboardingRig(
          repo: OnboardingScene().repository(),
          signedIn: true,
          bff: OnboardingBff(unlinked: true),
        ),
      );
      expect(rig.session.needsUsername, isTrue);
      expect(find.text(OnboardingCopy.usernameTitle), findsOneWidget);
    });

    test('entrySessionStateOf reads the session as the table needs it', () {
      expect(entrySessionStateOf(null), EntrySessionState.none);
    });
  });

  group('B2 restoring after a reinstall', () {
    SessionContinuity continuityFor(
      OnboardingRig rig, {
      required SessionAdoption outcome,
    }) {
      final store = MemoryBlockStore();
      store.entries[SessionContinuity.sessionKey] =
          const SessionBackup(
            refreshToken: 'rt-test-only',
            authUserId: kAuthUserId,
            method: SignInMethod.google,
          ).encode();
      return SessionContinuity(
        store: store,
        localSession: () async => null,
        lastSignIn: rig.lastSignIn,
        adopt: (_) async {
          if (outcome == SessionAdoption.adopted) {
            rig.auth.restored = snapshot();
            rig.auth.emit(SupabaseAuthEventKind.tokenRefreshed, snapshot());
          }
          return outcome;
        },
      );
    }

    testWidgets('restored: Home, "Welcome back, @ada.", never Welcome', (
      tester,
    ) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        bff: OnboardingBff(handle: 'ada'),
      );
      await _splash(
        tester,
        rig: rig,
        continuity: continuityFor(rig, outcome: SessionAdoption.adopted),
      );
      expect(rig.session.isReady, isTrue);
      expect(find.byKey(_home), findsOneWidget);
      expect(find.text(OnboardingCopy.restoreOk('@ada')), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(
        rig.events(AnalyticsEventName.sessionRestore),
        isEmpty,
        reason: 'recorded through the app recorder, not this rig',
      );
    });

    testWidgets(
      'refused: Welcome back, saying the session ended, Last used kept',
      (tester) async {
        final rig = OnboardingRig(repo: OnboardingScene().repository());
        await _splash(
          tester,
          rig: rig,
          continuity: continuityFor(rig, outcome: SessionAdoption.rejected),
        );
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.text(OnboardingCopy.backSessionEnded), findsOneWidget);
        expect(await rig.lastSignIn.read(), SignInMethod.google);
        expect(find.byType(WelcomeScreen), findsNothing);
      },
    );
  });

  group('resume after process death (§3 row 3)', () {
    testWidgets('a signed-in run cut short resumes at its step', (
      tester,
    ) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        signedIn: true,
        bff: OnboardingBff(handle: 'ada'),
      );
      SharedPreferences.setMockInitialValues({
        OnboardingStore.recordKey:
            '{"v":2,"status":"in_progress","stage":"topics",'
            '"stageAt":${kNowMs - 60000}}',
      });
      await _splash(tester, rig: rig);
      expect(find.byType(TopicsScreen), findsOneWidget);
    });
  });

  group('K1 Make Home yours', () {
    Future<OnboardingRig> mountCard(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        OnboardingStore.recordKey: '{"v":2,"status":"lookedAround"}',
      });
      final rig = OnboardingRig(repo: OnboardingScene().repository());
      await tester.runAsync(rig.start);
      addTearDown(rig.dispose);
      await mountAt(
        tester,
        const Scaffold(body: Column(children: [HomeSetupCard()])),
        around: rig.wrap,
      );
      await settle(tester);
      return rig;
    }

    testWidgets('shown after looking around; "Not now" hides it', (
      tester,
    ) async {
      final rig = await mountCard(tester);
      expect(find.byKey(const ValueKey('home-setup-card')), findsOneWidget);
      expect(rig.app.record.homeCardShows, 1);
      await tester.tap(find.byKey(const ValueKey('home-setup-later')));
      await settle(tester);
      expect(find.byKey(const ValueKey('home-setup-card')), findsNothing);
      expect(rig.app.record.homeCardDeclines, 1);
    });

    testWidgets('"Set up" opens Topics then People over Home', (tester) async {
      await mountCard(tester);
      await tester.tap(find.byKey(const ValueKey('home-setup-cta')));
      await settle(tester);
      expect(find.byType(TopicsScreen), findsOneWidget);
      // No Welcome, no First call in this run.
      expect(find.byType(WelcomeScreen), findsNothing);
    });
  });

  group('Settings → Notifications (§8.6)', () {
    Future<OnboardingRig> mountRow(
      WidgetTester tester, {
      required bool pushLive,
      bool granted = false,
      bool blocked = false,
    }) async {
      if (blocked) {
        SharedPreferences.setMockInitialValues({
          PushRegistration.recordKey:
              '{"asks":2,"denials":2,"lastResult":"permanently_denied"}',
        });
      }
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        signedIn: true,
        bff: OnboardingBff(handle: 'ada'),
        pushLive: pushLive,
        permission: FakePushPlatform(granted: granted, answer: true),
      );
      await tester.runAsync(rig.start);
      addTearDown(rig.dispose);
      await mountAt(
        tester,
        const Scaffold(body: Column(children: [NotificationsSettingsItem()])),
        around: rig.wrap,
      );
      await settle(tester);
      return rig;
    }

    testWidgets('a server that sends no pushes: no row, nothing asked', (
      tester,
    ) async {
      final rig = await mountRow(tester, pushLive: false);
      expect(
        find.byKey(const ValueKey('settings-notifications')),
        findsNothing,
      );
      expect(rig.permission.requests, 0);
    });

    testWidgets('off: a tap asks the OS once and reads it again', (
      tester,
    ) async {
      final rig = await mountRow(tester, pushLive: true);
      expect(
        find.text(OnboardingCopy.settingsNotificationsTapToTurnOn),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('settings-notifications')));
      await settle(tester);
      expect(rig.permission.requests, 1);
      expect(find.text(OnboardingCopy.settingsNotificationsOn), findsOneWidget);
    });

    testWidgets(
      'refused for good: a tap opens Android Settings, never a dialog',
      (tester) async {
        var opened = 0;
        PushRegistration.openSystemSettings = () async {
          opened++;
          return true;
        };
        addTearDown(
          () => PushRegistration.openSystemSettings = () async => false,
        );
        final rig = await mountRow(tester, pushLive: true, blocked: true);
        expect(
          find.text(OnboardingCopy.settingsNotificationsOff),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('settings-notifications')));
        await settle(tester);
        expect(opened, 1);
        expect(rig.permission.requests, 0);
      },
    );
  });

  testWidgets('Settings → Topics shows how many are picked', (tester) async {
    SharedPreferences.setMockInitialValues({
      OnboardingStore.topicsKey: ['sports', 'crypto'],
    });
    final rig = OnboardingRig(repo: OnboardingScene().repository());
    await tester.runAsync(rig.start);
    addTearDown(rig.dispose);
    await mountAt(
      tester,
      const Scaffold(body: Column(children: [TopicsSettingsItem()])),
      around: rig.wrap,
    );
    await settle(tester);
    expect(find.text(OnboardingCopy.settingsTopicsValue(2)), findsOneWidget);
    expect(OnboardingRun.values, contains(OnboardingRun.homeSetup));
  });
}
