/// The call sites this packet owns: `CallsProvider` and the receipt sheet.
///
/// A typed constructor that nothing calls measures nothing, so these tests
/// drive the real provider and the real sheet against the real mock repository
/// and assert on what actually reached the sink — including the standing rule
/// that **no payload anywhere contains a wallet, a signature, a balance or a
/// thesis**.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

/// The thesis on the seeded calls, so the "never in a payload" assertion has
/// real text to look for rather than a placeholder.
Future<List<String>> seededTheses(MockCallsRepository repo) async {
  final page = await repo.fetchFeed(mode: CallFeedMode.global, viewerUserId: viewer);
  return page.entries
      .map((e) => e.call.thesis)
      .whereType<String>()
      .toList(growable: false);
}

/// Asserts the standing privacy rule over everything a sink has seen.
void expectNothingSensitive(
  InMemoryAnalyticsSink sink, {
  List<String> theses = const [],
}) {
  expect(sink.length, greaterThan(0), reason: 'nothing was recorded at all');
  for (final event in sink.events) {
    expect(
      AnalyticsPrivacyGuard.inspect(event.props),
      isEmpty,
      reason: '${event.name.wire} would be rejected by the guard',
    );
    for (final entry in event.props.entries) {
      final value = entry.value;
      if (value is! String) continue;
      for (final thesis in theses) {
        expect(
          value,
          isNot(contains(thesis.substring(0, 20))),
          reason: '${event.name.wire}.${entry.key} leaked thesis text',
        );
      }
    }
  }
}

Widget host(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
);

