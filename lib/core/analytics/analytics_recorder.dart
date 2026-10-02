/// The only way an event reaches a sink.
///
/// Three jobs, in this order, none of them optional:
///
/// 1. **Stamp the arm.** Every event gets `experiment` and `treatment`, so the
///    people-first vs market-first comparison can be made from any event —
///    including the ones a call site forgot to think about.
/// 2. **Deduplicate.** [AnalyticsDedupePolicy.oncePerSession] events are
///    delivered once per dedupe key; everything is idempotent under a retry of
///    the same event value.
/// 3. **Guard.** [AnalyticsPrivacyGuard] inspects the final payload — the
///    stamped one, not the one the call site built — and a violating event is
///    dropped. It is counted, and its violations are kept for a test or a
///    developer to read, but it never reaches a sink.
///
/// Nothing here can throw into a caller. Analytics must never break a flow.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'package:chumbucket/core/analytics/analytics_consent.dart';
import 'package:chumbucket/core/analytics/analytics_event.dart';
import 'package:chumbucket/core/analytics/analytics_privacy_guard.dart';
import 'package:chumbucket/core/analytics/analytics_sink.dart';
import 'package:chumbucket/core/analytics/analytics_treatment.dart';

/// What happened to a recorded event. Returned so a caller (or a test) can
/// assert without reaching into the sink.
enum AnalyticsRecordOutcome {
  /// Handed to the sink.
  delivered,

  /// A duplicate of something already delivered this session.
  deduplicated,

  /// Refused by the privacy guard. Never delivered.
  rejected,
}

/// A dropped event, kept for diagnosis. Holds the event **name** and the
/// violations — never the payload, because storing the payload that had to be
/// dropped would defeat the point.
class AnalyticsRejection {
  final AnalyticsEventName name;
  final List<AnalyticsPrivacyViolation> violations;

  const AnalyticsRejection({required this.name, required this.violations});

  @override
  String toString() =>
      'AnalyticsRejection(${name.wire}: ${violations.map((v) => '$v').join('; ')})';
}

class AnalyticsRecorder {
  AnalyticsRecorder({AnalyticsSink? sink, int dedupeCapacity = 2000})
    : _sink = sink ?? InMemoryAnalyticsSink(),
      _dedupeCapacity = dedupeCapacity;

  final AnalyticsSink _sink;
  final int _dedupeCapacity;

  /// Insertion-ordered so the oldest key is the one evicted when the session
  /// gets long. A key falling out cannot double-count anything the person is
  /// still looking at.
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  final List<AnalyticsRejection> _rejections = [];

  TreatmentAssignment _assignment = TreatmentAssignment.none;

  AnalyticsSink get sink => _sink;

  /// Convenience for tests and for a debug screen. Null when the sink is not
  /// the in-memory one.
  InMemoryAnalyticsSink? get memory => switch (_sink) {
    final InMemoryAnalyticsSink sink => sink,
    ConsentGatedAnalyticsSink(inner: final InMemoryAnalyticsSink sink) => sink,
    _ => null,
  };

  TreatmentAssignment get assignment => _assignment;
  FeedTreatment get treatment => _assignment.treatment;

  /// Everything the guard refused this session.
  List<AnalyticsRejection> get rejections => List.unmodifiable(_rejections);
  int get rejectedCount => _rejections.length;

  /// Binds the experiment unit.
  ///
  /// [unitId] is the canonical `public.users.id`, or a per-install anonymous id
  /// for a signed-out person — **never a wallet** (contract §0.3). The id
  /// itself is never recorded; only the arm it hashes to.
  ///
  /// Changing the unit clears the session dedupe, so the next account's first
  /// impressions are not swallowed as duplicates of the previous one's.
  void setUnit(String? unitId) {
    final next = TreatmentAssigner.assign(unitId);
    if (next.treatment == _assignment.treatment &&
        next.experiment == _assignment.experiment) {
      return;
    }
    _assignment = next;
    _seen.clear();
  }

  /// Records [event]. Returns what happened; never throws.
  AnalyticsRecordOutcome record(AnalyticsEvent event) {
    final stamped = event.withProps({
      AnalyticsProps.experiment: _assignment.experiment,
      AnalyticsProps.treatment: _assignment.treatment.wire,
    });

    // 3. Guard first among the two that can reject, so a violating event does
    //    not consume a dedupe slot and thereby mask a later clean one.
    final violations = AnalyticsPrivacyGuard.inspect(stamped.props);
    if (violations.isNotEmpty) {
      _rejections.add(
        AnalyticsRejection(name: stamped.name, violations: violations),
      );
      assert(() {
        debugPrint(
          'Analytics: dropped ${stamped.name.wire} — '
          '${violations.map((v) => '$v').join('; ')}',
        );
        return true;
      }());
      return AnalyticsRecordOutcome.rejected;
    }

    // 2. Dedupe. Both policies use the same store; they differ only in what
    //    the typed constructor put in the key.
    if (_seen.contains(stamped.dedupeKey)) {
      return AnalyticsRecordOutcome.deduplicated;
    }
    _seen.add(stamped.dedupeKey);
    if (_seen.length > _dedupeCapacity) {
      _seen.remove(_seen.first);
    }

    _sink.add(stamped);
    return AnalyticsRecordOutcome.delivered;
  }

  /// True when [event] would be deduplicated rather than delivered. Lets a
  /// caller skip building an expensive payload; nothing depends on it.
  bool isDuplicate(AnalyticsEvent event) => _seen.contains(event.dedupeKey);

  /// Forgets what has been seen. A new app session, or a signed-out/signed-in
  /// boundary. Does not clear the sink.
  void resetSession() => _seen.clear();

  @visibleForTesting
  void clearRejections() => _rejections.clear();

  // -----------------------------------------------------------------------
  // Ambient instance
  // -----------------------------------------------------------------------

  static AnalyticsRecorder? _instance;

  /// The recorder the instrumentation uses when nothing was injected.
  ///
  /// Backed by a bounded [InMemoryAnalyticsSink], so leaving instrumentation
  /// switched on costs a few kilobytes and sends nothing anywhere. Swapping in
  /// a real destination is a deliberate, separately-approved change; see
  /// `docs/contracts/integration-requests/packet-h.md`.
  ///
  /// Nothing is recorded unless the person has switched analytics on
  /// ([AnalyticsConsent], Settings → Privacy & data).
  static AnalyticsRecorder get instance {
    final existing = _instance;
    if (existing != null) return existing;
    // Read the stored choice; until it is read, nothing is recorded.
    AnalyticsConsent.instance.ensureLoaded();
    return _instance = AnalyticsRecorder(
      sink: ConsentGatedAnalyticsSink(InMemoryAnalyticsSink()),
    );
  }

  /// Replaces the ambient recorder. Tests use this; production should inject a
  /// recorder rather than reassign the global.
  @visibleForTesting
  static void debugSetInstance(AnalyticsRecorder? recorder) {
    _instance = recorder;
  }
}
