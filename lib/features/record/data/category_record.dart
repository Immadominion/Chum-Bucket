/// A person's track record, per category.
///
/// This file exists to make four product rules structurally impossible to
/// break, rather than merely documented:
///
/// 1. **Accuracy is only shown when it is statistically honest.** Below
///    [kMinimumDecidedCallsForAccuracy] decided calls, [CategoryRecord.accuracy]
///    is null and the UI has nothing to render but raw counts.
/// 2. **The record must include misses.** The counts are private and the only
///    way to read them is [CategoryRecord.tallies], which always returns all
///    three outcomes in a fixed order. There is no `wins` getter to render on
///    its own.
/// 3. **VOID is neither a win nor a loss.** It appears in [CategoryRecord.tallies]
///    and in [CategoryRecord.resolved], and it is excluded from both the
///    numerator and the denominator of accuracy.
/// 4. **Free-call accuracy is strictly separate from funded performance.**
///    Only calls whose `fundingState` is `NONE` feed the tallies at all;
///    anything else is counted separately in [CategoryRecord.nonFreeCalls] and
///    can never move the percentage.
///
/// There is no money field here and there must never be one — no stake, no
/// balance, no PnL. A widget cannot render an amount it was never handed.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';

/// The minimum number of **decided** calls — correct plus incorrect, with void
/// excluded — before a record shows a percentage at all.
///
/// Chosen as 10, for a reason that can be checked rather than argued:
///
/// * At `n` decided calls, one more call moves the headline percentage by
///   `1/n`. At `n = 10` that is 10 points. At `n = 9` a single call swings it
///   by more than 10 points, which makes the number noise wearing the costume
///   of a measurement.
/// * The 95% confidence interval agrees: at 6 correct out of 10 the Wilson
///   interval is roughly 31%–83%. That is already wide. At 3 of 5 it is
///   roughly 23%–88% — an interval so wide that quoting "60%" is closer to a
///   lie than to a summary.
///
/// So below 10 we show what actually happened — the raw correct / incorrect /
/// void counts — and say plainly how many more calls it takes before a
/// percentage means anything. Above it, the percentage is shown *alongside*
/// those same counts, never instead of them.
const int kMinimumDecidedCallsForAccuracy = 10;

/// The sentinel [CategoryRecord.category] for the all-categories row.
const String kOverallCategory = '__overall__';

/// One outcome and how many times it happened.
class RecordTally {
  final CallOutcome outcome;
  final int count;

  const RecordTally(this.outcome, this.count);

  @override
  bool operator ==(Object other) =>
      other is RecordTally && other.outcome == outcome && other.count == count;

  @override
  int get hashCode => Object.hash(outcome, count);

  @override
  String toString() => 'RecordTally(${outcome.wire}: $count)';
}

/// One category's settled record, built only from free calls.
class CategoryRecord {
  /// The venue market's own `category` string, or [kOverallCategory].
  final String category;

  // Private on purpose: see rule 2 in the library doc. The only public way to
  // read these is [tallies], which always hands back all three together.
  final int _correct;
  final int _incorrect;
  final int _voided;

  /// Free calls in this category the venue has not resolved yet. Not part of
  /// the record — a pending call is neither a hit nor a miss.
  final int pending;

  /// Calls in this category whose `fundingState` is **not** `NONE`.
  ///
  /// These never touch the tallies or the accuracy. They are surfaced only so
  /// the record can say out loud that it is not the whole story.
  final int nonFreeCalls;

  /// The subset of [nonFreeCalls] that actually reached `FILLED`.
  ///
  /// `FILLED` is the only state the word "funded" may appear for (contract §3),
  /// and the word itself is read from `FundingState.filled.label` so it cannot
  /// drift.
  final int fundedCalls;

  CategoryRecord({
    required this.category,
    required int correct,
    required int incorrect,
    required int voided,
    this.pending = 0,
    this.nonFreeCalls = 0,
    this.fundedCalls = 0,
  }) : _correct = correct,
       _incorrect = incorrect,
       _voided = voided,
       assert(correct >= 0 && incorrect >= 0 && voided >= 0),
       assert(pending >= 0 && nonFreeCalls >= 0),
       assert(
         fundedCalls <= nonFreeCalls,
         'A funded call is by definition not a free call.',
       );

  /// Every outcome that makes up this record, always all three, always in the
  /// same order: correct, incorrect, void.
  ///
  /// This is the record. A caller that renders a record renders this list, so
  /// there is no code path that shows the hits and quietly drops the misses.
  List<RecordTally> get tallies => [
    RecordTally(CallOutcome.correct, _correct),
    RecordTally(CallOutcome.incorrect, _incorrect),
    RecordTally(CallOutcome.voided, _voided),
  ];

