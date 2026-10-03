// T "What are you into?" and P "Follow people who call it" (onboarding spec
// §6), acceptance as tests: real categories with real counts on big tiles
// docked above Continue, steps skipped when the data is thin, selections
// announced and visible without colour, and follows chosen signed out kept
// for after sign-in.
import 'dart:ui' show Tristate;

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_steps.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/onboarding_flow_controller.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/first_call_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/people_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/screens/topics_screen.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/suggested_person_row.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/topic_chip.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
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

Future<OnboardingRig> _start(
  WidgetTester tester, {
  FakeOnboardingRepository? repo,
  double width = 390,
  double height = 844,
  double scale = 1,
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
  );
  await settle(tester);
  return rig;
}

Future<void> _getStarted(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('welcome-get-started')));
  await settle(tester);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('T Topics', () {
    testWidgets('only categories with open markets, with their real counts', (
      tester,
    ) async {
      await _start(tester);
      await _getStarted(tester);
      expect(find.byType(TopicsScreen), findsOneWidget);
      final tiles = tester.widget<TopicTiles>(find.byType(TopicTiles));
      expect(
        {for (final t in tiles.topics) t.slug: t.openCount},
        {
          'crypto': 3,
          'commodities': 1,
          'gaming': 1,
          'pop-culture': 1,
          'sports': 1,
        },
      );
      for (final t in tiles.topics) {
        expect(find.byKey(ValueKey('topic-${t.slug}')), findsOneWidget);
      }
      // Each tile says its real count.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('topic-crypto')),
          matching: find.text(OnboardingCopy.topicTileCount(3)),
        ),
        findsOneWidget,
      );
      expect(find.text(OnboardingCopy.topicTileCount(1)), findsNWidgets(4));
      // The venue still calls the 30 Sep market OPEN; its close has passed.
      expect(find.byKey(const ValueKey('topic-finance')), findsNothing);
      // Nothing is preselected.
      expect(tiles.selected, isEmpty);
    });

    testWidgets(
      'the tiles sit above Continue, two to a row, under the note; the '
      'illustration is in the page',
      (tester) async {
        await _start(tester);
        await _getStarted(tester);
        expect(find.text(OnboardingCopy.topicsBody), findsOneWidget);
        final page = find.byType(SingleChildScrollView);
        // Docked in the sticky actions, not in the scrolling page.
        expect(
          find.descendant(of: page, matching: find.byType(TopicTiles)),
          findsNothing,
        );
        expect(
          find.descendant(of: page, matching: find.byType(ChumbucketStateArt)),
          findsOneWidget,
        );
        final note = tester.getRect(find.text(OnboardingCopy.topicsNote));
        final crypto = tester.getRect(
          find.byKey(const ValueKey('topic-crypto')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('topic-commodities')),
        );
        final cta = tester.getRect(
          find.byKey(const ValueKey('topics-continue')),
        );
        expect(note.bottom, lessThanOrEqualTo(crypto.top));
        expect(second.center.dy, crypto.center.dy, reason: 'two to a row');
        expect(second.left, greaterThan(crypto.right));
        for (final t
            in tester.widget<TopicTiles>(find.byType(TopicTiles)).topics) {
          final tile = tester.getRect(find.byKey(ValueKey('topic-${t.slug}')));
          expect(tile.bottom, lessThanOrEqualTo(cta.top), reason: t.slug);
          expect(tile.height, greaterThanOrEqualTo(48), reason: t.slug);
        }
        expect(cta.bottom, lessThanOrEqualTo(844));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('selection is announced and visible without colour', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _start(tester);
      await _getStarted(tester);
      expect(find.text(OnboardingCopy.ctaSkip), findsOneWidget);
      final check = find.descendant(
        of: find.byKey(const ValueKey('topic-sports')),
        matching: find.byWidgetPredicate(
          (w) => w is BasilIcon && w.icon == 'check-outline',
        ),
      );
      double checkScale() =>
          tester
              .widget<AnimatedScale>(
                find.ancestor(of: check, matching: find.byType(AnimatedScale)),
              )
              .scale;
      expect(checkScale(), 0, reason: 'no check before it is chosen');
      await tester.tap(find.byKey(const ValueKey('topic-sports')));
      await settle(tester, const Duration(milliseconds: 400));
      final node = tester.getSemantics(
        find.byKey(const ValueKey('topic-sports')),
      );
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.label, contains('Sports, 1 open market'));
      // A check icon, not only a colour change.
      expect(check, findsOneWidget);
      expect(checkScale(), 1);
      expect(find.text(OnboardingCopy.ctaContinue), findsOneWidget);
      expect(
        rig.events(AnalyticsEventName.onboardingTopicToggled).single,
        allOf(contains('sports'), contains('selected: true')),
      );
      handle.dispose();
    });

    testWidgets('choosing Sports ranks Sports first in C and Markets', (
      tester,
    ) async {
      final rig = await _start(tester);
      final scene = OnboardingScene();
      await _getStarted(tester);
      await tester.tap(find.byKey(const ValueKey('topic-sports')));
      await settle(tester, const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('topics-continue')));
      await settle(tester, const Duration(milliseconds: 1500));
      expect(rig.app.topics, {'sports'});
      // Markets opens on "For you" the first time.
      expect(rig.app.record.forYouPending, isTrue);
      final flow = _flow(tester);
      expect(flow.firstCallMarkets.first.market.id, scene.lakers.id);
    });

    testWidgets('fewer than two categories: Topics is skipped for you', (
      tester,
    ) async {
      final scene = OnboardingScene();
      final repo = scene.repository()..catalog = [scene.btc, scene.eth];
      await _start(tester, repo: repo);
      expect(_flow(tester).steps, isNot(contains(OnboardingStep.topics)));
      await _getStarted(tester);
      expect(find.byType(TopicsScreen), findsNothing);
    });

    testWidgets('"Skip for now" with nothing chosen still moves on', (
      tester,
    ) async {
      final rig = await _start(tester);
      await _getStarted(tester);
      await tester.tap(find.byKey(const ValueKey('topics-continue')));
      await settle(tester);
      expect(find.byType(TopicsScreen), findsNothing);
      expect(rig.app.topics, isEmpty);
      expect(
        rig.events(AnalyticsEventName.onboardingStepCompleted),
        contains(allOf(contains('topics'), contains('skipped'))),
      );
    });

    testWidgets(
      'fits at 320dp and 2x text: the tiles move into the page, one to a '
      'row; Continue stays docked; nothing overflows',
      (tester) async {
        await _start(tester, width: 320, height: 700, scale: 2);
        await _getStarted(tester);
        expect(find.byType(TopicsScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        final page = find.byType(SingleChildScrollView);
        expect(
          find.descendant(of: page, matching: find.byType(TopicTiles)),
          findsOneWidget,
        );
        expect(tester.widget<TopicTiles>(find.byType(TopicTiles)).columns, 1);
        final cta = tester.getRect(
          find.byKey(const ValueKey('topics-continue')),
        );
        expect(cta.bottom, lessThanOrEqualTo(700));
        expect(
          find.descendant(
            of: page,
            matching: find.byType(ChumbucketPrimaryButton),
          ),
          findsNothing,
        );
        // Every tile is reachable by scrolling, and inside the screen.
        for (final t
            in tester.widget<TopicTiles>(find.byType(TopicTiles)).topics) {
          final tile = find.byKey(ValueKey('topic-${t.slug}'));
          await tester.dragUntilVisible(tile, page, const Offset(0, -200));
          await settle(tester, const Duration(milliseconds: 100));
          final rect = tester.getRect(tile);
          expect(rect.left, greaterThanOrEqualTo(0), reason: t.slug);
          expect(rect.right, lessThanOrEqualTo(320), reason: t.slug);
          expect(rect.bottom, lessThanOrEqualTo(cta.top), reason: t.slug);
        }
        await tester.tap(find.byKey(const ValueKey('topic-pop-culture')));
        await settle(tester, const Duration(milliseconds: 300));
        expect(_flow(tester).selectedTopics, {'pop-culture'});
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('P People', () {
    Future<void> toPeople(WidgetTester tester) async {
      await _getStarted(tester);
      await tester.tap(find.byKey(const ValueKey('topics-continue')));
      await settle(tester);
    }

    testWidgets('every row is a person the server suggested, no more', (
      tester,
    ) async {
      final rig = await _start(tester);
      await toPeople(tester);
      expect(find.byType(PeopleScreen), findsOneWidget);
      expect(
        find.byType(SuggestedPersonRow),
        findsNWidgets(rig.repo.suggestions!.people.length),
      );
      expect(find.text('8 of 10 called right'), findsOneWidget);
      expect(find.text('3 settled · building a record'), findsOneWidget);
      expect(find.text('2 open calls'), findsOneWidget);
      expect(find.textContaining('user-80d78065'), findsNothing);
      // No ranks, medals, money or follower counts.
      expect(find.textContaining('#1'), findsNothing);
      expect(find.textContaining('USDC'), findsNothing);
      expect(find.textContaining('followers'), findsNothing);
    });

    testWidgets("with one real caller (2 Oct production) P doesn't appear", (
      tester,
    ) async {
      final scene = OnboardingScene();
      final repo =
          scene.repository()
            ..suggestions = PeopleSuggestions(
              friends: const [],
              people: [scene.suggestions.people.first],
              servedAt: kNowMs,
            );
      await _start(tester, repo: repo);
      await toPeople(tester);
      expect(find.byType(PeopleScreen), findsNothing);
      expect(find.byType(FirstCallScreen), findsOneWidget);
    });

    testWidgets('follows chosen signed out wait on this phone for sign-in', (
      tester,
    ) async {
      final rig = await _start(tester);
      await toPeople(tester);
      expect(find.text(OnboardingCopy.pendingNote), findsNothing);
      await tester.tap(find.byKey(const ValueKey('follow-user-ada')));
      await settle(tester, const Duration(milliseconds: 300));
      expect(find.text(OnboardingCopy.pendingNote), findsOneWidget);
      expect(rig.app.pendingFollowIds, {'user-ada'});
      expect(rig.repo.followed, isEmpty);
      expect(find.text(OnboardingCopy.ctaContinue), findsOneWidget);
    });

    testWidgets(
      'follows chosen signed out are applied during the run once signed in — '
      'even though the calls slice learns the account a frame later',
      (tester) async {
        final rig = OnboardingRig(
          repo: OnboardingScene().repository(),
          bindViewerLate: true,
        );
        await tester.runAsync(rig.start);
        addTearDown(rig.dispose);
        await mountAt(
          tester,
          rig.flow(OnboardingRun.newUser),
          around: rig.wrap,
          height: 1000,
        );
        await settle(tester);
        await toPeople(tester);
        await tester.tap(find.byKey(const ValueKey('follow-user-ada')));
        await settle(tester, const Duration(milliseconds: 300));
        await tester.tap(find.byKey(const ValueKey('people-continue')));
        await settle(tester, const Duration(milliseconds: 1500));
        expect(find.byType(FirstCallScreen), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('first-call-later')));
        await settle(tester);

        rig.auth.deliverOnSignIn = snapshot();
        await tester.tap(find.byKey(const ValueKey('front-door-google')));
        await settle(tester, const Duration(milliseconds: 1500));
        expect(rig.session.isReady, isTrue);
        expect(rig.repo.followed, ['user-ada']);
        expect(rig.app.pendingFollowIds, isEmpty);
      },
    );

    testWidgets('Follow all, then Unfollow all, both announced as state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _start(tester);
      await toPeople(tester);
      await tester.tap(find.byKey(const ValueKey('people-follow-all')));
      await settle(tester, const Duration(milliseconds: 300));
      expect(rig.app.pendingFollowIds, hasLength(3));
      expect(find.text(OnboardingCopy.unfollowAll), findsOneWidget);
      final ada = tester.getSemantics(
        find.byKey(const ValueKey('follow-user-ada')),
      );
      expect(ada.flagsCollection.isToggled, Tristate.isTrue);
      await tester.tap(find.byKey(const ValueKey('people-follow-all')));
      await settle(tester, const Duration(milliseconds: 300));
      expect(rig.app.pendingFollowIds, isEmpty);
      handle.dispose();
    });

    testWidgets('each row reads as one sentence: name, record, latest call', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final scene = OnboardingScene();
      await _start(tester);
      await toPeople(tester);
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^Ada Okafor, 8 of 10 called right\\. Latest call YES on '
            '${RegExp.escape(scene.btc.question)}\\.',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('at 2x text the Follow button moves under the name', (
      tester,
    ) async {
      await _start(tester, width: 320, height: 900, scale: 2);
      await toPeople(tester);
      expect(tester.takeException(), isNull);
      final name = tester.getRect(find.text('Ada Okafor'));
      final button = tester.getRect(
        find.byKey(const ValueKey('follow-user-ada')),
      );
      expect(button.top, greaterThan(name.bottom));
    });
  });
}
