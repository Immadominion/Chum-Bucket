/// Every one of the roadmap's sixteen event names is reachable through a typed
/// constructor, emits under exactly that wire name, and survives the privacy
/// guard.
///
/// The last part is the important one: an event that a screen can build but the
/// recorder always drops is worse than no instrumentation, because it looks
/// instrumented.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chumbucket/core/analytics/analytics.dart';

import 'onboarding_analytics_fixtures.dart';

void main() {
  late InMemoryAnalyticsSink sink;
  late AnalyticsRecorder recorder;

  setUp(() {
    sink = InMemoryAnalyticsSink();
    recorder = AnalyticsRecorder(sink: sink);
    recorder.setUnit('user_ada');
  });

  /// One builder per roadmap name. The map is the test: if a name is added to
  /// [AnalyticsEventName] without a constructor, the completeness test below
  /// fails.
  Map<AnalyticsEventName, AnalyticsEvent> buildAll() => {
    AnalyticsEventName.feedCallImpression: AnalyticsEvents.feedCallImpression(
      callId: 'call_ada_btc',
      marketId: 'market_btc_150k',
      authorId: 'user_ada',
      surface: AnalyticsSurface.feedGlobal,
      position: 0,
      side: 'YES',
      outcome: 'PENDING',
      venue: 'jupiter',
      venueIsDemo: false,
      thesisPresent: true,
      thesisLengthBucket: ThesisLengthBucket.short,
      viewerIsSignedIn: true,
    ),
    AnalyticsEventName.callOpened: AnalyticsEvents.callOpened(
      callId: 'call_ada_btc',
      surface: AnalyticsSurface.feedGlobal,
      marketId: 'market_btc_150k',
      authorId: 'user_ada',
      side: 'YES',
      outcome: 'PENDING',
      viewerIsSignedIn: true,
    ),
    AnalyticsEventName.callCreated: AnalyticsEvents.callCreated(
      callId: 'call_you_fed',
      marketId: 'market_fed_cut',
      side: 'NO',
      visibility: 'public',
      fromResponse: false,
      confidencePresent: true,
      thesisPresent: false,
      thesisLengthBucket: ThesisLengthBucket.none,
      entryProbability: 0.38,
      surface: AnalyticsSurface.marketDetail,
    ),
    AnalyticsEventName.callBacked: AnalyticsEvents.callBacked(
      responseId: 'response_you_back',
      targetCallId: 'call_ada_btc',
      resultingCallId: 'call_you_btc',
      marketId: 'market_btc_150k',
      side: 'YES',
      surface: AnalyticsSurface.feedGlobal,
    ),
    AnalyticsEventName.callFaded: AnalyticsEvents.callFaded(
      responseId: 'response_kemi_fade',
      targetCallId: 'call_ada_btc',
      resultingCallId: 'call_kemi_btc_fade',
      marketId: 'market_btc_150k',
      side: 'NO',
      surface: AnalyticsSurface.callDetail,
    ),
    AnalyticsEventName.challengeSent: AnalyticsEvents.challengeSent(
      responseId: 'response_zed_challenge',
      targetCallId: 'call_you_fed',
      marketId: 'market_fed_cut',
      personId: 'user_zed',
      surface: AnalyticsSurface.personProfile,
    ),
    AnalyticsEventName.followCreated: AnalyticsEvents.followCreated(
      personId: 'user_ada',
      surface: AnalyticsSurface.personProfile,
      callId: 'call_ada_btc',
    ),
    AnalyticsEventName.shareStarted: AnalyticsEvents.shareStarted(
      linkKind: AnalyticsLinkKind.receipt,
      channel: AnalyticsShareChannel.image,
      callId: 'call_ada_btc',
      outcome: 'CORRECT',
      surface: AnalyticsSurface.receiptSheet,
    ),
    AnalyticsEventName.shareOpened: AnalyticsEvents.shareOpened(
      linkKind: AnalyticsLinkKind.call,
      hasReferrer: true,
      callId: 'call_ada_btc',
      viewerIsSignedIn: false,
    ),
    AnalyticsEventName.walletLinkStarted: AnalyticsEvents.walletLinkStarted(
      surface: AnalyticsSurface.callDetail,
      callId: 'call_ada_btc',
    ),
    AnalyticsEventName.walletLinkSucceeded: AnalyticsEvents.walletLinkSucceeded(
      surface: AnalyticsSurface.callDetail,
    ),
    AnalyticsEventName.fundQuoteViewed: AnalyticsEvents.fundQuoteViewed(
      callId: 'call_you_fed',
      marketId: 'market_fed_cut',
      side: 'NO',
    ),
    AnalyticsEventName.fundOrderSigned: AnalyticsEvents.fundOrderSigned(
      orderId: 'order_001',
      callId: 'call_you_fed',
      marketId: 'market_fed_cut',
      side: 'NO',
    ),
    AnalyticsEventName.fundOrderConfirmed: AnalyticsEvents.fundOrderConfirmed(
      orderId: 'order_001',
      callId: 'call_you_fed',
      fundingState: 'FILLED',
      marketId: 'market_fed_cut',
    ),
    AnalyticsEventName.receiptViewed: AnalyticsEvents.receiptViewed(
      callId: 'call_kemi_listing',
      settled: true,
      surface: AnalyticsSurface.receiptSheet,
      marketId: 'market_cancelled_listing',
      outcome: 'VOID',
      venue: 'fixture',
      venueIsDemo: true,
    ),
    AnalyticsEventName.receiptShared: AnalyticsEvents.receiptShared(
      callId: 'call_kemi_listing',
      channel: AnalyticsShareChannel.link,
      outcome: 'VOID',
      marketId: 'market_cancelled_listing',
    ),
    ...onboardingAnalyticsSamples(),
  };

  group('the roadmap vocabulary', () {
    test('has exactly the sixteen §9 names, the onboarding funnel, and '
        'nothing else', () {
      // Copied from CHUMBUCKET_CALL_RECEIPT_ROADMAP.md §9 "Minimum event
      // names". If this list and the enum ever disagree, one of them drifted.
      const roadmap = <String>{
        'feed_call_impression',
        'call_opened',
        'call_created',
        'call_backed',
        'call_faded',
        'challenge_sent',
        'follow_created',
        'share_started',
        'share_opened',
        'wallet_link_started',
        'wallet_link_succeeded',
        'fund_quote_viewed',
        'fund_order_signed',
        'fund_order_confirmed',
        'receipt_viewed',
        'receipt_shared',
      };
      expect(AnalyticsEventName.values.map((n) => n.wire).toSet(), {
        ...roadmap,
        ...kOnboardingEventWires,
      });
      expect(AnalyticsEventName.values, hasLength(16 + 16));
    });

    test('every name has a typed constructor', () {
      expect(buildAll().keys.toSet(), AnalyticsEventName.values.toSet());
    });

    test('an unknown wire name cannot be turned into an event', () {
      expect(
        () => AnalyticsEventName.fromWire('call_backd'),
        throwsArgumentError,
      );
    });
  });

  group('emission', () {
    test('every event reaches the sink under its own wire name', () {
      final built = buildAll();
      for (final entry in built.entries) {
        expect(
          recorder.record(entry.value),
          AnalyticsRecordOutcome.delivered,
          reason: '${entry.key.wire} was not delivered',
        );
      }

      expect(recorder.rejectedCount, 0, reason: '${recorder.rejections}');
      expect(sink.length, built.length);
      expect(
        sink.events.map((e) => e.name.wire).toSet(),
        built.keys.map((n) => n.wire).toSet(),
      );
    });

    test('every delivered event carries the experiment arm', () {
      for (final event in buildAll().values) {
        recorder.record(event);
      }
      for (final event in sink.events) {
        expect(event[AnalyticsProps.experiment], 'feed_card_framing_v1');
        expect(
          event[AnalyticsProps.treatment],
          anyOf('people_first', 'market_first'),
          reason: '${event.name.wire} lost its arm',
        );
      }
    });

    test('a null dimension is omitted, never sent as null', () {
      final event = AnalyticsEvents.callOpened(
        callId: 'call_ada_btc',
        surface: AnalyticsSurface.deepLink,
      );
      expect(event.props.containsKey(AnalyticsProps.marketId), isFalse);
      // A null cannot even be represented: props is Map<String, Object>,
      // non-nullable, so an omitted dimension is absent rather than null.
      expect(event.props, isA<Map<String, Object>>());
      expect(recorder.record(event), AnalyticsRecordOutcome.delivered);
    });

    test('props are unmodifiable once built', () {
      final event = AnalyticsEvents.followCreated(
        personId: 'user_ada',
        surface: AnalyticsSurface.feedGlobal,
      );
      expect(() => event.props['wallet'] = 'anything', throwsUnsupportedError);
    });
  });

  group('thesis length bucketing', () {
    test('reduces text to one of four buckets and keeps none of it', () {
      expect(ThesisLengthBucket.of(null), ThesisLengthBucket.none);
      expect(ThesisLengthBucket.of('   '), ThesisLengthBucket.none);
      expect(
        ThesisLengthBucket.of('ETF flows are front-running the halving.'),
        ThesisLengthBucket.short,
      );
      expect(ThesisLengthBucket.of('x' * 120), ThesisLengthBucket.medium);
      expect(ThesisLengthBucket.of('x' * 260), ThesisLengthBucket.long);
      // Over the contract's 280 limit: still buckets, never throws. Analytics
      // does not get to fail a flow.
      expect(ThesisLengthBucket.of('x' * 5000), ThesisLengthBucket.long);
    });
  });

  group('the in-memory sink', () {
    test('is bounded and drops the oldest first', () {
      final bounded = InMemoryAnalyticsSink(capacity: 3);
      final small = AnalyticsRecorder(sink: bounded);
      for (var i = 0; i < 10; i++) {
        small.record(
          AnalyticsEvents.feedCallImpression(
            callId: 'call_$i',
            marketId: 'market_btc_150k',
            authorId: 'user_ada',
            surface: AnalyticsSurface.feedGlobal,
            position: i,
          ),
        );
      }
      expect(bounded.length, 3);
      expect(bounded.events.first[AnalyticsProps.callId], 'call_7');
      expect(bounded.events.last[AnalyticsProps.callId], 'call_9');
    });
  });
}
