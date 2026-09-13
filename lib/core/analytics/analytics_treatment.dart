/// Treatment assignment for the one experiment the go/no-go decision rests on.
///
/// Roadmap §9: for the same underlying markets, compare
///
/// * **people-first** — "Ada called YES at 38% — Back or Fade?"
/// * **market-first** — "Trending: YES is 38%."
///
/// The comparison is only worth anything if the arm is (a) stable for a person
/// across sessions and devices, (b) roughly balanced across people, and (c)
/// stamped on every event so the two arms can actually be separated after the
/// fact. This file does all three, and does them **without storage**: the arm
/// is a pure function of the unit id, so there is nothing to persist, nothing
/// to migrate, and nothing that can drift between the phone and the BFF if the
/// same function is ported there.
library;

/// Which card framing a person sees.
enum FeedTreatment {
  /// The person is the subject: "Ada called YES at 38% — Back or Fade?"
  peopleFirst('people_first'),

  /// The market is the subject: "Trending: YES is 38%."
  marketFirst('market_first'),

  /// No unit id yet (cold start before a session or an anonymous id exists).
  /// Recorded honestly rather than defaulting into an arm and poisoning it.
  unassigned('unassigned');

  const FeedTreatment(this.wire);
  final String wire;

  bool get isAssigned => this != FeedTreatment.unassigned;
}

/// A person's arm, plus the experiment it belongs to.
class TreatmentAssignment {
  /// Experiment key, versioned. Changing the key reshuffles everybody, which
  /// is exactly what you want when the experiment itself changes.
  final String experiment;

  final FeedTreatment treatment;

  const TreatmentAssignment({
    required this.experiment,
    required this.treatment,
  });

  static const TreatmentAssignment none = TreatmentAssignment(
    experiment: TreatmentAssigner.experimentKey,
    treatment: FeedTreatment.unassigned,
  );

  @override
  String toString() => 'TreatmentAssignment($experiment, ${treatment.wire})';
}

/// Deterministic 50/50 assignment by hashing the unit id.
///
/// The **unit** is the canonical `public.users.id` for a signed-in person
/// (contract §0.3 — identity is never a wallet), or a per-install anonymous id
/// for somebody who has not signed in. Either way only the resulting
/// [FeedTreatment] is ever recorded; the unit id is never put into a payload by
/// this class.
abstract final class TreatmentAssigner {
  /// Versioned so a later change to the card design starts a clean experiment.
  static const String experimentKey = 'feed_card_framing_v1';

  /// Number of buckets. 100 makes a future 10/90 ramp a one-line change.
  static const int buckets = 100;

  /// Bucket below this are people-first. 50 is the even split §9 asks for.
  static const int peopleFirstCutoff = 50;

  /// FNV-1a, 32-bit. Chosen because it is tiny, dependency-free, well spread
  /// over short ASCII strings, and — the part that matters — identical in any
  /// language, so the BFF can reproduce an arm from the same id without this
  /// file being the only source of truth.
  static int hashUnit(String unitId) {
    const int prime = 0x01000193;
    int hash = 0x811c9dc5;
    final input = '$experimentKey:$unitId';
    for (final unit in input.codeUnits) {
      hash ^= unit & 0xff;
      hash = (hash * prime) & 0xffffffff;
    }
    return hash;
  }

  /// 0..[buckets]-1, stable for the life of [experimentKey].
  static int bucketOf(String unitId) => hashUnit(unitId) % buckets;

  /// The arm for [unitId]. Null or empty means "not yet known", which is
  /// [FeedTreatment.unassigned] rather than a silent default.
  static FeedTreatment treatmentFor(String? unitId) {
    if (unitId == null || unitId.isEmpty) return FeedTreatment.unassigned;
    return bucketOf(unitId) < peopleFirstCutoff
        ? FeedTreatment.peopleFirst
        : FeedTreatment.marketFirst;
  }

  static TreatmentAssignment assign(String? unitId) => TreatmentAssignment(
    experiment: experimentKey,
    treatment: treatmentFor(unitId),
  );
}
