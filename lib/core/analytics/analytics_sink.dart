/// Where events go — which, today, is nowhere off the device.
///
/// **No implementation in this package performs a network call, and none may.**
/// Choosing a destination is a separate, separately-approved decision; this
/// file exists so that decision is a one-class change rather than a rewrite of
/// every call site.
///
/// ## Why this is not routed through `lib/core/services/analytics_service.dart`
///
/// That service is read-only to this packet and stays as it is, but it is the
/// wrong pipe for this experiment on four independent counts:
///
/// 1. It posts to a Supabase Edge Function (`analytics-telegram`) on every
///    call. The brief for this work is explicit: send analytics nowhere.
/// 2. Its payloads carry exactly what Packet I's acceptance forbids —
///    `wallet_address`, `creator_wallet`, `witness_wallet`, `winner_wallet`,
///    `amount_sol`, `fee_sol`, `winner_amount_sol`. Routing through it would
///    mean shipping a guard that the transport underneath is already violating.
/// 3. Its four methods are a fixed, Arena-era vocabulary (`user_signup`,
///    `challenge_created`, `challenge_resolved`, `error`) with no overlap with
///    the roadmap's sixteen names, and each takes free-form `String` arguments
///    — the opposite of "a typo cannot silently create a new event".
/// 4. It has no notion of deduplication or of an experiment arm, so the one
///    comparison the founder's decision rests on could not be made from its
///    output.
///
/// So this package ships its own sink behind [AnalyticsSink]. If the two are
/// ever unified, the direction is to put the guard in front of the service, not
/// to put this experiment behind it.
library;

import 'package:chumbucket/core/analytics/analytics_event.dart';

/// The one seam a future destination implements.
///
/// Implementations must not throw: analytics never blocks a user flow. They
/// must also not mutate the event.
abstract interface class AnalyticsSink {
  void add(AnalyticsEvent event);
}

/// Drops everything. The correct sink for a release build until a destination
/// is chosen, and for any test that does not assert on analytics.
class NoopAnalyticsSink implements AnalyticsSink {
  const NoopAnalyticsSink();

  @override
  void add(AnalyticsEvent event) {}
}

/// Keeps events in a bounded in-memory ring. This is the default, and it is
/// what makes the instrumentation safe to leave switched on: the events exist
/// for inspection and for tests, and they never leave the process.
class InMemoryAnalyticsSink implements AnalyticsSink {
  /// Oldest events are discarded past this. A session cannot grow memory
  /// without bound just because somebody scrolls a feed for an hour.
  final int capacity;

  final List<AnalyticsEvent> _events = [];

  InMemoryAnalyticsSink({this.capacity = 1000})
    : assert(capacity > 0, 'capacity must be positive');

  List<AnalyticsEvent> get events => List.unmodifiable(_events);

  int get length => _events.length;

  /// Every event with this name, in order. The usual assertion in a test.
  List<AnalyticsEvent> named(AnalyticsEventName name) =>
      _events.where((e) => e.name == name).toList(growable: false);

  int countOf(AnalyticsEventName name) =>
      _events.where((e) => e.name == name).length;

  AnalyticsEvent? lastOf(AnalyticsEventName name) {
    for (var i = _events.length - 1; i >= 0; i--) {
      if (_events[i].name == name) return _events[i];
    }
    return null;
  }

  /// The distinct names seen, in first-seen order.
  List<AnalyticsEventName> get distinctNames {
    final seen = <AnalyticsEventName>[];
    for (final event in _events) {
      if (!seen.contains(event.name)) seen.add(event.name);
    }
    return seen;
  }

  @override
  void add(AnalyticsEvent event) {
    _events.add(event);
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
  }

  void clear() => _events.clear();
}

/// Fans one event out to several sinks. Used when a destination is eventually
/// added beside the in-memory one rather than instead of it.
class FanOutAnalyticsSink implements AnalyticsSink {
  final List<AnalyticsSink> sinks;
  const FanOutAnalyticsSink(this.sinks);

  @override
  void add(AnalyticsEvent event) {
    for (final sink in sinks) {
      sink.add(event);
    }
  }
}
