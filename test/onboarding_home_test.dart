// What onboarding leaves on Home (onboarding spec §6 "Home arrival"): the
// first Home opens on Following only when it has a call to show, says what
// happened to the follows, and a later sign-in offers the waiting draft
// again — never locks it.
import 'dart:convert';

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/onboarding_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';
import 'session_fakes.dart';

Future<OnboardingRig> _home(
  WidgetTester tester, {
  required OnboardingRig rig,
  HomeArrival? arrival,
}) async {
  await tester.runAsync(rig.start);
  addTearDown(rig.dispose);
  if (arrival != null) rig.app.setArrival(arrival);
  await mountAt(
    tester,
    const OnboardingHomeEffects(child: Scaffold(body: SizedBox())),
    around: rig.wrap,
  );
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await settle(tester);
  return rig;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('followed someone with a call: Home opens on Following', (
    tester,
  ) async {
    final scene = OnboardingScene();
    final repo =
        scene.repository()..followingFeed = [scene.feedEntry(scene.adaBtc)];
    final rig = await _home(
      tester,
      rig: OnboardingRig(
        repo: repo,
        signedIn: true,
        bff: OnboardingBff(handle: 'ada'),
      ),
      arrival: const HomeArrival(followed: 1),
    );
    expect(rig.calls.feedMode, CallFeedMode.following);
    expect(find.text(OnboardingCopy.followingApplied(1, null)), findsOneWidget);
  });

  testWidgets(
    'followed people with nothing live: Global, never an empty Following',
    (tester) async {
      final rig = await _home(
        tester,
        rig: OnboardingRig(
          repo: OnboardingScene().repository(),
          signedIn: true,
          bff: OnboardingBff(handle: 'ada'),
        ),
        arrival: const HomeArrival(followed: 2),
      );
      expect(rig.calls.feedMode, CallFeedMode.global);
    },
  );

  testWidgets('follows that could not be applied are said plainly', (
    tester,
  ) async {
    await _home(
      tester,
      rig: OnboardingRig(
        repo: OnboardingScene().repository(),
        signedIn: true,
        bff: OnboardingBff(handle: 'ada'),
      ),
      arrival: const HomeArrival(failed: 1),
    );
    expect(find.text(OnboardingCopy.followApplyFailed(1)), findsOneWidget);
  });

  testWidgets('signing in later applies waiting follows and offers the draft', (
    tester,
  ) async {
    final scene = OnboardingScene();
    SharedPreferences.setMockInitialValues({
      OnboardingStore.pendingFollowsKey:
          '{"ids":["user-ada"],"savedAt":$kNowMs}',
      OnboardingStore.pendingCallKey: jsonEncode({
        'kind': 'call',
        'marketId': scene.btc.id,
        'side': 'YES',
        'question': scene.btc.question,
        'savedAt': kNowMs,
      }),
    });
    final rig = OnboardingRig(
      repo: scene.repository(),
      bff: OnboardingBff(handle: 'ada'),
    );
    await _home(tester, rig: rig);
    expect(rig.repo.followed, isEmpty, reason: 'signed out: nothing applied');

    // Signing in from anywhere (here: a session the SDK hands over).
    rig.auth.restored = snapshot();
    await tester.runAsync(rig.session.restore);
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(rig.session.isReady, isTrue);
    expect(rig.repo.followed, ['user-ada']);
    expect(find.text(OnboardingCopy.followingApplied(1, null)), findsOneWidget);
    // Then, once that note has gone, the waiting call. (Its timer started
    // on the session's own zone, so the test dismisses it.)
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).hideCurrentSnackBar();
    await settle(tester);
    expect(find.byKey(const ValueKey('home-pending-call')), findsOneWidget);
    expect(find.text(OnboardingCopy.pendingCallCta), findsOneWidget);
    // Offered, never locked on its own.
    expect(rig.repo.created, isEmpty);
    expect(rig.app.pendingCall?.side, Side.yes);
  });

  for (final offered in [false, true]) {
    testWidgets(
      offered
          ? 'Home\'s feed leads with "Make Home yours" while it is offered'
          : 'Home\'s feed takes no slot (and no gap) for a card nobody is offered',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          if (offered) OnboardingStore.recordKey: '{"status":"lookedAround"}',
        });
        final scene = OnboardingScene();
        final repo = scene.repository()..feed = [scene.feedEntry(scene.adaBtc)];
        final rig = OnboardingRig(repo: repo);
        await tester.runAsync(rig.start);
        addTearDown(rig.dispose);
        await mountAt(
          tester,
          const Scaffold(
            body: CallFeedScreen(showHeader: false, topBanner: HomeSetupCard()),
          ),
          around: rig.wrap,
        );
        await settle(tester, const Duration(milliseconds: 900));
        expect(find.byType(CallCard), findsWidgets);
        expect(
          find.byType(HomeSetupCard),
          offered ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('home-setup-card')),
          offered ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets(
    'Markets opens on "For you" once: chosen topics first, the rest after',
    (tester) async {
      final scene = OnboardingScene();
      final rig = OnboardingRig(repo: scene.repository());
      await tester.runAsync(() async {
        await rig.start();
        await rig.app.setTopics({'sports'});
      });
      addTearDown(rig.dispose);
      await mountAt(
        tester,
        const Scaffold(body: CallMarketsScreen()),
        around: rig.wrap,
        height: 1400,
      );
      await settle(tester, const Duration(milliseconds: 1200));
      expect(find.text('For you'), findsOneWidget);
      expect(find.text('More markets'), findsOneWidget);
      final rows = tester.widgetList<CallMarketCard>(
        find.byType(CallMarketCard),
      );
      expect(rows.first.market.id, scene.lakers.id);
      // Nothing hidden: every open market is still listed.
      expect(
        rows.map((r) => r.market.id).toSet(),
        containsAll([scene.btc.id, scene.album.id, scene.gta.id]),
      );
      // Shown on "For you" once; afterwards Markets keeps its own filter.
      expect(rig.app.record.forYouPending, isFalse);
    },
  );
}
