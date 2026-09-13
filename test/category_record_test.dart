/// The category record: what it counts, what it refuses to count, and the one
/// boundary that decides whether a percentage is shown at all.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/record/data/category_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'packet_g_fixtures.dart';

RecordTally tallyFor(CategoryRecord record, CallOutcome outcome) =>
    record.tallies.firstWhere((t) => t.outcome == outcome);

void main() {
  group('the accuracy threshold', () {
    test('is 10 decided calls, and that is the documented boundary', () {
      expect(kMinimumDecidedCallsForAccuracy, 10);
    });

    test('9 decided calls show counts and NO percentage', () {
      final record = PersonRecord.fromEntries([
        ...testEntries(count: 6, outcome: CallOutcome.correct),
        ...testEntries(count: 3, outcome: CallOutcome.incorrect),
      ]).overall;

      expect(record.decided, 9);
      expect(record.isAccuracyHonest, isFalse);
      expect(record.accuracy, isNull);
      expect(record.decidedCallsUntilAccuracy, 1);
      // The counts are still there — withholding the percentage is not the
      // same as withholding the record.
      expect(tallyFor(record, CallOutcome.correct).count, 6);
      expect(tallyFor(record, CallOutcome.incorrect).count, 3);
    });

    test('10 decided calls is exactly where the percentage starts', () {
      final record = PersonRecord.fromEntries([
        ...testEntries(count: 6, outcome: CallOutcome.correct),
        ...testEntries(count: 4, outcome: CallOutcome.incorrect),
      ]).overall;

      expect(record.decided, 10);
      expect(record.isAccuracyHonest, isTrue);
      expect(record.accuracy, closeTo(0.6, 1e-9));
      expect(record.decidedCallsUntilAccuracy, 0);
    });

    test('one decided call is never a 100% record', () {
      final record =
          PersonRecord.fromEntries([
            testEntry(id: 'c1', outcome: CallOutcome.correct),
          ]).overall;

      expect(record.accuracy, isNull);
      expect(record.decidedCallsUntilAccuracy, 9);
    });

    test('an empty record is null accuracy, never 0%', () {
      final record = PersonRecord.fromEntries(const []).overall;
      expect(record.accuracy, isNull);
      expect(record.resolved, 0);
      expect(record.isEmpty, isTrue);
    });
  });

  group('VOID is neither a win nor a loss', () {
    test('void is counted, but never in the numerator or the denominator', () {
      final record = PersonRecord.fromEntries([
        ...testEntries(count: 6, outcome: CallOutcome.correct),
        ...testEntries(count: 4, outcome: CallOutcome.incorrect),
        ...testEntries(count: 5, outcome: CallOutcome.voided),
      ]).overall;

      expect(tallyFor(record, CallOutcome.voided).count, 5);
      expect(record.resolved, 15);
      expect(record.decided, 10);
      // 6/10, not 6/15 and not 11/15.
      expect(record.accuracy, closeTo(0.6, 1e-9));
    });

    test('void alone never unlocks a percentage', () {
      final record = PersonRecord.fromEntries(
        testEntries(count: 40, outcome: CallOutcome.voided),
      ).overall;

      expect(record.resolved, 40);
      expect(record.decided, 0);
      expect(record.accuracy, isNull);
    });
  });

  group('the record must include misses', () {
    test('tallies always carry all three outcomes, in a fixed order', () {
      final record = PersonRecord.fromEntries(
        testEntries(count: 12, outcome: CallOutcome.correct),
      ).overall;

      expect(
        record.tallies.map((t) => t.outcome).toList(),
        [CallOutcome.correct, CallOutcome.incorrect, CallOutcome.voided],
      );
      // A flawless record still renders the zero it earned.
      expect(tallyFor(record, CallOutcome.incorrect).count, 0);
    });

    test('a record with only misses is still a record', () {
      final record = PersonRecord.fromEntries(
        testEntries(count: 11, outcome: CallOutcome.incorrect),
      ).overall;

      expect(record.accuracy, closeTo(0, 1e-9));
      expect(tallyFor(record, CallOutcome.incorrect).count, 11);
    });
  });

  group('pending is not part of the record', () {
    test('pending calls are counted apart from settled ones', () {
      final record = PersonRecord.fromEntries([
        ...testEntries(count: 6, outcome: CallOutcome.correct),
        ...testEntries(count: 4, outcome: CallOutcome.incorrect),
        ...testEntries(count: 7, outcome: CallOutcome.pending),
      ]).overall;

      expect(record.pending, 7);
      expect(record.resolved, 10);
      expect(record.totalFreeCalls, 17);
      expect(record.accuracy, closeTo(0.6, 1e-9));
    });
  });

  group('free accuracy is strictly separate from funded performance', () {
    test('a funded call cannot move the percentage', () {
      final free = [
        ...testEntries(count: 6, outcome: CallOutcome.correct),
        ...testEntries(count: 4, outcome: CallOutcome.incorrect),
      ];
      final baseline = PersonRecord.fromEntries(free).overall;

      final withFunded = PersonRecord.fromEntries([
        ...free,
        ...testEntries(
          count: 9,
          outcome: CallOutcome.correct,
          funding: FundingState.filled,
          prefix: 'funded',
        ),
      ]).overall;

      expect(withFunded.accuracy, baseline.accuracy);
      expect(withFunded.decided, baseline.decided);
      expect(
        tallyFor(withFunded, CallOutcome.correct).count,
        tallyFor(baseline, CallOutcome.correct).count,
      );
      expect(withFunded.nonFreeCalls, 9);
      expect(withFunded.fundedCalls, 9);
    });

    test(
      'only FILLED counts as funded; a submitted call is neither free nor funded',
      () {
        final record = PersonRecord.fromEntries([
          ...testEntries(count: 10, outcome: CallOutcome.correct),
          testEntry(
            id: 'submitted_1',
            outcome: CallOutcome.correct,
            funding: FundingState.submitted,
          ),
          testEntry(
            id: 'filled_1',
            outcome: CallOutcome.correct,
            funding: FundingState.filled,
          ),
        ]).overall;

        expect(record.nonFreeCalls, 2);
        // SUBMITTED is not money in (contract §3) so it is not funded either.
        expect(record.fundedCalls, 1);
        expect(record.decided, 10);
      },
    );

    test('a funded-only history has no accuracy at all', () {
      final record = PersonRecord.fromEntries(
        testEntries(
          count: 30,
          outcome: CallOutcome.correct,
          funding: FundingState.filled,
        ),
      ).overall;

      expect(record.accuracy, isNull);
      expect(record.decided, 0);
      expect(record.nonFreeCalls, 30);
    });
  });

  group('per category', () {
    test('each category gets its own record and its own threshold', () {
      final record = PersonRecord.fromEntries([
        ...testEntries(
          count: 7,
          outcome: CallOutcome.correct,
          category: 'crypto',
          marketId: 'm_crypto',
        ),
        ...testEntries(
          count: 5,
          outcome: CallOutcome.incorrect,
          category: 'crypto',
          marketId: 'm_crypto',
          prefix: 'x',
        ),
        ...testEntries(
          count: 2,
          outcome: CallOutcome.correct,
          category: 'macro',
          marketId: 'm_macro',
          prefix: 'y',
        ),
      ]);

      final crypto = record.categories.firstWhere(
        (c) => c.category == 'crypto',
      );
      final macro = record.categories.firstWhere((c) => c.category == 'macro');

      expect(crypto.decided, 12);
      expect(crypto.accuracy, closeTo(7 / 12, 1e-9));
      // The small category stays honest even while the big one shows a number.
      expect(macro.decided, 2);
      expect(macro.accuracy, isNull);

      // Overall is the sum, and it clears the bar.
      expect(record.overall.decided, 14);
      expect(record.overall.accuracy, closeTo(9 / 14, 1e-9));
    });

    test('categories are ordered by settled count, then name', () {
      final record = PersonRecord.fromEntries([
        ...testEntries(
          count: 2,
          outcome: CallOutcome.correct,
          category: 'alpha',
          marketId: 'm_a',
          prefix: 'a',
        ),
        ...testEntries(
          count: 5,
          outcome: CallOutcome.correct,
          category: 'zeta',
          marketId: 'm_z',
          prefix: 'z',
        ),
      ]);

      expect(
        record.categories.map((c) => c.category).toList(),
        ['zeta', 'alpha'],
      );
    });

    test('the overall row is labelled, not left as a sentinel', () {
      final record = PersonRecord.fromEntries(
        testEntries(count: 1, outcome: CallOutcome.correct),
      );
      expect(record.overall.category, kOverallCategory);
      expect(record.overall.label, 'All categories');
      expect(record.categories.single.label, 'Crypto');
    });
  });

  test('a funded call can never be counted as free', () {
    expect(
      () => CategoryRecord(
        category: 'crypto',
        correct: 1,
        incorrect: 0,
        voided: 0,
        nonFreeCalls: 1,
        fundedCalls: 2,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
