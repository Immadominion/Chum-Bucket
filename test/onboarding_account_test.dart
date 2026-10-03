// A1 sign-in, A2/A2c usernames, B1 Welcome back and U1 What's new
// (onboarding spec §6, §7), acceptance as tests.
import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/profile_hints.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/sign_in_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/upgrade_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/username_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';
import 'session_fakes.dart';

OnboardingFlowController _flow(WidgetTester tester) =>
    Provider.of<OnboardingFlowController>(
      tester.element(find.byType(Scaffold).last),
      listen: false,
    );

Future<OnboardingRig> _mount(
  WidgetTester tester,
  OnboardingRun run, {
  OnboardingRig? rig,
  bool sessionEnded = false,
  double width = 390,
  double height = 900,
  double scale = 1,
}) async {
  final r = rig ?? OnboardingRig(repo: OnboardingScene().repository());
  await tester.runAsync(r.start);
  addTearDown(r.dispose);
  await mountAt(
    tester,
    r.flow(run, sessionEnded: sessionEnded),
    around: r.wrap,
    width: width,
    height: height,
    scale: scale,
  );
  await settle(tester);
  return r;
}

PendingCall _draft() => PendingCall(
  kind: PendingCallKind.call,
  marketId: OnboardingScene().btc.id,
  side: Side.yes,
  question: OnboardingScene().btc.question,
  savedAt: kNowMs,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('A1 Sign in', () {
    Future<void> toSignIn(WidgetTester tester) async {
      _flow(tester).goTo(OnboardingStep.signIn);
      await settle(tester, const Duration(milliseconds: 600));
      expect(find.byType(SignInScreen), findsOneWidget);
    }

    for (final (label, call, follows, title) in [
      ('a call', true, 0, OnboardingCopy.signInTitleCall),
      ('follows', false, 3, OnboardingCopy.signInTitleFollow(3, null)),
      ('both: the call wins', true, 2, OnboardingCopy.signInTitleCall),
      ('nothing waiting', false, 0, OnboardingCopy.signInTitleDefault),
    ]) {
      testWidgets('the title says what it saves: $label', (tester) async {
        final rig = OnboardingRig(repo: OnboardingScene().repository());
        await tester.runAsync(() async {
          await rig.start();
          if (call) await rig.app.saveDraft(_draft());
          if (follows > 0) {
            await rig.app.setPendingFollows(
              ['user-ada', 'user-kemi', 'user-tunde'].take(follows),
            );
          }
        });
        await _mount(tester, OnboardingRun.newUser, rig: rig);
        await toSignIn(tester);
        expect(find.text(title), findsOneWidget);
        expect(
          find.text(OnboardingCopy.signInDraftNote),
          call ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('one person waiting: "Sign in to follow Ada Okafor"', (
      tester,
    ) async {
      final rig = await _mount(tester, OnboardingRun.newUser);
      final flow = _flow(tester);
      flow.goTo(OnboardingStep.people);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('follow-user-ada')));
      await settle(tester, const Duration(milliseconds: 300));
      await toSignIn(tester);
      expect(rig.app.pendingFollowIds, {'user-ada'});
      expect(
        find.text(OnboardingCopy.signInTitleFollow(1, 'Ada Okafor')),
        findsOneWidget,
      );
    });

    testWidgets('X appears only when Supabase has it switched on', (
      tester,
    ) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        providers: const {'google'},
      );
      await _mount(tester, OnboardingRun.newUser, rig: rig);
      await toSignIn(tester);
      expect(find.byKey(const ValueKey('front-door-google')), findsOneWidget);
      expect(find.byKey(const ValueKey('front-door-x')), findsNothing);
    });

    testWidgets('"Last used" is first, filled, and marked', (tester) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        providers: const {'google', 'x'},
        lastUsed: SignInMethod.x,
      );
      await _mount(tester, OnboardingRun.newUser, rig: rig);
      await toSignIn(tester);
      final x = tester.getRect(find.byKey(const ValueKey('front-door-x')));
      final google = tester.getRect(
        find.byKey(const ValueKey('front-door-google')),
      );
      expect(x.top, lessThan(google.top));
      expect(find.text(OnboardingCopy.signInLastUsed), findsOneWidget);
    });

    testWidgets(
      'consent links are 48dp targets to the real Terms and Privacy',
      (tester) async {
        await _mount(tester, OnboardingRun.newUser);
        await toSignIn(tester);
        for (final label in [
          OnboardingCopy.signInTerms,
          OnboardingCopy.signInPrivacy,
        ]) {
          final target = find.ancestor(
            of: find.text(label),
            matching: find.byType(InkWell),
          );
          expect(tester.getSize(target.first).height, greaterThanOrEqualTo(48));
        }
      },
    );

    testWidgets('"Not now": Home signed out; the draft and follows are kept', (
      tester,
    ) async {
      final rig = OnboardingRig(repo: OnboardingScene().repository());
      await tester.runAsync(() async {
        await rig.start();
        await rig.app.saveDraft(_draft());
      });
      await _mount(tester, OnboardingRun.newUser, rig: rig);
      await toSignIn(tester);
      await tester.tap(find.byKey(const ValueKey('sign-in-not-now')));
      await settle(tester);
      expect(rig.exits, [FlowExit.home]);
      expect(rig.app.status, OnboardingStatus.lookedAround);
      expect(rig.app.pendingCall, isNotNull);
      expect(
        rig.events(AnalyticsEventName.onboardingStepCompleted),
        contains(allOf(contains('sign_in'), contains('not_now'))),
      );
    });

    testWidgets(
      'at 320dp and 2x text everything is reachable, nothing overflows',
      (tester) async {
        final rig = OnboardingRig(repo: OnboardingScene().repository());
        await tester.runAsync(() async {
          await rig.start();
          await rig.app.saveDraft(_draft());
        });
        await _mount(
          tester,
          OnboardingRun.newUser,
          rig: rig,
          width: 320,
          height: 700,
          scale: 2,
        );
        await toSignIn(tester);
        expect(tester.takeException(), isNull);
        await tester.dragUntilVisible(
          find.text(OnboardingCopy.signInPrivacy),
          find.byType(SingleChildScrollView).first,
          const Offset(0, -200),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('A2 / A2c usernames', () {
    OnboardingRig newAccount({
      ProfileHints? hints,
      Set<String> taken = const {},
    }) {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        signedIn: true,
        bff: OnboardingBff(unlinked: true, taken: taken),
      );
      rig.auth.restored = SupabaseSessionSnapshot(
        accessToken: kAccessToken,
        authUserId: kAuthUserId,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        profileHints: hints,
      );
      return rig;
    }

    const xHints = ProfileHints(
      provider: 'twitter',
      userName: 'ada_calls',
      fullName: 'Ada Okafor',
    );

    testWidgets(
      'a suggestion is prefilled only when the server says available',
      (tester) async {
        final rig = await _mount(
          tester,
          OnboardingRun.claimOnly,
          rig: newAccount(hints: xHints),
        );
        await settle(tester, const Duration(milliseconds: 1200));
        expect(find.byType(UsernameScreen), findsOneWidget);
        expect(rig.bff.statusChecks, contains('ada_calls'));
        final field = tester.widget<TextField>(
          find.byKey(const ValueKey('username-field')),
        );
        expect(field.controller!.text, 'ada_calls');
        expect(
          find.textContaining(OnboardingCopy.usernameSuggestedX),
          findsOneWidget,
        );
        // The name came from X too; nothing is claimed without a tap.
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('username-name')))
              .controller!
              .text,
          'Ada Okafor',
        );
        expect(rig.bff.claims, isEmpty);
        expect(rig.bff.profiles, isEmpty);
      },
    );

    testWidgets('a taken suggestion is never prefilled', (tester) async {
      await _mount(
        tester,
        OnboardingRun.claimOnly,
        rig: newAccount(hints: xHints, taken: {'ada_calls'}),
      );
      await settle(tester, const Duration(milliseconds: 1200));
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('username-field')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('A2 says the username is permanent, and claims on a tap', (
      tester,
    ) async {
      final rig = await _mount(
        tester,
        OnboardingRun.claimOnly,
        rig: newAccount(hints: xHints),
      );
      await settle(tester, const Duration(milliseconds: 1200));
      expect(find.text(OnboardingCopy.usernameTitle), findsOneWidget);
      expect(find.text(OnboardingCopy.usernamePermanent), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('username-claim')));
      await settle(tester, const Duration(milliseconds: 1200));
      expect(rig.bff.profiles.single, {
        'displayName': 'Ada Okafor',
        'handle': 'ada_calls',
      });
      expect(
        rig.events(AnalyticsEventName.usernameClaimed).single,
        allOf(contains('usedSuggestion: true'), contains('x')),
      );
      // Never the handle itself in analytics.
      expect(
        rig.events(AnalyticsEventName.usernameClaimed).single,
        isNot(contains('ada_calls')),
      );
    });

    testWidgets('trust\'s content policy answers at once, before the server', (
      tester,
    ) async {
      final rig = await _mount(
        tester,
        OnboardingRun.claimOnly,
        rig: newAccount(),
      );
      await settle(tester, const Duration(milliseconds: 600));
      await tester.enterText(
        find.byKey(const ValueKey('username-field')),
        'ada_ok',
      );
      await tester.enterText(
        find.byKey(const ValueKey('username-name')),
        'Ada at pump.fun',
      );
      await settle(tester, const Duration(milliseconds: 900));
      await tester.tap(find.byKey(const ValueKey('username-claim')));
      await settle(tester);
      expect(find.byKey(const ValueKey('username-error')), findsOneWidget);
      expect(rig.bff.profiles, isEmpty);
    });

    testWidgets('A2c: a carried-over profile never sees a Name field', (
      tester,
    ) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        signedIn: true,
        bff: OnboardingBff(handle: null),
      );
      await _mount(tester, OnboardingRun.claimOnly, rig: rig);
      await settle(tester, const Duration(milliseconds: 600));
      expect(rig.session.needsHandleClaim, isTrue);
      expect(find.text(OnboardingCopy.usernameCTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('username-name')), findsNothing);
      // "Later" is offered, once per install.
      await tester.tap(find.byKey(const ValueKey('username-later')));
      await settle(tester);
      expect(rig.app.record.handleClaimDeferred, isTrue);
      expect(rig.exits, [FlowExit.pop]);
    });
  });

  group('B1 Welcome back', () {
    testWidgets(
      'one tap back in; never Welcome, Topics, People or First call',
      (tester) async {
        final rig = OnboardingRig(
          repo: OnboardingScene().repository(),
          lastUsed: SignInMethod.google,
          bff: OnboardingBff(handle: 'ada'),
        );
        await _mount(tester, OnboardingRun.welcomeBack, rig: rig);
        expect(find.text(OnboardingCopy.backTitle), findsOneWidget);
        expect(_flow(tester).steps, [OnboardingStep.welcomeBack]);
        rig.auth.deliverOnSignIn = snapshot();
        await tester.tap(find.byKey(const ValueKey('front-door-google')));
        await settle(tester, const Duration(milliseconds: 1500));
        expect(rig.session.isReady, isTrue);
        expect(rig.exits, [FlowExit.home]);
        expect(find.byType(WelcomeScreen), findsNothing);
      },
    );

    testWidgets('after a failed restore it says the session ended', (
      tester,
    ) async {
      await _mount(tester, OnboardingRun.welcomeBack, sessionEnded: true);
      expect(find.text(OnboardingCopy.backSessionEnded), findsOneWidget);
      expect(find.text(OnboardingCopy.backLook), findsOneWidget);
    });
  });

  group('U1 What\'s new', () {
    testWidgets('with carry-over off it says so, and offers no new account', (
      tester,
    ) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        bff: OnboardingBff(walletProfileCarry: false),
      );
      await _mount(tester, OnboardingRun.upgrade, rig: rig);
      expect(find.byType(UpgradeScreen), findsOneWidget);
      expect(find.text(OnboardingCopy.upgradeSafe), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('upgrade-continue')));
      await settle(tester, const Duration(milliseconds: 600));
      expect(find.text(OnboardingCopy.upgradeClosed), findsOneWidget);
      expect(find.byKey(const ValueKey('upgrade-continue')), findsNothing);
      expect(rig.bff.profiles, isEmpty);
      expect(rig.bff.claims, isEmpty);
    });

    testWidgets('"Not now" is once per install', (tester) async {
      final rig = await _mount(tester, OnboardingRun.upgrade);
      await tester.tap(find.byKey(const ValueKey('upgrade-not-now')));
      await settle(tester);
      expect(rig.app.record.upgradeIntroSeen, isTrue);
      expect(rig.exits, [FlowExit.home]);
      final stored = await tester.runAsync(
        () => const OnboardingStore().readRecord(),
      );
      expect(stored!.upgradeIntroSeen, isTrue);
    });
  });
}