/// The receipt sheet sizes itself from `MediaQuery` and scales through
/// `flutter_screenutil`. The default 800x600 test surface makes the two action
/// buttons overflow a row that is fine on a real 390x844 phone, so the surface
/// is pinned to the design size — the same one `main.dart:129` declares.
void useDesignSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late MockCallsRepository repo;
  late InMemoryAnalyticsSink sink;
  late AnalyticsRecorder recorder;
  late CallsProvider provider;

  /// Controlled so "a second open, later" is a fact about time rather than a
  /// race with the millisecond clock.
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    now = DateTime.utc(2026, 9, 13, 12);
    repo = MockCallsRepository(clock: clock);
    sink = InMemoryAnalyticsSink();
    recorder = AnalyticsRecorder(sink: sink);
    provider = CallsProvider(
      repository: repo,
      clock: clock,
      analytics: recorder,
    )..setViewer(viewer);
  });

  tearDown(() => provider.dispose());

  group('session', () {
    test('setViewer binds the experiment unit to the canonical user id', () {
      expect(provider.analytics.treatment.isAssigned, isTrue);
      expect(
        provider.analytics.assignment.experiment,
        TreatmentAssigner.experimentKey,
      );
      // Deterministic: the arm for this id is a pure function of it.
      expect(
        provider.analytics.treatment,
        TreatmentAssigner.treatmentFor(viewer),
      );
    });

    test('a signed-out provider records the unassigned arm, not a default', () {
      final anonSink = InMemoryAnalyticsSink();
      final anon = CallsProvider(
        repository: MockCallsRepository(),
        analytics: AnalyticsRecorder(sink: anonSink),
      );
      addTearDown(anon.dispose);
      expect(anon.analytics.treatment, FeedTreatment.unassigned);
    });

    test('the viewer id itself is never put in a payload', () async {
      await provider.loadCall('call_ada_btc');
      for (final event in sink.events) {
        expect(event.props.values, isNot(contains(viewer)));
      }
    });
  });

  group('call_opened', () {
    test('fires when a call is loaded, with the surface', () async {
      await provider.loadCall(
        'call_ada_btc',
        surface: AnalyticsSurface.feedGlobal,
      );
      final event = sink.lastOf(AnalyticsEventName.callOpened);
      expect(event, isNotNull);
      expect(event![AnalyticsProps.callId], 'call_ada_btc');
      expect(event[AnalyticsProps.surface], 'feed_global');
      expect(event[AnalyticsProps.viewerIsSignedIn], isTrue);
    });

    test('re-opening a cached call still counts as an open', () async {
      await provider.loadCall('call_ada_btc');
      now = now.add(const Duration(minutes: 20));
      await provider.loadCall('call_ada_btc');
      expect(
        sink.countOf(AnalyticsEventName.callOpened),
        2,
        reason: 'a return visit is the behaviour §9 is measuring',
      );
    });

    test('a deep-link open is distinguishable from a feed open', () async {
      await provider.loadCall(
        'call_ada_btc',
        surface: AnalyticsSurface.deepLink,
      );
      expect(
        sink.lastOf(AnalyticsEventName.callOpened)![AnalyticsProps.surface],
        'deep_link',
      );
    });

    test('a pre-warm can opt out of reporting an open', () async {
      await provider.loadCall('call_ada_btc', reportOpen: false);
      expect(sink.countOf(AnalyticsEventName.callOpened), 0);
    });
  });

  group('call_created', () {
    test('fires when a free call is locked, with the composer dimensions', () async {
      final entry = await provider.createCall(
        const CreateCallInput(
          marketId: 'market_btc_150k',
          side: Side.no,
          confidence: 0.7,
          thesis: 'Issuance outruns the flows before December.',
        ),
        surface: AnalyticsSurface.marketDetail,
      );

      final event = sink.lastOf(AnalyticsEventName.callCreated);
      expect(event, isNotNull);
      expect(event![AnalyticsProps.callId], entry.call.id);
      expect(event[AnalyticsProps.marketId], 'market_btc_150k');
      expect(event[AnalyticsProps.side], 'NO');
      expect(event[AnalyticsProps.visibility], 'public');
      expect(event[AnalyticsProps.fromResponse], isFalse);
      expect(event[AnalyticsProps.confidencePresent], isTrue);
      expect(event[AnalyticsProps.surface], 'market_detail');
    });

    test('records the thesis as presence and bucket, never as text', () async {
      const thesis =
          'Issuance outruns the flows before December and the skew agrees.';
      await provider.createCall(
        const CreateCallInput(
          marketId: 'market_btc_150k',
          side: Side.no,
          thesis: thesis,
        ),
      );
      final event = sink.lastOf(AnalyticsEventName.callCreated)!;
      expect(event[AnalyticsProps.thesisPresent], isTrue);
      expect(event[AnalyticsProps.thesisLengthBucket], 'short');
      expect(event.props.containsKey('thesis'), isFalse);
      expect(event.props.values, isNot(contains(thesis)));
    });

    test('an absent thesis is recorded honestly', () async {
      await provider.createCall(
        const CreateCallInput(marketId: 'market_btc_150k', side: Side.yes),
      );
      final event = sink.lastOf(AnalyticsEventName.callCreated)!;
      expect(event[AnalyticsProps.thesisPresent], isFalse);
      expect(event[AnalyticsProps.thesisLengthBucket], 'none');
      expect(event[AnalyticsProps.confidencePresent], isFalse);
    });
  });

  group('call_backed, call_faded, challenge_sent', () {
    test('Back records the response and the actor\'s own call', () async {
      final result = await provider.respondToCall(
        const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.back,
        ),
        surface: AnalyticsSurface.feedGlobal,
      );

      final backed = sink.lastOf(AnalyticsEventName.callBacked);
      expect(backed, isNotNull);
      expect(backed![AnalyticsProps.responseId], result.response.id);
      expect(backed[AnalyticsProps.targetCallId], 'call_ada_btc');
      expect(backed[AnalyticsProps.callId], result.resultingCall!.call.id);
      expect(backed[AnalyticsProps.surface], 'feed_global');

      // The §9 ratio: the resulting call must also be a counted call_created
      // that knows it came from a response.
      final created = sink.lastOf(AnalyticsEventName.callCreated)!;
      expect(created[AnalyticsProps.callId], result.resultingCall!.call.id);
      expect(created[AnalyticsProps.fromResponse], isTrue);
      expect(created[AnalyticsProps.responseKind], 'back');
      expect(created[AnalyticsProps.parentCallId], 'call_ada_btc');
    });

    test('Fade records the opposite side', () async {
      final result = await provider.respondToCall(
        const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.fade,
        ),
      );
      final faded = sink.lastOf(AnalyticsEventName.callFaded)!;
      expect(faded[AnalyticsProps.responseId], result.response.id);
      expect(faded[AnalyticsProps.side], result.resultingCall!.call.side.wire);
      expect(sink.countOf(AnalyticsEventName.callBacked), 0);

      final created = sink.lastOf(AnalyticsEventName.callCreated)!;
      expect(created[AnalyticsProps.responseKind], 'fade');
    });

    test('Challenge records no resulting call and nothing money-shaped', () async {
      final result = await provider.respondToCall(
        const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.challenge,
        ),
      );
      final sent = sink.lastOf(AnalyticsEventName.challengeSent)!;
      expect(sent[AnalyticsProps.responseId], result.response.id);
      expect(sent[AnalyticsProps.targetCallId], 'call_ada_btc');
      expect(sent.props.containsKey(AnalyticsProps.callId), isFalse);
      expect(sink.countOf(AnalyticsEventName.callCreated), 0);
      // A challenge has no escrow, so there is no amount to omit — but assert
      // it anyway, because "there is no field for it" is the guarantee.
      expect(AnalyticsPrivacyGuard.inspect(sent.props), isEmpty);
    });

    test('a rejected response records nothing', () async {
      // Responding to your own call is refused by the repository.
      await expectLater(
        provider.respondToCall(
          const RespondToCallInput(
            targetCallId: 'call_you_fed',
            kind: CallResponseKind.back,
          ),
        ),
        throwsA(isA<CallsException>()),
      );
      expect(sink.countOf(AnalyticsEventName.callBacked), 0);
      expect(sink.countOf(AnalyticsEventName.callCreated), 0);
    });
  });

  group('receipt_viewed, share_started, receipt_shared', () {
    Future<CallReceipt> receiptFor(String callId) async {
      final detail = await repo.fetchCall(callId: callId, viewerUserId: viewer);
      return CallReceipt.fromEntry(
        detail.entry,
        shareUrl: repo.shareLinkForCall(callId),
      );
    }

    testWidgets('opening the sheet records exactly one receipt_viewed', (
      tester,
    ) async {
      useDesignSurface(tester);
      final receipt = await receiptFor('call_you_fed');
      await tester.pumpWidget(
        host(
          CallReceiptSheet(
            receipt: receipt,
            surface: AnalyticsSurface.personProfile,
            analytics: recorder,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sink.countOf(AnalyticsEventName.receiptViewed), 1);
      final event = sink.lastOf(AnalyticsEventName.receiptViewed)!;
      expect(event[AnalyticsProps.callId], 'call_you_fed');
      expect(event[AnalyticsProps.settled], isTrue);
      expect(event[AnalyticsProps.outcome], 'CORRECT');
      expect(event[AnalyticsProps.surface], 'person_profile');
      // The market question and the share URL are on the receipt object and
      // must not be on the event.
      expect(event.props.values, isNot(contains(receipt.marketQuestion)));
      expect(event.props.values, isNot(contains(receipt.shareUrl)));
    });

    testWidgets('a rebuild does not re-fire receipt_viewed', (tester) async {
      useDesignSurface(tester);
      final receipt = await receiptFor('call_you_fed');
      await tester.pumpWidget(
        host(CallReceiptSheet(receipt: receipt, analytics: recorder)),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(sink.countOf(AnalyticsEventName.receiptViewed), 1);
    });

    testWidgets('an unsettled call records receipt_viewed with settled=false', (
      tester,
    ) async {
      useDesignSurface(tester);
      // The pending card is not a receipt, and pooling the two would inflate
      // the receipt metric.
      final receipt = await receiptFor('call_ada_btc');
      expect(receipt.isSettled, isFalse);
      await tester.pumpWidget(
        host(CallReceiptSheet(receipt: receipt, analytics: recorder)),
      );
      await tester.pumpAndSettle();
      expect(
        sink.lastOf(AnalyticsEventName.receiptViewed)![AnalyticsProps.settled],
        isFalse,
      );
    });

    testWidgets('tapping share records share_started for that channel', (
      tester,
    ) async {
      useDesignSurface(tester);
      final receipt = await receiptFor('call_you_fed');
      final entry =
          (await repo.fetchCall(
            callId: receipt.callId,
            viewerUserId: viewer,
          )).entry;
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      var platformAttempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (_) async {
            platformAttempts++;
            throw PlatformException(code: 'share_failed');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, null),
      );
      await tester.pumpWidget(
        host(
          CallReceiptSheet(receipt: receipt, entry: entry, analytics: recorder),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Share link'));
      await tester.tap(find.text('Share link'));
      await tester.pump();

      final started = sink.lastOf(AnalyticsEventName.shareStarted);
      expect(started, isNotNull);
      expect(started![AnalyticsProps.callId], 'call_you_fed');
      expect(started[AnalyticsProps.channel], 'link');
      expect(started[AnalyticsProps.linkKind], 'receipt');
      expect(started[AnalyticsProps.outcome], 'CORRECT');
      expect(started.props.values, isNot(contains(receipt.shareUrl)));

      // A real platform failure must leave a start with no completion, and
      // release the busy state so the person can try again.
      await tester.pumpAndSettle();
      expect(platformAttempts, 1);
      expect(sink.countOf(AnalyticsEventName.receiptShared), 0);
      expect(
        find.text('The link could not be shared. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Share link'), findsOneWidget);
    });
  });

  group('the standing rule: nothing sensitive, ever', () {
    test('across a full free-loop session', () async {
      final theses = await seededTheses(repo);
      expect(theses, isNotEmpty, reason: 'the seed should contain theses');

      await provider.loadFeed();
      await provider.loadCall(
        'call_ada_btc',
        surface: AnalyticsSurface.feedGlobal,
      );
      await provider.respondToCall(
        const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.fade,
          thesis: 'The flows are already priced in and the skew flipped.',
        ),
      );
      await provider.createCall(
        const CreateCallInput(
          marketId: 'market_sol_flip',
          side: Side.yes,
          confidence: 0.55,
          thesis: 'Validator revenue is the only number that matters here.',
        ),
      );
      await provider.respondToCall(
        const RespondToCallInput(
          targetCallId: 'call_tobi_btc',
          kind: CallResponseKind.challenge,
        ),
      );

      expect(recorder.rejectedCount, 0, reason: '${recorder.rejections}');
      expectNothingSensitive(sink, theses: theses);

      // And specifically: no wallet, no signature, no balance, no stake.
      for (final event in sink.events) {
        for (final key in event.props.keys) {
          final words = AnalyticsPrivacyGuard.keyWords(key).toSet();
          expect(
            words.intersection({
              'wallet',
              'address',
              'signature',
              'balance',
              'stake',
              'amount',
              'token',
              'email',
            }),
            isEmpty,
            reason: '${event.name.wire} carries "$key"',
          );
        }
      }
    });

    test('a person\'s handle and display name never reach a payload', () async {
      final person = await repo.fetchPerson(
        personRef: 'user_ada',
        viewerUserId: viewer,
      );
      await provider.loadFeed();
      await provider.loadCall('call_ada_btc');
      for (final event in sink.events) {
        expect(event.props.values, isNot(contains(person.person.handle)));
        expect(event.props.values, isNot(contains(person.person.displayName)));
      }
    });
  });
}