  /// Everything the venue has settled: correct + incorrect + void.
  int get resolved => _correct + _incorrect + _voided;

  /// The calls that actually went one way or the other. Void is excluded,
  /// because a cancelled market decided nothing.
  int get decided => _correct + _incorrect;

  /// Free calls in this category, settled or not.
  int get totalFreeCalls => resolved + pending;

  /// True once a percentage would mean something. See
  /// [kMinimumDecidedCallsForAccuracy].
  bool get isAccuracyHonest => decided >= kMinimumDecidedCallsForAccuracy;

  /// `[0,1]`, or **null** when there is not enough decided history for a
  /// percentage to be honest — including when nothing has settled at all.
  /// Never render "0%" for "no data".
  double? get accuracy => isAccuracyHonest ? _correct / decided : null;

  /// How many more decided calls before [accuracy] starts being shown. Zero
  /// once it is. Lets the UI say something specific instead of staying mute.
  int get decidedCallsUntilAccuracy =>
      isAccuracyHonest ? 0 : kMinimumDecidedCallsForAccuracy - decided;

  bool get isEmpty => totalFreeCalls == 0 && nonFreeCalls == 0;

  /// Human label. The overall row is not a real category name.
  String get label =>
      category == kOverallCategory ? 'All categories' : _titleCase(category);

  CategoryRecord _plus(CategoryRecord other) => CategoryRecord(
    category: category,
    correct: _correct + other._correct,
    incorrect: _incorrect + other._incorrect,
    voided: _voided + other._voided,
    pending: pending + other.pending,
    nonFreeCalls: nonFreeCalls + other.nonFreeCalls,
    fundedCalls: fundedCalls + other.fundedCalls,
  );

  @override
  String toString() =>
      'CategoryRecord($category: ${_correct}C/${_incorrect}I/${_voided}V, '
      'pending $pending, nonFree $nonFreeCalls)';
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(RegExp(r'[\s_-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// A person's whole record: one row per category, plus the all-categories row.
class PersonRecord {
  /// Every category the person has a free call in, most-settled first, then
  /// alphabetical so the order is stable between loads.
  final List<CategoryRecord> categories;

  /// The same arithmetic across every category.
  final CategoryRecord overall;

  const PersonRecord({required this.categories, required this.overall});

  bool get isEmpty => overall.isEmpty;

  /// Build the record from whatever calls the person's page already loaded.
  ///
  /// Uses `CallFeedEntry.outcome`, which is derived by `deriveCallOutcome` —
  /// the only permitted derivation (contract §3). Nothing here decides an
  /// outcome; it only counts the ones the venue produced.
  factory PersonRecord.fromEntries(Iterable<CallFeedEntry> entries) {
    final byCategory = <String, _Bucket>{};

    for (final entry in entries) {
      final bucket = byCategory.putIfAbsent(
        entry.market.category,
        () => _Bucket(),
      );

      // Rule 4: only a free call can move the tallies. Everything else is
      // counted apart and can never reach the percentage.
      if (!entry.call.fundingState.isFree) {
        bucket.nonFree++;
        if (entry.call.fundingState.isFunded) bucket.funded++;
        continue;
      }

      switch (entry.outcome) {
        case CallOutcome.correct:
          bucket.correct++;
        case CallOutcome.incorrect:
          bucket.incorrect++;
        case CallOutcome.voided:
          bucket.voided++;
        case CallOutcome.pending:
          bucket.pending++;
      }
    }

    final categories =
        byCategory.entries
            .map((e) => e.value.toRecord(e.key))
            .toList(growable: false)
          ..sort((a, b) {
            final byResolved = b.resolved.compareTo(a.resolved);
            if (byResolved != 0) return byResolved;
            return a.category.compareTo(b.category);
          });

    var overall = CategoryRecord(
      category: kOverallCategory,
      correct: 0,
      incorrect: 0,
      voided: 0,
    );
    for (final record in categories) {
      overall = overall._plus(record);
    }

    return PersonRecord(categories: categories, overall: overall);
  }
}

class _Bucket {
  int correct = 0;
  int incorrect = 0;
  int voided = 0;
  int pending = 0;
  int nonFree = 0;
  int funded = 0;

  CategoryRecord toRecord(String category) => CategoryRecord(
    category: category,
    correct: correct,
    incorrect: incorrect,
    voided: voided,
    pending: pending,
    nonFreeCalls: nonFree,
    fundedCalls: funded,
  );
}
