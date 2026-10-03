// T "What are you into?" and P "Follow people who call it" (onboarding spec
// §6), acceptance as tests: real categories with real counts, steps skipped
// when the data is thin, selections announced and visible without colour,
// and follows chosen signed out kept for after sign-in.
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
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';
import 'onboarding_scenes.dart';

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
      final chips = tester.widgetList<TopicChip>(find.byType(TopicChip));
      expect(
        {for (final c in chips) c.topic.slug: c.topic.openCount},
        {
          'crypto': 3,
          'commodities': 1,
          'gaming': 1,
          'pop-culture': 1,
          'sports': 1,
        },
      );
      // The venue still calls the 30 Sep market OPEN; its close has passed.
      expect(find.byKey(const ValueKey('topic-finance')), findsNothing);
      // Nothing is preselected.
      expect(chips.every((c) => !c.selected), isTrue);
    });

    testWidgets('selection is announced and visible without colour', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final rig = await _start(tester);
      await _getStarted(tester);
      expect(find.text(OnboardingCopy.ctaSkip), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-sports')));
      await settle(tester, const Duration(milliseconds: 400));
      final node = tester.getSemantics(
        find.byKey(const ValueKey('topic-sports')),
      );
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(node.label, contains('Sports, 1 open market'));
      // A check icon, not only a colour change.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('topic-sports')),
          matching: find.byWidgetPredicate(
            (w) => w is BasilIcon && w.icon == 'check-outline',
          ),
        ),
        findsOneWidget,
      );
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

    testWidgets('fits at 320dp and 2x text: chips wrap, nothing overflows', (
      tester,
    ) async {
      await _start(tester, width: 320, height: 700, scale: 2);
      await _getStarted(tester);
      expect(find.byType(TopicsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final chip in find.byType(TopicChip).evaluate()) {
        expect(
          tester.getRect(find.byWidget(chip.widget)).right,
          lessThanOrEqualTo(320),
        );
      }
    });
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
