// Onboarding's per-install memory (onboarding spec §12): round trips,
// expiry, what sign-out forgets, and follows chosen before sign-in applied
// exactly once afterwards.
import 'dart:convert';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/data/onboarding_store.dart';
import 'package:chumbucket/features/onboarding/domain/entry_decision.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'onboarding_fakes.dart';

PendingCall _draft({
  int? savedAt,
  PendingCallKind kind = PendingCallKind.call,
}) => PendingCall(
  kind: kind,
  marketId: 'm-1',
  side: Side.no,
  thesis: 'The close matters, not the wick.',
  visibility: CallVisibility.followers,
  confidence: .7,
  targetCallId: kind == PendingCallKind.call ? null : 'call-9',
  question: 'Will it?',
  savedAt: savedAt ?? kNowMs,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('records round-trip', () {
    test('the onboarding record', () {
      const record = OnboardingRecord(
        status: OnboardingStatus.inProgress,
        stage: 'topics',
        stageAt: 1,
        startedAt: 2,
        homeCardShows: 2,
        homeCardDeclines: 1,
        upgradeIntroSeen: true,
        handleClaimDeferred: true,
        forYouPending: true,
        setupSkipped: true,
      );
      final back = OnboardingRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
      );
      expect(back.toJson(), record.toJson());
      expect(record.toJson()['v'], 2);
    });

    test(
      'the draft call keeps market, side, reason, visibility and parent',
      () {
        for (final kind in PendingCallKind.values) {
          final draft = _draft(kind: kind);
          final back =
              PendingCall.fromJson(
                jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
              )!;
          expect(back.toJson(), draft.toJson(), reason: '$kind');
        }
      },
    );

    test('a damaged or incomplete draft is no draft', () {
      expect(PendingCall.fromJson({'kind': 'call'}), isNull);
      expect(
        PendingCall.fromJson({..._draft().toJson(), 'side': 'MAYBE'}),
        isNull,
      );
      // A Back or Fade must say which call it answers.
      expect(
        PendingCall.fromJson({
          ..._draft(kind: PendingCallKind.back).toJson(),
          'targetCallId': null,
        }),
        isNull,
      );
    });
  });

  group('lifetimes', () {
    const store = OnboardingStore();

    test('a draft lives 24 hours, then is forgotten', () async {
      await store.writePendingCall(_draft());
      expect(
        await store.readPendingCall(kNow.add(const Duration(hours: 23))),
        isNotNull,
      );
      expect(
        await store.readPendingCall(kNow.add(const Duration(hours: 25))),
        isNull,
      );
      // Expired means removed, not just hidden.
      expect(await store.readPendingCall(kNow), isNull);
    });

    test('pending follows live 7 days', () async {
      await store.writePendingFollows(PendingFollows(const ['a', 'b'], kNowMs));
      expect(
        (await store.readPendingFollows(
          kNow.add(const Duration(days: 6)),
        ))?.ids,
        ['a', 'b'],
      );
      expect(
        await store.readPendingFollows(kNow.add(const Duration(days: 8))),
        isNull,
      );
    });

    test(
      'sign-out forgets the draft and follows, keeps topics and status',
      () async {
        await store.writeTopics(const ['sports']);
        await store.writeRecord(
          const OnboardingRecord(status: OnboardingStatus.completed),
        );
        await store.writePendingCall(_draft());
        await store.writePendingFollows(PendingFollows(const ['a'], kNowMs));
        await store.clearForSignOut();
        expect(await store.readPendingCall(kNow), isNull);
        expect(await store.readPendingFollows(kNow), isNull);
        expect(await store.readTopics(), ['sports']);
        expect((await store.readRecord()).status, OnboardingStatus.completed);
      },
    );

    test('the old carousel flag is read, never written', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingStore.legacyCompletedKey: true,
      });
      expect(await store.legacyOnboardingCompleted(), isTrue);
      final app = OnboardingController(clock: () => kNow);
      await app.load();
      await app.startRun('welcome');
      await app.complete();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(OnboardingStore.legacyCompletedKey), isTrue);
      expect(app.legacyOnboardingCompleted, isTrue);
    });

    test('unreadable prefs start a fresh record, never a crash', () async {
      SharedPreferences.setMockInitialValues({
        OnboardingStore.recordKey: '{not json',
        OnboardingStore.pendingCallKey: '[]',
      });
      expect((await store.readRecord()).status, OnboardingStatus.fresh);
      expect(await store.readPendingCall(kNow), isNull);
    });
  });

  group('follows chosen before sign-in (§6 P)', () {
    late FakeOnboardingRepository repo;
    late CallsProvider calls;
    late OnboardingController app;
    late InMemoryAnalyticsSink sink;

    setUp(() async {
      repo = FakeOnboardingRepository();
      sink = InMemoryAnalyticsSink();
      final analytics = AnalyticsRecorder(sink: sink);
      calls = CallsProvider(repository: repo, analytics: analytics);
      app = OnboardingController(clock: () => kNow, analytics: analytics);
      await app.load();
    });

    tearDown(() {
      calls.dispose();
      app.dispose();
    });

    test('survive app kill (they are in prefs)', () async {
      await app.setPendingFollows({'user-ada', 'user-kemi'});
      final again = OnboardingController(clock: () => kNow);
      await again.load();
      expect(again.pendingFollowIds, {'user-ada', 'user-kemi'});
      again.dispose();
    });

    test('nothing is applied signed out', () async {
      await app.setPendingFollows({'user-ada'});
      expect(await app.applyPendingFollows(calls), isNull);
      expect(repo.followed, isEmpty);
      expect(app.pendingFollowIds, {'user-ada'});
    });

    test('applied exactly once after sign-in, even when asked twice', () async {
      await app.setPendingFollows({'user-ada', 'user-kemi'});
      calls.setViewer('me');
      final results = await Future.wait([
        app.applyPendingFollows(calls),
        app.applyPendingFollows(calls),
      ]);
      expect(identical(results[0], results[1]), isTrue);
      expect(repo.followed..sort(), ['user-ada', 'user-kemi']);
      expect(app.pendingFollowIds, isEmpty);
      expect(await app.applyPendingFollows(calls), isNull);
      expect(repo.followed, hasLength(2));
      expect(
        sink.named(AnalyticsEventName.onboardingFollowsApplied),
        hasLength(1),
      );
    });

    test('a failure is tried once more, then reported', () async {
      repo.failFollowIds.add('user-kemi');
      await app.setPendingFollows({'user-ada', 'user-kemi'});
      calls.setViewer('me');
      final result = (await app.applyPendingFollows(calls))!;
      expect(result.succeeded, ['user-ada']);
      expect(result.failed, ['user-kemi']);
      expect(result.requested, 2);
      // Not left waiting to be retried forever.
      expect(app.pendingFollowIds, isEmpty);
    });
  });

  group('Make Home yours (K1) eligibility', () {
    test(
      'after looking around: at most three sessions, gone after two Not nows',
      () async {
        SharedPreferences.setMockInitialValues({
          OnboardingStore.recordKey: jsonEncode(
            const OnboardingRecord(
              status: OnboardingStatus.lookedAround,
            ).toJson(),
          ),
        });
        Future<OnboardingController> session() async =>
            OnboardingController(clock: () => kNow)..load();

        var app = await session();
        await app.load();
        expect(app.homeCardEligible, isTrue);
        await app.noteHomeCardShown();
        await app.declineHomeCard();
        expect(app.homeCardEligible, isFalse, reason: 'hidden this session');

        app = await session();
        await app.load();
        expect(app.homeCardEligible, isTrue);
        await app.noteHomeCardShown();
        await app.declineHomeCard();

        app = await session();
        await app.load();
        expect(app.homeCardEligible, isFalse, reason: 'two Not nows');
      },
    );

    test(
      'never for someone who finished, unless they skipped everything',
      () async {
        final app = OnboardingController(clock: () => kNow);
        await app.load();
        await app.complete();
        expect(app.homeCardEligible, isFalse);
        await app.noteSetupSkipped();
        expect(app.homeCardEligible, isTrue);
        await app.finishHomeCard();
        expect(app.homeCardEligible, isFalse);
      },
    );
  });
}
