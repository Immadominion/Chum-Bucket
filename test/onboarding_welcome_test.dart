// W1 "Call it before it happens." (onboarding spec §6), as redesigned on
// device with the owner: a phone in perspective showing only what the server
// returned (people's calls first, then open markets to fill it), one line
// that says what the phone shows, Get started, and Sign in at the top right.
// No strip, no how-it-works list, no money line. An honest empty or offline
// phone that asks again every 15 s. It fits at 320dp and 2x text, it is read
// in order by a screen reader, and its ambient motion stops on touch and
// under reduced motion.
import 'dart:async';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/sign_in_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/topics_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/welcome_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/live_call_strip.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_motion.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_parts.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/welcome_phone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';

const _phone = ValueKey('welcome-live-strip');
const _phoneEmpty = ValueKey('welcome-phone-empty');
const _getStarted = ValueKey('welcome-get-started');
const _signIn = ValueKey('welcome-have-account');

/// How often the empty phone asks the server again.
const _retry = Duration(seconds: 15);

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

  Finder inPhone(Finder f) =>
      find.descendant(of: find.byKey(_phone), matching: f);

  testWidgets(
    'the phone shows the calls production returned, then open markets to '
    'fill it to five',
    (tester) async {
      final scene = OnboardingScene();
      final rig = await mountWelcome(tester, repo: scene.repository());
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(WelcomePhone), findsOneWidget);
      // The three live calls, then the two markets closing soonest. (The
      // phone's feed loops, so a card can appear more than once.)
      for (final t in rig.repo.top) {
        expect(inPhone(find.text(t.market.question)), findsWidgets);
      }
      expect(inPhone(find.text(scene.soon.question)), findsWidgets);
      for (final unused in [scene.eth, scene.gta, scene.stale]) {
        expect(inPhone(find.text(unused.question)), findsNothing);
      }
      // Kemi only has a placeholder handle: her name shows, the handle never.
      expect(inPhone(find.text('Kemi Bello')), findsWidgets);
      expect(find.textContaining('user-80d78065'), findsNothing);
      // A caller without a photo shows initials, not their whole name.
      expect(inPhone(find.text('AO')), findsWidgets);
      expect(find.text('ADA OKAFOR'), findsNothing);
      expect(
        rig.events(AnalyticsEventName.onboardingWelcomeLive).single,
        allOf(
          contains('source: calls'),
          contains('count: $kWelcomeFeedTarget'),
        ),
      );
    },
  );

  testWidgets('the line under the title says what the phone shows', (
    tester,
  ) async {
    await mountWelcome(tester);
    expect(find.text(OnboardingCopy.welcomeTagline), findsOneWidget);
    expect(find.text(OnboardingCopy.welcomeTaglineMarkets), findsNothing);
  });

  testWidgets(
    'nobody has called anything yet: the phone shows five open markets, and '
    'the line says so',
    (tester) async {
      final scene = OnboardingScene();
      final rig = await mountWelcome(
        tester,
        repo: scene.repository(withTop: false),
      );
      expect(find.text(OnboardingCopy.welcomeTaglineMarkets), findsOneWidget);
      expect(find.text(OnboardingCopy.welcomeTagline), findsNothing);
      for (final m in [
        scene.soon,
        scene.lakers,
        scene.btc,
        scene.stale,
        scene.album,
      ]) {
        expect(inPhone(find.text(m.question)), findsWidgets, reason: m.id);
      }
      expect(inPhone(find.text(scene.gta.question)), findsNothing);
      expect(
        rig.events(AnalyticsEventName.onboardingWelcomeLive).single,
        allOf(contains('source: markets'), contains('count: 5')),
      );
    },
  );

  testWidgets(
    'nothing live anywhere: the phone says so plainly and asks again every '
    '15 s until something answers',
    (tester) async {
      final scene = OnboardingScene();
      final repo = FakeOnboardingRepository();
      final rig = await mountWelcome(tester, repo: repo);
      expect(inPhone(find.byKey(_phoneEmpty)), findsOneWidget);
      expect(find.text(OnboardingCopy.welcomePhoneEmpty), findsOneWidget);
      expect(find.text(OnboardingCopy.welcomePhoneOffline), findsNothing);
      // The tagline still describes the product; Get started is there.
      expect(find.text(OnboardingCopy.welcomeTagline), findsOneWidget);
      expect(find.byKey(_getStarted), findsOneWidget);

      final top = repo.topReads;
      final catalog = repo.catalogReads;
      await tester.pump(_retry - const Duration(seconds: 2));
      expect(repo.topReads, top, reason: 'not before 15 s');
      expect(repo.catalogReads, catalog);
      await tester.pump(const Duration(seconds: 3));
      expect(repo.topReads, top + 1);
      expect(repo.catalogReads, catalog + 1);
      // Still nothing: still honest, and it keeps asking.
      await settle(tester);
      expect(find.byKey(_phoneEmpty), findsOneWidget);
      await tester.pump(_retry);
      expect(repo.topReads, top + 2);

      // Production answers: the next try fills the phone.
      repo
        ..top = [scene.adaBtc, scene.kemiAlbum, scene.tundeLakers]
        ..catalog = scene.catalog
        ..prices = scene.prices;
      await tester.pump(_retry);
      await settle(tester);
      expect(find.byKey(_phoneEmpty), findsNothing);
      expect(inPhone(find.text(scene.btc.question)), findsWidgets);
      expect(
        rig.events(AnalyticsEventName.onboardingWelcomeLive),
        containsAllInOrder([
          contains('source: none'),
          contains('source: calls'),
        ]),
      );
      // Resolved with something: it stops asking and never changes under
      // the reader.
      final answered = repo.topReads;
      await tester.pump(_retry * 3);
      expect(repo.topReads, answered);
    },
  );

  testWidgets(
    'a retry\'s answer reaches the phone even when it is slow to arrive',
    (tester) async {
      final scene = OnboardingScene();
      final repo = scene.repository(withTop: false)..offline = true;
      await mountWelcome(tester, repo: repo);
      expect(find.text(OnboardingCopy.welcomePhoneOffline), findsOneWidget);

      // Back online, but the market list takes a while.
      final hold = Completer<void>();
      repo
        ..offline = false
        ..holdCatalog = hold;
      await tester.pump(_retry);
      await settle(tester, const Duration(milliseconds: 500));
      // Asking again keeps the honest state up; no flash of anything else.
      expect(find.byKey(_phoneEmpty), findsOneWidget);
      hold.complete();
      await settle(tester, const Duration(milliseconds: 500));
      expect(find.byKey(_phoneEmpty), findsNothing);
      expect(inPhone(find.text(scene.soon.question)), findsWidgets);
      expect(find.text(OnboardingCopy.welcomeTaglineMarkets), findsOneWidget);
    },
  );

  testWidgets(
    'offline: the phone says so, asks again every 15 s, and the CTAs still '
    'work',
    (tester) async {
      final scene = OnboardingScene();
      final repo = scene.repository()..offline = true;
      await mountWelcome(tester, repo: repo);
      expect(inPhone(find.byKey(_phoneEmpty)), findsOneWidget);
      expect(find.text(OnboardingCopy.welcomePhoneOffline), findsOneWidget);
      expect(find.text(OnboardingCopy.welcomePhoneEmpty), findsNothing);

      final top = repo.topReads;
      await tester.pump(_retry + const Duration(seconds: 1));
      expect(repo.topReads, top + 1);
      await settle(tester);
      expect(find.text(OnboardingCopy.welcomePhoneOffline), findsOneWidget);

      // Back online: the next try shows the calls.
      repo.offline = false;
      await tester.pump(_retry);
      await settle(tester);
      expect(find.byKey(_phoneEmpty), findsNothing);
      expect(inPhone(find.text(scene.btc.question)), findsWidgets);

      await tester.tap(find.byKey(_getStarted));
      await settle(tester);
      expect(find.byType(WelcomeScreen), findsNothing);
    },
  );

  testWidgets(
    'one screen: no scrolling strip, no how-it-works list, no money line',
    (tester) async {
      await mountWelcome(tester);
      expect(find.byType(LiveCallStrip), findsNothing);
      expect(find.byType(HowItWorksList), findsNothing);
      expect(find.text(OnboardingCopy.welcomeMoney), findsNothing);
      expect(find.text(OnboardingCopy.welcomeBody), findsNothing);
      for (final word in ['deposit', 'wallet', 'Add funds', 'balance']) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
      // Nothing to scroll to: the page itself does not scroll.
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text(OnboardingCopy.welcomeTitle), findsOneWidget);
      expect(find.byKey(_getStarted), findsOneWidget);
    },
  );

  for (final (width, height, scale) in [
    (390.0, 844.0, 1.0),
    (390.0, 844.0, 1.3),
    (320.0, 640.0, 2.0),
  ]) {
    testWidgets(
      'fits at ${width.toInt()}dp and ${scale}x text: title, line, Get started '
      'and Sign in all on screen, nothing overflows',
      (tester) async {
        await mountWelcome(tester, width: width, height: height, scale: scale);
        expect(tester.takeException(), isNull);
        final cta = tester.getRect(find.byKey(_getStarted));
        final signIn = tester.getRect(find.byKey(_signIn));
        final title = tester.getRect(find.text(OnboardingCopy.welcomeTitle));
        final tagline = tester.getRect(
          find.text(OnboardingCopy.welcomeTagline),
        );
        for (final rect in [cta, signIn, title, tagline]) {
          expect(rect.top, greaterThanOrEqualTo(0), reason: '$rect');
          expect(rect.left, greaterThanOrEqualTo(0), reason: '$rect');
          expect(rect.bottom, lessThanOrEqualTo(height), reason: '$rect');
          expect(rect.right, lessThanOrEqualTo(width), reason: '$rect');
        }
        // Sign in is the top-right action, a 48dp target.
        expect(signIn.bottom, lessThan(title.top));
        expect(signIn.center.dx, greaterThan(width / 2));
        expect(signIn.height, greaterThanOrEqualTo(48));
        expect(title.bottom, lessThanOrEqualTo(tagline.top));
        expect(tagline.bottom, lessThanOrEqualTo(cta.top));
        // The title stops growing where onboarding titles do, so no word
        // breaks mid-word; the miniature phone keeps its own type size.
        final titleScale = tester
            .widget<Text>(find.text(OnboardingCopy.welcomeTitle))
            .textScaler!
            .scale(10);
        expect(titleScale, lessThanOrEqualTo(10 * OnbTitle.maxTitleScale));
        final card = tester.element(inPhone(find.text('Ada Okafor')).first);
        expect(MediaQuery.textScalerOf(card).scale(10), 10);
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
    // Each card is one button: "{name} called YES on {question}".
    final scene = OnboardingScene();
    expect(
      find.bySemanticsLabel(
        RegExp(
          '^Ada Okafor called YES on ${RegExp.escape(scene.btc.question)}',
        ),
      ),
      findsWidgets,
    );
    expect(
      find.bySemanticsLabel(OnboardingCopy.welcomeSignInShort),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a call card opens the real call; Back returns to Welcome', (
    tester,
  ) async {
    await mountWelcome(tester);
    await tester.tap(inPhone(find.text('Ada Okafor')).first);
    await settle(tester);
    expect(find.byType(CallDetailScreen), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(CallDetailScreen), findsNothing);
  });

  testWidgets('a market card opens the market', (tester) async {
    final scene = OnboardingScene();
    await mountWelcome(tester, repo: scene.repository(withTop: false));
    await tester.tap(inPhone(find.text(scene.soon.question)).first);
    await settle(tester);
    final detail = tester.widget<MarketDetailScreen>(
      find.byType(MarketDetailScreen),
    );
    expect(detail.marketId, scene.soon.id);
  });

  testWidgets('Get started opens Topics; Sign in (top right) opens B1', (
    tester,
  ) async {
    final rig = await mountWelcome(tester);
    expect(
      find.descendant(
        of: find.byKey(_signIn),
        matching: find.text(OnboardingCopy.welcomeSignInShort),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(_signIn));
    await settle(tester);
    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.text(OnboardingCopy.backTitle), findsOneWidget);
    // System Back from Welcome back returns to Welcome.
    final popped = await tester.binding.handlePopRoute();
    expect(popped, isTrue);
    await settle(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);

    await tester.tap(find.byKey(_getStarted));
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

  // Ambient loops are off for every other widget test
  // (test/flutter_test_config.dart); here they run as they do in the app.
  group('ambient motion', () {
    setUp(() => onbAmbientMotion = true);
    tearDown(() => onbAmbientMotion = false);

    /// How far the drag-up hint has lifted the phone (negative: up).
    double lift(WidgetTester tester) {
      final hint = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_PeekHint',
      );
      final transform = tester.widget<Transform>(
        find.descendant(of: hint, matching: find.byType(Transform)).first,
      );
      return transform.transform.getTranslation().y;
    }

    /// How far the phone's feed has advanced on its own.
    double advanced(WidgetTester tester) =>
        tester
            .state<ScrollableState>(inPhone(find.byType(Scrollable)).first)
            .position
            .pixels;

    /// The highest lift seen while pumping [duration] in small steps.
    Future<double> highestLift(WidgetTester tester, Duration duration) async {
      var highest = 0.0;
      const step = Duration(milliseconds: 100);
      for (var t = Duration.zero; t < duration; t += step) {
        await tester.pump(step);
        final y = lift(tester);
        if (y < highest) highest = y;
      }
      return highest;
    }

    testWidgets(
      'the drag-up hint lifts the phone until the first touch, then never '
      'again',
      (tester) async {
        await mountWelcome(tester);
        // First peek 1.5 s in: the phone lifts, then settles back.
        expect(
          await highestLift(tester, const Duration(seconds: 2)),
          lessThan(-20),
        );
        expect(lift(tester), moreOrLessEquals(0, epsilon: .5));
        // The feed advances one card on its own.
        await settle(tester, const Duration(milliseconds: 1500));
        expect(advanced(tester), greaterThan(0));

        // A touch on the phone: the hint stops for good (it would have
        // peeked again 6 s after the first).
        await tester.drag(find.byKey(_phone), const Offset(0, -40));
        expect(
          await highestLift(tester, const Duration(seconds: 12)),
          moreOrLessEquals(0, epsilon: .5),
        );
      },
    );

    testWidgets(
      'reduced motion: no hint, no auto-advance, no pulse or floating '
      'callers; the screen settles',
      (tester) async {
        await mountWelcome(tester, reduceMotion: true);
        // Any running loop would keep scheduling frames and time this out.
        await tester.pumpAndSettle();
        expect(await highestLift(tester, const Duration(seconds: 10)), 0);
        expect(advanced(tester), 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  });
}
