// Opt-in captures of every onboarding step with the real fonts and the
// synthetic scene, for design review at phone size. Writes nothing unless
// asked:
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_ONBOARDING=/abs/output/dir \
//   test/onboarding_visual_capture_test.dart
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_home.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/shared/screens/splash/mwa_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outDir = String.fromEnvironment('CAPTURE_ONBOARDING');

  setUpAll(() async {
    if (outDir.isEmpty) return;
    await loadBrandFonts();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await settle(tester, const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(Uri.file('$outDir/onboarding-$name.png')),
    );
  }

  OnboardingFlowController flowOf(WidgetTester tester) =>
      Provider.of<OnboardingFlowController>(
        tester.element(find.byType(Scaffold).last),
        listen: false,
      );

  Future<OnboardingRig> rigFor(
    WidgetTester tester, {
    bool signedIn = false,
    OnboardingBff? bff,
    SignInMethod? lastUsed,
    bool pushLive = false,
  }) async {
    final scene = OnboardingScene();
    final rig = OnboardingRig(
      repo: scene.repository(),
      signedIn: signedIn,
      bff: bff,
      lastUsed: lastUsed,
      providers: const {'google', 'x'},
      pushLive: pushLive,
    );
    await tester.runAsync(rig.start);
    addTearDown(rig.dispose);
    return rig;
  }

  final sizes = <String, (double, double, double)>{
    '390': (390, 844, 1),
    '320-2x': (320, 1800, 2),
  };

  testWidgets('splash', (tester) async {
    await mountAt(
      tester,
      MwaSplashScreen(
        peopleFirst: false,
        minimumDuration: const Duration(seconds: 30),
        deepLinkPending: () async => false,
      ),
    );
    await shot(tester, 's0-splash-390');
  }, skip: outDir.isEmpty);

  for (final MapEntry(key: size, value: (w, h, scale)) in sizes.entries) {
    testWidgets('welcome $size', (tester) async {
      final rig = await rigFor(tester);
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.newUser)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await shot(tester, 'w1-welcome-$size');
    }, skip: outDir.isEmpty);

    testWidgets('topics $size', (tester) async {
      final rig = await rigFor(tester);
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.newUser)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      flowOf(tester).advance(outcome: 'get_started');
      await settle(tester);
      flowOf(tester).toggleTopic('crypto');
      await settle(tester, const Duration(milliseconds: 300));
      await shot(tester, 't-topics-$size');
    }, skip: outDir.isEmpty);

    testWidgets('people $size', (tester) async {
      final rig = await rigFor(tester);
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.newUser)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      final flow = flowOf(tester);
      flow.goTo(OnboardingStep.people);
      await settle(tester);
      flow.togglePerson('user-ada', friend: false);
      await settle(tester, const Duration(milliseconds: 300));
      await shot(tester, 'p-people-$size');
    }, skip: outDir.isEmpty);

    testWidgets('first call $size', (tester) async {
      final rig = await rigFor(tester);
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.newUser)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      flowOf(tester).goTo(OnboardingStep.firstCall);
      await settle(tester, const Duration(milliseconds: 1500));
      await shot(tester, 'c-first-call-$size');
    }, skip: outDir.isEmpty);

    testWidgets('sign in with a draft $size', (tester) async {
      final rig = await rigFor(tester, lastUsed: SignInMethod.google);
      final scene = OnboardingScene();
      await rig.app.saveDraft(
        PendingCall(
          kind: PendingCallKind.call,
          marketId: scene.btc.id,
          side: Side.yes,
          question: scene.btc.question,
          savedAt: kNowMs,
        ),
      );
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.newUser)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      flowOf(tester).goTo(OnboardingStep.signIn);
      await settle(tester, const Duration(milliseconds: 1500));
      await shot(tester, 'a1-sign-in-$size');
    }, skip: outDir.isEmpty);

    testWidgets('welcome back $size', (tester) async {
      final rig = await rigFor(tester, lastUsed: SignInMethod.wallet);
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.welcomeBack, sessionEnded: true)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      await shot(tester, 'b1-welcome-back-$size');
    }, skip: outDir.isEmpty);

    testWidgets('claim username $size', (tester) async {
      final rig = await rigFor(
        tester,
        signedIn: true,
        bff: OnboardingBff(unlinked: true),
      );
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.claimOnly)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('username-field')),
        'ada_calls',
      );
      await tester.enterText(
        find.byKey(const ValueKey('username-name')),
        'Ada Okafor',
      );
      await settle(tester, const Duration(milliseconds: 900));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester, const Duration(milliseconds: 300));
      await shot(tester, 'a2-username-$size');
    }, skip: outDir.isEmpty);

    testWidgets('pick username (carried over) $size', (tester) async {
      final rig = await rigFor(tester, signedIn: true, bff: OnboardingBff());
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.claimOnly)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      await shot(tester, 'a2c-pick-username-$size');
    }, skip: outDir.isEmpty);

    for (final live in [false, true]) {
      testWidgets('on record push ${live ? 'live' : 'off'} $size', (
        tester,
      ) async {
        final rig = await rigFor(tester, signedIn: true, pushLive: live);
        final scene = OnboardingScene();
        await mountAt(
          tester,
          rig.wrap(rig.flow(OnboardingRun.newUser)),
          width: w,
          height: h,
          scale: scale,
        );
        await settle(tester);
        final entry = await rig.calls.createCall(
          CreateCallInput(marketId: scene.btc.id, side: Side.yes),
        );
        await flowOf(tester).locked(entry);
        await settle(tester, const Duration(milliseconds: 2600));
        await shot(tester, 'r-on-record-${live ? 'ask' : 'no-push'}-$size');
      }, skip: outDir.isEmpty);
    }

    testWidgets('upgrade $size', (tester) async {
      final rig = await rigFor(tester);
      await mountAt(
        tester,
        rig.wrap(rig.flow(OnboardingRun.upgrade)),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      await shot(tester, 'u1-upgrade-$size');
    }, skip: outDir.isEmpty);

    testWidgets('home setup card $size', (tester) async {
      SharedPreferences.setMockInitialValues({
        OnboardingStore.recordKey: '{"status":"lookedAround"}',
      });
      final rig = await rigFor(tester);
      await mountAt(
        tester,
        rig.wrap(
          const Scaffold(
            backgroundColor: Color(0xFFF4F4F4),
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: HomeSetupCard(),
                ),
              ),
            ),
          ),
        ),
        width: w,
        height: h,
        scale: scale,
      );
      await settle(tester);
      await shot(tester, 'k1-home-card-$size');
    }, skip: outDir.isEmpty);
  }
}
