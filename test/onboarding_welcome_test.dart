// W1 "Call it before it happens." (onboarding spec §6), acceptance as tests:
// only what the server returned reaches the strip, nothing is left blank,
// placeholder handles never show, it works at 320dp and 2x text, and it is
// read in order by a screen reader.
import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/sign_in_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/topics_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/live_call_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<OnboardingRig> mountWelcome(
    WidgetTester tester, {
    FakeOnboardingRepository? repo,
    double width = 390,
    double height = 844,
    double scale = 1,
    bool reduceMotion = false,
  }) async {
    final rig = OnboardingRig(repo: repo ?? OnboardingScene().repository());
    await tester.runAsync(rig.start);
    addTearDown(rig.dispose);
    await mountAt(
      tester,
      rig.flow(OnboardingRun.newUser),
      around: rig.wrap,
      width: width,
      height: height,
      scale: scale,
      reduceMotion: reduceMotion,
    );
    await settle(tester);
    return rig;
  }

  testWidgets('the strip shows exactly the live calls production returned', (
    tester,
  ) async {
    final scene = OnboardingScene();
    final rig = await mountWelcome(tester, repo: scene.repository());
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text(OnboardingCopy.welcomeLiveCalls), findsOneWidget);
    expect(find.byType(LiveCallCard), findsNWidgets(rig.repo.top.length));
    for (final t in rig.repo.top) {
      expect(find.text(t.market.question), findsOneWidget);
    }
    // Kemi only has a placeholder handle: her name shows, the handle never.
    expect(find.text('Kemi Bello'), findsOneWidget);
    expect(find.textContaining('user-80d78065'), findsNothing);
    expect(
      rig.events(AnalyticsEventName.onboardingWelcomeLive).single,
      contains('source: top'),
    );
  });

  testWidgets('no live calls: the strip falls back to open Panta markets', (
    tester,
  ) async {
    final scene = OnboardingScene();
    await mountWelcome(tester, repo: scene.repository(withTop: false));
    expect(find.text(OnboardingCopy.welcomeLiveMarkets), findsOneWidget);
    expect(find.byType(LiveMarketCard), findsNWidgets(3));
    expect(find.byType(LiveCallCard), findsNothing);
  });

  testWidgets('nothing live anywhere: no strip, no label, no blank gap', (
    tester,
  ) async {
    await mountWelcome(tester, repo: FakeOnboardingRepository());
    expect(find.text(OnboardingCopy.welcomeLiveCalls), findsNothing);
    expect(find.text(OnboardingCopy.welcomeLiveMarkets), findsNothing);
    expect(find.byType(LiveCallStrip), findsNothing);
    expect(find.byType(LiveStripSkeleton), findsNothing);
    // The body flows straight into "how it works".
    final body = tester.getBottomLeft(find.text(OnboardingCopy.welcomeBody));
    final how = tester.getTopLeft(
      find.textContaining(OnboardingCopy.howCallLead),
    );
    expect(how.dy - body.dy, lessThan(48));
  });

  testWidgets('offline: says so in place of the strip; the CTAs still work', (
    tester,
  ) async {
    final repo = OnboardingScene().repository()..offline = true;
    await mountWelcome(tester, repo: repo);
    expect(find.text(OnboardingCopy.welcomeOffline), findsOneWidget);
    expect(find.byType(LiveCallStrip), findsNothing);
    await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('says money once, truthfully, and how it works in three lines', (
    tester,
  ) async {
    await mountWelcome(tester);
    expect(find.text(OnboardingCopy.welcomeMoney), findsOneWidget);
    expect(find.textContaining(OnboardingCopy.howCallBody), findsOneWidget);
    expect(find.textContaining(OnboardingCopy.howSideBody), findsOneWidget);
    expect(find.textContaining(OnboardingCopy.howReceiptBody), findsOneWidget);
  });

  for (final (width, scale) in [(390.0, 1.0), (390.0, 1.3), (320.0, 2.0)]) {
    testWidgets(
      'fits at ${width.toInt()}dp and ${scale}x text, CTA always visible',
      (tester) async {
        await mountWelcome(
          tester,
          width: width,
          height: scale > 1.5 ? 640 : 844,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        final cta = find.byKey(const ValueKey('welcome-get-started'));
        final rect = tester.getRect(cta);
        expect(rect.bottom, lessThanOrEqualTo(scale > 1.5 ? 640 : 844));
        expect(rect.top, greaterThan(0));
        // Everything else is reachable by scrolling.
        await tester.dragUntilVisible(
          find.text(OnboardingCopy.welcomeMoney),
          find.byType(SingleChildScrollView).first,
          const Offset(0, -200),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a screen reader hears the title first, as a heading', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await mountWelcome(tester);
    final title = tester.getSemantics(find.text(OnboardingCopy.welcomeTitle));
    expect(title.flagsCollection.isHeader, isTrue);
    // Each card is one button: "{name} called YES on {question}. Closes …".
    final scene = OnboardingScene();
    expect(
      find.bySemanticsLabel(
        RegExp(
          '^Ada Okafor called YES on ${RegExp.escape(scene.btc.question)}\\. '
          'Closes in 4 days\\.\$',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a card opens the real call; Back returns to Welcome', (
    tester,
  ) async {
    await mountWelcome(tester);
    await tester.tap(find.byType(LiveCallCard).first);
    await settle(tester);
    expect(find.byType(CallDetailScreen), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(CallDetailScreen), findsNothing);
  });

  testWidgets('Get started opens Topics; I already have an account opens B1', (
    tester,
  ) async {
    final rig = await mountWelcome(tester);
    await tester.tap(find.byKey(const ValueKey('welcome-have-account')));
    await settle(tester);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text(OnboardingCopy.backTitle), findsOneWidget);
    // System Back from Welcome back returns to Welcome.
    final popped = await tester.binding.handlePopRoute();
    expect(popped, isTrue);
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
    await settle(tester);
    expect(find.byType(TopicsScreen), findsOneWidget);
    expect(
      rig.events(AnalyticsEventName.onboardingStepCompleted),
      contains(allOf(contains('welcome'), contains('get_started'))),
    );
    expect(
      rig.events(AnalyticsEventName.onboardingStarted).single,
      contains('welcome'),
    );
  });

  testWidgets('reduced motion: everything is there at once, no rise', (
    tester,
  ) async {
    await mountWelcome(tester, reduceMotion: true);
    expect(find.text(OnboardingCopy.welcomeTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
