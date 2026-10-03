// A1 sign-in, A2/A2c usernames, B1 Welcome back and U1 What's new
// (onboarding spec §6, §7), acceptance as tests. A1 and B1 as redesigned on
// device: brand art, the title and the pick, and the ways in at the bottom
// (the first as a full button, the others round under an "or"). An account
// is the way in: no "Not now" on A1, no "Look around first" on B1.
import 'dart:typed_data';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/front_door_options.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/sign_in_panel.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/profile_hints.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/first_call_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/sign_in_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/upgrade_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/username_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
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

    testWidgets(
      'brand art, the title and the pick; the ways in and the consent line '
      'sit at the bottom',
      (tester) async {
        final rig = OnboardingRig(repo: OnboardingScene().repository());
        await tester.runAsync(() async {
          await rig.start();
          await rig.app.saveDraft(_draft());
        });
        await _mount(tester, OnboardingRun.newUser, rig: rig);
        await toSignIn(tester);
        final page = find.byType(SingleChildScrollView);
        final art = tester.widget<ChumbucketStateArt>(
          find.descendant(of: page, matching: find.byType(ChumbucketStateArt)),
        );
        expect(art.artwork, ChumbucketStateArtwork.record);
        expect(
          find.descendant(
            of: page,
            matching: find.text(OnboardingCopy.signInTitleCall),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: page, matching: find.byType(DraftCallCard)),
          findsOneWidget,
        );
        // The compact panel and the consent line are the sticky actions.
        final panel = find.byType(OnboardingSignInPanel);
        expect(tester.widget<OnboardingSignInPanel>(panel).compact, isTrue);
        expect(find.descendant(of: page, matching: panel), findsNothing);
        expect(
          find.descendant(of: page, matching: find.byType(OnbConsentLine)),
          findsNothing,
        );
        expect(
          tester.getRect(panel).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(OnbConsentLine)).top),
        );
        expect(
          tester.getRect(find.byType(OnbConsentLine)).bottom,
          lessThanOrEqualTo(900),
        );
        expect(find.byType(FrontDoorCircleButton), findsWidgets);
        expect(find.text(OnboardingCopy.signInWalletLine), findsNothing);
        expect(find.text(OnboardingCopy.signInSubtitle), findsNothing);
      },
    );

    testWidgets(
      'no "Not now": an account is the way in, and the pick stays on the '
      'phone',
      (tester) async {
        final rig = OnboardingRig(repo: OnboardingScene().repository());
        await tester.runAsync(() async {
          await rig.start();
          await rig.app.saveDraft(_draft());
        });
        await _mount(tester, OnboardingRun.newUser, rig: rig);
        await toSignIn(tester);
        expect(find.byKey(const ValueKey('sign-in-not-now')), findsNothing);
        expect(find.text(OnboardingCopy.signInNotNow), findsNothing);
        expect(find.text(OnboardingCopy.backLook), findsNothing);
        await settle(tester, const Duration(seconds: 2));
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(rig.exits, isEmpty, reason: 'no way out to Home signed out');
        expect(rig.app.status, isNot(OnboardingStatus.lookedAround));
        expect(rig.app.pendingCall, isNotNull);
        expect(
          rig.events(AnalyticsEventName.onboardingStepCompleted),
          isNot(contains(contains('not_now'))),
        );
      },
    );

    testWidgets(
      '"I\'ll do this later" on First call still leads to A1, which has no '
      'way around it',
      (tester) async {
        final rig = await _mount(tester, OnboardingRun.newUser);
        _flow(tester).goTo(OnboardingStep.firstCall);
        await settle(tester, const Duration(milliseconds: 1500));
        expect(find.byType(FirstCallScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('first-call-later')));
        await settle(tester);
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.text(OnboardingCopy.signInTitleDefault), findsOneWidget);
        expect(find.byKey(const ValueKey('sign-in-not-now')), findsNothing);
        expect(rig.exits, isEmpty);
      },
    );

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
      // Signing back in is the way in: nothing to look around first.
      expect(find.text(OnboardingCopy.backLook), findsNothing);
      expect(find.byKey(const ValueKey('sign-in-not-now')), findsNothing);
    });

    testWidgets('success art, the compact ways in, no "Look around first"', (
      tester,
    ) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        providers: const {'google', 'x'},
        lastUsed: SignInMethod.google,
      );
      await _mount(tester, OnboardingRun.welcomeBack, rig: rig);
      expect(find.text(OnboardingCopy.backTitle), findsOneWidget);
      expect(
        tester
            .widget<ChumbucketStateArt>(find.byType(ChumbucketStateArt))
            .artwork,
        ChumbucketStateArtwork.success,
      );
      expect(
        tester
            .widget<OnboardingSignInPanel>(find.byType(OnboardingSignInPanel))
            .compact,
        isTrue,
      );
      final primary = tester.widget<FrontDoorButton>(
        find.byType(FrontDoorButton),
      );
      expect(primary.method, SignInMethod.google);
      expect(find.byType(FrontDoorCircleButton), findsNWidgets(2));
      expect(find.text(OnboardingCopy.backLook), findsNothing);
      expect(find.byKey(const ValueKey('sign-in-not-now')), findsNothing);
      await settle(tester, const Duration(seconds: 2));
      expect(rig.exits, isEmpty);
    });
  });

  group('the compact sign-in panel (A1, B1)', () {
    Future<OnboardingRig> mountPanel(
      WidgetTester tester, {
      SignInMethod? lastUsed,
      bool walletApp = true,
      bool compact = true,
      List<(SignInMethod, bool)>? started,
    }) async {
      final rig = OnboardingRig(
        repo: OnboardingScene().repository(),
        providers: const {'google', 'x'},
        lastUsed: lastUsed,
      );
      await tester.runAsync(rig.start);
      addTearDown(rig.dispose);
      await mountAt(
        tester,
        Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OnboardingSignInPanel(
                compact: compact,
                walletAvailable: () async => walletApp,
                isOnline: () async => true,
                onStarted: (m, last) => started?.add((m, last)),
              ),
            ),
          ),
        ),
        around: rig.wrap,
      );
      await settle(tester);
      return rig;
    }

    FrontDoorButton primary(WidgetTester tester) =>
        tester.widget<FrontDoorButton>(find.byType(FrontDoorButton));

    List<SignInMethod> circles(WidgetTester tester) {
      final found =
          find.byType(FrontDoorCircleButton).evaluate().toList()..sort(
            (a, b) => tester
                .getCenter(find.byWidget(a.widget))
                .dx
                .compareTo(tester.getCenter(find.byWidget(b.widget)).dx),
          );
      return [
        for (final e in found) (e.widget as FrontDoorCircleButton).method,
      ];
    }

    testWidgets(
      'the first way in is the full button; the others are round buttons '
      'under an "or"; no wallet line',
      (tester) async {
        final handle = tester.ensureSemantics();
        await mountPanel(tester);
        expect(primary(tester).method, SignInMethod.wallet);
        expect(primary(tester).primary, isTrue);
        expect(circles(tester), [SignInMethod.google, SignInMethod.x]);
        final full = tester.getRect(
          find.byKey(const ValueKey('front-door-wallet')),
        );
        final or = tester.getRect(find.text('or'));
        final google = tester.getRect(
          find.byKey(const ValueKey('front-door-google')),
        );
        expect(full.bottom, lessThanOrEqualTo(or.top));
        expect(or.bottom, lessThanOrEqualTo(google.top));
        // Round, 48dp or more, and named for a screen reader.
        expect(google.width, google.height);
        expect(google.height, greaterThanOrEqualTo(48));
        expect(find.bySemanticsLabel('Continue with Google'), findsOneWidget);
        expect(find.bySemanticsLabel('Continue with X'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('front-door-last-used')),
          findsNothing,
        );
        expect(find.text(OnboardingCopy.signInWalletLine), findsNothing);
        handle.dispose();
      },
    );

    testWidgets('a round button starts its own sign-in', (tester) async {
      final started = <(SignInMethod, bool)>[];
      final rig = await mountPanel(tester, started: started);
      rig.auth.deliverOnSignIn = snapshot();
      await tester.tap(find.byKey(const ValueKey('front-door-x')));
      await settle(tester, const Duration(milliseconds: 1500));
      expect(started, [(SignInMethod.x, false)]);
      expect(rig.session.isReady, isTrue);
    });

    testWidgets('the method last used here leads, filled and marked', (
      tester,
    ) async {
      await mountPanel(tester, lastUsed: SignInMethod.x);
      expect(primary(tester).method, SignInMethod.x);
      expect(primary(tester).lastUsed, isTrue);
      expect(find.text(OnboardingCopy.signInLastUsed), findsOneWidget);
      expect(circles(tester), [SignInMethod.wallet, SignInMethod.google]);
      expect(
        find.descendant(
          of: find.byType(FrontDoorCircleButton),
          matching: find.byKey(const ValueKey('front-door-last-used')),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'last used was the wallet but no wallet app is here now: Google leads '
      'and the round wallet button carries the last-used dot',
      (tester) async {
        final handle = tester.ensureSemantics();
        await mountPanel(
          tester,
          lastUsed: SignInMethod.wallet,
          walletApp: false,
        );
        expect(primary(tester).method, SignInMethod.google);
        expect(circles(tester), [SignInMethod.x, SignInMethod.wallet]);
        final wallet = find.byWidgetPredicate(
          (w) => w is FrontDoorCircleButton && w.method == SignInMethod.wallet,
        );
        expect(
          find.descendant(
            of: wallet,
            matching: find.byKey(const ValueKey('front-door-last-used')),
          ),
          findsOneWidget,
        );
        expect(tester.getSemantics(wallet).hint, 'Last used on this phone');
        handle.dispose();
      },
    );

    testWidgets('elsewhere the full panel keeps full buttons and the wallet '
        'line', (tester) async {
      await mountPanel(tester, compact: false);
      expect(find.byType(FrontDoorButton), findsNWidgets(3));
      expect(find.byType(FrontDoorCircleButton), findsNothing);
      expect(find.text('or'), findsNothing);
      expect(find.text(OnboardingCopy.signInWalletLine), findsOneWidget);
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

  group('the wallet door: connected, but the message was not signed', () {
    Future<WalletDoorFailure?> knock(
      WidgetTester tester,
      _ConnectsWithoutSigning wallet,
    ) async {
      final rig = OnboardingRig(repo: OnboardingScene().repository());
      await tester.runAsync(rig.start);
      addTearDown(rig.dispose);
      late BuildContext ctx;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MwaAuthProvider>.value(value: wallet),
            ChangeNotifierProvider<ChumbucketSession>.value(value: rig.session),
          ],
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      var signed = false;
      final failure = await mwaWalletDoor(ctx, onSigned: () => signed = true);
      expect(signed, isFalse);
      return failure;
    }

    testWidgets('a new person: nothing is kept (no U1 on the next launch)', (
      tester,
    ) async {
      final wallet = _ConnectsWithoutSigning(heldBefore: false);
      expect(await knock(tester, wallet), WalletDoorFailure.declined);
      expect(wallet.forgotten, 1);
      expect(wallet.isAuthenticated, isFalse);
    });

    testWidgets('an old app\'s wallet session (U1) is left as it was', (
      tester,
    ) async {
      final wallet = _ConnectsWithoutSigning(heldBefore: true);
      expect(await knock(tester, wallet), WalletDoorFailure.declined);
      expect(wallet.forgotten, 0);
      expect(wallet.isAuthenticated, isTrue);
    });
  });
}

/// A wallet app that approves the connection and then declines to sign the
/// Chumbucket sign-in message.
class _ConnectsWithoutSigning extends MwaAuthProvider {
  _ConnectsWithoutSigning({required bool heldBefore}) : _held = heldBefore;

  bool _held;
  int forgotten = 0;

  @override
  bool get isAuthenticated => _held;

  @override
  Future<bool> isWalletAvailable() async => true;

  @override
  Future<bool> authorize({
    String Function(String address)? signInMessageFor,
  }) async {
    _held = true;
    return true;
  }

  @override
  ({String message, Uint8List signature})? takeSignedSignIn() => null;

  @override
  Future<void> forgetSession() async {
    forgotten++;
    _held = false;
  }
}
