/// Treatment assignment for the §9 people-first vs market-first experiment.
///
/// Two properties decide whether the experiment can be read at all:
///
/// * **stable** — a person stays in one arm, across sessions, restarts and
///   devices. If they drift, every per-person metric mixes the arms.
/// * **balanced** — roughly half the cohort in each arm. §9 plans for twenty
///   users; a 70/30 split would leave six people in one arm.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chumbucket/core/analytics/analytics.dart';

void main() {
  group('stability', () {
    test('the same unit id always lands in the same arm', () {
      for (final unit in [
        'user_ada',
        'user_kemi',
        'user_you',
        '550e8400-e29b-41d4-a716-446655440000',
      ]) {
        final first = TreatmentAssigner.treatmentFor(unit);
        for (var i = 0; i < 100; i++) {
          expect(TreatmentAssigner.treatmentFor(unit), first);
        }
      }
    });

    test('assignment needs no storage, so a reinstall cannot reshuffle it', () {
      // A fresh assigner is just the pure function again — there is no state
      // for a reinstall or a cache clear to lose.
      final before = TreatmentAssigner.assign('user_ada');
      final after = TreatmentAssigner.assign('user_ada');
      expect(after.treatment, before.treatment);
      expect(after.experiment, TreatmentAssigner.experimentKey);
    });

    test('a recorder keeps the arm it was given for the whole session', () {
      final sink = InMemoryAnalyticsSink();
      final recorder = AnalyticsRecorder(sink: sink);
      recorder.setUnit('user_ada');
      final arm = recorder.treatment;

      for (var i = 0; i < 20; i++) {
        recorder.record(
          AnalyticsEvents.feedCallImpression(
            callId: 'call_$i',
            marketId: 'market_btc_150k',
            authorId: 'user_kemi',
            surface: AnalyticsSurface.feedGlobal,
            position: i,
          ),
        );
      }
      expect(recorder.treatment, arm);
      expect(
        sink.events.map((e) => e[AnalyticsProps.treatment]).toSet(),
        {arm.wire},
      );
    });

    test('different people can land in different arms', () {
      final arms = <FeedTreatment>{};
      for (var i = 0; i < 200; i++) {
        arms.add(TreatmentAssigner.treatmentFor('user_$i'));
      }
      expect(arms, containsAll([
        FeedTreatment.peopleFirst,
        FeedTreatment.marketFirst,
      ]));
    });
  });

  group('balance', () {
    test('is close to 50/50 over uuid-shaped ids', () {
      // UUID v4-shaped ids, which is what `public.users.id` actually is.
      var peopleFirst = 0;
      const total = 4000;
      for (var i = 0; i < total; i++) {
        final unit =
            '550e8400-e29b-41d4-a716-${i.toString().padLeft(12, '0')}';
        if (TreatmentAssigner.treatmentFor(unit) == FeedTreatment.peopleFirst) {
          peopleFirst++;
        }
      }
      final share = peopleFirst / total;
      expect(
        share,
        inInclusiveRange(0.45, 0.55),
        reason: 'people-first share was $share over $total units',
      );
    });

    test('is close to 50/50 over slug-shaped ids too', () {
      var peopleFirst = 0;
      const total = 4000;
      for (var i = 0; i < total; i++) {
        if (TreatmentAssigner.treatmentFor('user_$i') ==
            FeedTreatment.peopleFirst) {
          peopleFirst++;
        }
      }
      final share = peopleFirst / total;
      expect(
        share,
        inInclusiveRange(0.45, 0.55),
        reason: 'people-first share was $share over $total units',
      );
    });

    test('buckets spread across the whole 0..99 range', () {
      final buckets = <int>{};
      for (var i = 0; i < 2000; i++) {
        buckets.add(TreatmentAssigner.bucketOf('user_$i'));
      }
      // A degenerate hash would collapse into a handful of buckets.
      expect(buckets.length, greaterThan(90));
      expect(buckets.every((b) => b >= 0 && b < TreatmentAssigner.buckets),
          isTrue);
    });
  });

  group('honesty about not knowing', () {
    test('no unit id is unassigned, not a silent default arm', () {
      expect(TreatmentAssigner.treatmentFor(null), FeedTreatment.unassigned);
      expect(TreatmentAssigner.treatmentFor(''), FeedTreatment.unassigned);
      expect(FeedTreatment.unassigned.isAssigned, isFalse);
    });

    test('an event recorded before sign-in says so', () {
      final sink = InMemoryAnalyticsSink();
      final recorder = AnalyticsRecorder(sink: sink);
      recorder.record(
        AnalyticsEvents.callOpened(
          callId: 'call_ada_btc',
          surface: AnalyticsSurface.deepLink,
        ),
      );
      expect(sink.events.single[AnalyticsProps.treatment], 'unassigned');
    });
  });

  group('experiment key', () {
    test('is versioned so a redesign starts a clean experiment', () {
      expect(TreatmentAssigner.experimentKey, 'feed_card_framing_v1');
      expect(
        TreatmentAssignment.none.experiment,
        TreatmentAssigner.experimentKey,
      );
    });

    test('is stamped on every event', () {
      final sink = InMemoryAnalyticsSink();
      final recorder = AnalyticsRecorder(sink: sink)..setUnit('user_ada');
      recorder.record(
        AnalyticsEvents.followCreated(
          personId: 'user_kemi',
          surface: AnalyticsSurface.personProfile,
        ),
      );
      expect(
        sink.events.single[AnalyticsProps.experiment],
        'feed_card_framing_v1',
      );
    });
  });
}
