/// Deduplication and retry-idempotency.
///
/// Packet I's acceptance says analytics events must be deduplicated. For the
/// experiment that is not hygiene, it is correctness: `feed_call_impression` is
/// the denominator of every §9 go signal, and a feed that rebuilds more often
/// in one arm than the other would silently move the result.
///
/// The widget half of this — rebuild and scroll-back — is in
/// `analytics_impression_widget_test.dart`.
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
    recorder.setUnit('user_you');
  });

  AnalyticsEvent impression(String callId, {int position = 0}) =>
      AnalyticsEvents.feedCallImpression(
        callId: callId,
        marketId: 'market_btc_150k',
        authorId: 'user_ada',
        surface: AnalyticsSurface.feedGlobal,
        position: position,
      );

  group('feed_call_impression', () {
    test('fires once per card per session however often it is reported', () {
      for (var i = 0; i < 50; i++) {
        recorder.record(impression('call_ada_btc'));
      }
      expect(sink.countOf(AnalyticsEventName.feedCallImpression), 1);
    });

    test('a changed position does not create a second impression', () {
      // The same card at a different index after a refresh is still the same
      // card. The dedupe key is (surface, callId) for exactly this reason.
      recorder.record(impression('call_ada_btc', position: 0));
      recorder.record(impression('call_ada_btc', position: 7));
      expect(sink.countOf(AnalyticsEventName.feedCallImpression), 1);
      expect(sink.events.single[AnalyticsProps.position], 0);
    });

    test('different cards each count once', () {
      for (final id in ['call_ada_btc', 'call_tobi_btc', 'call_zed_sol']) {
        recorder.record(impression(id));
        recorder.record(impression(id));
      }
      expect(sink.countOf(AnalyticsEventName.feedCallImpression), 3);
    });

    test('the same card on a different surface is a different impression', () {
      recorder.record(impression('call_ada_btc'));
      recorder.record(
        AnalyticsEvents.feedCallImpression(
          callId: 'call_ada_btc',
          marketId: 'market_btc_150k',
          authorId: 'user_ada',
          surface: AnalyticsSurface.personProfile,
          position: 0,
        ),
      );
      expect(sink.countOf(AnalyticsEventName.feedCallImpression), 2);
    });

    test('a viewer change resets the session so the next account counts', () {
      recorder.record(impression('call_ada_btc'));
      expect(sink.countOf(AnalyticsEventName.feedCallImpression), 1);

      // Second account, same card. Suppressing this would under-count the new
      // person's feed entirely.
      recorder.setUnit('user_kemi');
      recorder.record(impression('call_ada_btc'));
      expect(sink.countOf(AnalyticsEventName.feedCallImpression), 2);
    });

    test('isDuplicate answers without recording anything', () {
      final event = impression('call_ada_btc');
      expect(recorder.isDuplicate(event), isFalse);
      recorder.record(event);
      expect(recorder.isDuplicate(event), isTrue);
      expect(sink.length, 1);
    });
  });

  group('idempotency under retry', () {
    /// Re-recording the same event value is what a retry is. Every event must
    /// survive it without double counting.
    void expectIdempotent(AnalyticsEvent event) {
      final local = InMemoryAnalyticsSink();
      final rec = AnalyticsRecorder(sink: local)..setUnit('user_you');
      expect(rec.record(event), AnalyticsRecordOutcome.delivered);
      expect(rec.record(event), AnalyticsRecordOutcome.deduplicated);
      expect(rec.record(event), AnalyticsRecordOutcome.deduplicated);
      expect(local.length, 1, reason: '${event.name.wire} double counted');
    }

    test('every event name is idempotent when the same value is retried', () {
      const at = 1789000000000;
      final events = <AnalyticsEvent>[
        AnalyticsEvents.feedCallImpression(
          callId: 'call_ada_btc',
          marketId: 'market_btc_150k',
          authorId: 'user_ada',
          surface: AnalyticsSurface.feedGlobal,
          position: 1,
          occurredAtMs: at,
        ),
        AnalyticsEvents.callOpened(
          callId: 'call_ada_btc',
          surface: AnalyticsSurface.feedGlobal,
          occurredAtMs: at,
        ),
        AnalyticsEvents.callCreated(
          callId: 'call_you_btc',
          marketId: 'market_btc_150k',
          side: 'YES',
          visibility: 'public',
          fromResponse: true,
          responseKind: 'back',
          occurredAtMs: at,
        ),
        AnalyticsEvents.callBacked(
          responseId: 'response_you_back',
          targetCallId: 'call_ada_btc',
          occurredAtMs: at,
        ),
        AnalyticsEvents.callFaded(
          responseId: 'response_you_fade',
          targetCallId: 'call_ada_btc',
          occurredAtMs: at,
        ),
        AnalyticsEvents.challengeSent(
          responseId: 'response_zed_challenge',
          targetCallId: 'call_you_fed',
          occurredAtMs: at,
        ),
        AnalyticsEvents.followCreated(
          personId: 'user_ada',
          surface: AnalyticsSurface.personProfile,
          occurredAtMs: at,
        ),
        AnalyticsEvents.shareStarted(
          linkKind: AnalyticsLinkKind.call,
          channel: AnalyticsShareChannel.link,
          callId: 'call_ada_btc',
          occurredAtMs: at,
        ),
        AnalyticsEvents.shareOpened(
          linkKind: AnalyticsLinkKind.call,
          hasReferrer: false,
          callId: 'call_ada_btc',
          occurredAtMs: at,
        ),
        AnalyticsEvents.walletLinkStarted(
          surface: AnalyticsSurface.callDetail,
          occurredAtMs: at,
        ),
        AnalyticsEvents.walletLinkSucceeded(
          surface: AnalyticsSurface.callDetail,
          occurredAtMs: at,
        ),
        AnalyticsEvents.fundQuoteViewed(
          callId: 'call_you_fed',
          marketId: 'market_fed_cut',
          occurredAtMs: at,
        ),
        AnalyticsEvents.fundOrderSigned(
          orderId: 'order_001',
          callId: 'call_you_fed',
          occurredAtMs: at,
        ),
        AnalyticsEvents.fundOrderConfirmed(
          orderId: 'order_001',
          callId: 'call_you_fed',
          fundingState: 'FILLED',
          occurredAtMs: at,
        ),
        AnalyticsEvents.receiptViewed(
          callId: 'call_kemi_listing',
          settled: true,
          surface: AnalyticsSurface.receiptSheet,
          occurredAtMs: at,
        ),
        AnalyticsEvents.receiptShared(
          callId: 'call_kemi_listing',
          channel: AnalyticsShareChannel.image,
          occurredAtMs: at,
        ),
        ...onboardingAnalyticsSamples(at: at).values,
      ];

      expect(
        events.map((e) => e.name).toSet(),
        AnalyticsEventName.values.toSet(),
        reason: 'an event name is missing from the retry test',
      );
      for (final event in events) {
        expectIdempotent(event);
      }
    });

    test('a durable artefact is counted once even from two code paths', () {
      // A created call reported by both the composer and a refresh is one
      // call. The dedupe key is the call id — no timestamp.
      final first = AnalyticsEvents.callCreated(
        callId: 'call_you_btc',
        marketId: 'market_btc_150k',
        side: 'YES',
        visibility: 'public',
        fromResponse: false,
        occurredAtMs: 1789000000000,
      );
      final laterDuplicate = AnalyticsEvents.callCreated(
        callId: 'call_you_btc',
        marketId: 'market_btc_150k',
        side: 'YES',
        visibility: 'public',
        fromResponse: false,
        occurredAtMs: 1789000900000,
      );
      expect(recorder.record(first), AnalyticsRecordOutcome.delivered);
      expect(
        recorder.record(laterDuplicate),
        AnalyticsRecordOutcome.deduplicated,
      );
      expect(sink.countOf(AnalyticsEventName.callCreated), 1);
    });

    test('a genuine second occurrence of a view event still counts', () {
      // Opening the same call again later is a real, separate open — the §9
      // return-behaviour signal depends on it.
      expect(
        recorder.record(
          AnalyticsEvents.callOpened(
            callId: 'call_ada_btc',
            surface: AnalyticsSurface.feedGlobal,
            occurredAtMs: 1789000000000,
          ),
        ),
        AnalyticsRecordOutcome.delivered,
      );
      expect(
        recorder.record(
          AnalyticsEvents.callOpened(
            callId: 'call_ada_btc',
            surface: AnalyticsSurface.feedGlobal,
            occurredAtMs: 1789000900000,
          ),
        ),
        AnalyticsRecordOutcome.delivered,
      );
      expect(sink.countOf(AnalyticsEventName.callOpened), 2);
    });

    test('a partial fill and a full fill are both recorded', () {
      // fund_order_confirmed keys on (orderId, fundingState) so PARTIAL cannot
      // swallow the later FILLED, and FILLED cannot be reported twice.
      for (final state in ['PARTIAL', 'FILLED', 'FILLED']) {
        recorder.record(
          AnalyticsEvents.fundOrderConfirmed(
            orderId: 'order_001',
            callId: 'call_you_fed',
            fundingState: state,
          ),
        );
      }
      expect(sink.countOf(AnalyticsEventName.fundOrderConfirmed), 2);
    });
  });

  group('the dedupe store', () {
    test('is bounded', () {
      final bounded = AnalyticsRecorder(
        sink: InMemoryAnalyticsSink(capacity: 100000),
        dedupeCapacity: 10,
      );
      for (var i = 0; i < 50; i++) {
        bounded.record(impression('call_$i'));
      }
      // The most recent keys are still remembered; the oldest have aged out
      // rather than growing without bound.
      expect(bounded.isDuplicate(impression('call_49')), isTrue);
      expect(bounded.isDuplicate(impression('call_0')), isFalse);
    });

    test('resetSession forgets keys but keeps the sink', () {
      recorder.record(impression('call_ada_btc'));
      recorder.resetSession();
      recorder.record(impression('call_ada_btc'));
      expect(sink.countOf(AnalyticsEventName.feedCallImpression), 2);
    });
  });
}
