/// The real-data rules behind each optional step (onboarding spec §4.3–§4.5,
/// §6). Pure functions over what the server returned: no fixtures, no
/// padding, nothing invented. A step without enough real data is skipped.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';

// ── Display rules (§4.5) ─────────────────────────────────────────────────────

/// A handle-less account's placeholder (`user-80d78065`). Never shown.
final RegExp kPlaceholderHandle = RegExp(r'^user-[0-9a-f]{8}$');

/// The @handle to show, or null when the account only has a placeholder.
String? visibleHandle(String? handle) {
  final h = handle?.trim().replaceFirst(RegExp(r'^@'), '');
  if (h == null || h.isEmpty || kPlaceholderHandle.hasMatch(h)) return null;
  return h;
}

/// The display name to show, or null when there is none. The server falls
/// back to the handle — and so to the placeholder — when an account has no
/// name (`personFromRow`: `full_name ?? handle`), so a "name" that is only a
/// placeholder is no name at all.
String? visibleDisplayName(String displayName) {
  final name = displayName.trim();
  if (name.isEmpty || kPlaceholderHandle.hasMatch(name)) return null;
  return name;
}

/// A person onboarding may show: the server gave a real display name or a
/// real handle. Someone with neither is left out rather than invented.
bool isShowablePerson({required String displayName, String? handle}) =>
    visibleDisplayName(displayName) != null || visibleHandle(handle) != null;

/// The name to show: the display name, else the real handle.
String shownName({required String displayName, String? handle}) =>
    visibleDisplayName(displayName) ?? '@${visibleHandle(handle) ?? ''}';

/// A market a call can be made on right now: OPEN, already open, closing in
/// the future, and from the live venue — never a demo fixture.
bool isLiveOpenMarket(VenueMarket market, DateTime now) {
  final at = now.toUtc().millisecondsSinceEpoch;
  return market.status.acceptsNewCalls &&
      !market.venue.isDemo &&
      (market.opensAt == null || market.opensAt! <= at) &&
      market.closesAt != null &&
      market.closesAt! > at;
}

/// Calls need this long before a market closes to be a first-call pick
/// (§4.3): a receipt that arrives soon closes the loop, one that is about to
/// close cannot be locked in time.
const Duration kFirstCallMinRunway = Duration(minutes: 30);

bool isCallReadyMarket(VenueMarket market, DateTime now) =>
    isLiveOpenMarket(market, now) &&
    market.closesAt! >
        now.toUtc().add(kFirstCallMinRunway).millisecondsSinceEpoch;

// ── Topics (T) ───────────────────────────────────────────────────────────────

class TopicCount {
  const TopicCount(this.slug, this.openCount);

  /// The venue's category slug, lowercased (`pop-culture`).
  final String slug;
  final int openCount;

  @override
  bool operator ==(Object other) =>
      other is TopicCount && other.slug == slug && other.openCount == openCount;

  @override
  int get hashCode => Object.hash(slug, openCount);

  @override
  String toString() => 'TopicCount($slug, $openCount)';
}

/// Categories with at least one market open right now, by open count then
/// slug. A market still labelled OPEN after its close time is not open.
List<TopicCount> topicsFrom(Iterable<VenueMarket> markets, DateTime now) {
  final counts = <String, int>{};
  for (final market in markets) {
    if (!isLiveOpenMarket(market, now)) continue;
    final slug = market.category.trim().toLowerCase();
    if (slug.isEmpty) continue;
    counts[slug] = (counts[slug] ?? 0) + 1;
  }
  return [for (final e in counts.entries) TopicCount(e.key, e.value)]
    ..sort((a, b) {
      final byCount = b.openCount.compareTo(a.openCount);
      return byCount != 0 ? byCount : a.slug.compareTo(b.slug);
    });
}

/// T is worth showing only when there is a real choice to make.
const int kMinTopicsToShow = 2;

bool topicsWorthShowing(List<TopicCount> topics) =>
    topics.length >= kMinTopicsToShow;

// ── First call (C) ───────────────────────────────────────────────────────────

/// Markets C may offer, best first: chosen topics, then soonest to close.
/// Prices are checked separately (each must be fresh before it is shown).
List<VenueMarket> firstCallCandidates(
  Iterable<VenueMarket> markets, {
  required Set<String> topics,
  required DateTime now,
}) {
  final rows = markets.where((m) => isCallReadyMarket(m, now)).toList();
  int rank(VenueMarket m) =>
      topics.contains(m.category.trim().toLowerCase()) ? 0 : 1;
  rows.sort((a, b) {
    final byTopic = rank(a).compareTo(rank(b));
    if (byTopic != 0) return byTopic;
    final byClose = a.closesAt!.compareTo(b.closesAt!);
    return byClose != 0 ? byClose : a.id.compareTo(b.id);
  });
  return rows;
}

/// At most this many markets in "Or call one yourself".
const int kFirstCallMarkets = 3;

/// At most this many cards in "Answer a call".
const int kAnswerableCalls = 2;

/// A call the viewer could Back or Fade from C: someone else's live public
/// call on a call-ready market they have not called. People the viewer chose
/// to follow come first.
List<TopCall> answerableCalls(
  Iterable<TopCall> top, {
  required String? viewerUserId,
  required Set<String> preferredAuthors,
  required DateTime now,
}) {
  final rows =
      top
          .where(
            (t) =>
                t.author.id != viewerUserId &&
                !t.viewerHasCalled &&
                t.call.visibility == CallVisibility.public &&
                isCallReadyMarket(t.market, now) &&
                isShowablePerson(
                  displayName: t.author.displayName,
                  handle: t.author.handle,
                ),
          )
          .toList();
  final ordered = [
    ...rows.where((t) => preferredAuthors.contains(t.author.id)),
    ...rows.where((t) => !preferredAuthors.contains(t.author.id)),
  ];
  final seenMarkets = <String>{};
  final out = <TopCall>[];
  for (final t in ordered) {
    if (!seenMarkets.add(t.market.id)) continue;
    out.add(t);
    if (out.length == kAnswerableCalls) break;
  }
  return out;
}

/// The feed row a [TopCall] stands for, so the existing Back/Fade sheet can
/// review it.
CallFeedEntry entryOfTopCall(TopCall top) => CallFeedEntry(
  call: top.call,
  author: Person(
    id: top.author.id,
    handle: top.author.handle,
    displayName: top.author.displayName,
    avatarUrl: top.author.avatarUrl,
  ),
  market: top.market,
  viewerHasCalled: top.viewerHasCalled,
);

// ── Welcome's live strip (W1) ───────────────────────────────────────────────

enum LiveStripSource {
  top('top'),
  feed('feed'),
  markets('markets'),
  none('none');

  const LiveStripSource(this.wire);
  final String wire;
}

/// One card on the strip: somebody's call, or (when nobody has called
/// anything live) a market open on Panta.
sealed class LiveItem {
  const LiveItem();
}

class LiveCallItem extends LiveItem {
  const LiveCallItem(this.entry);
  final CallFeedEntry entry;
}

class LiveMarketItem extends LiveItem {
  const LiveMarketItem(this.market);
  final VenueMarket market;
}

class LiveStrip {
  const LiveStrip(this.source, this.items);
  static const empty = LiveStrip(LiveStripSource.none, []);
  final LiveStripSource source;
  final List<LiveItem> items;
  bool get isEmpty => items.isEmpty;
}

const int kLiveStripCalls = 6;
const int kLiveStripMarkets = 3;

bool _liveCall(CallFeedEntry e, DateTime now) =>
    e.call.visibility == CallVisibility.public &&
    isLiveOpenMarket(e.market, now) &&
    isShowablePerson(
      displayName: e.author.displayName,
      handle: e.author.handle,
    );

/// Live calls from `calls.top`, else from the global feed, else open markets,
/// else nothing (§6 W1). Only what the server returned, and never a demo row.
/// A source that has not answered yet is passed as null and skipped.
LiveStrip chooseLiveStrip({
  List<TopCall>? top,
  List<CallFeedEntry>? feed,
  List<VenueMarket>? markets,
  required DateTime now,
}) {
  final fromTop = [
    for (final t in top ?? const <TopCall>[])
      if (_liveCall(entryOfTopCall(t), now)) LiveCallItem(entryOfTopCall(t)),
  ];
  if (fromTop.isNotEmpty) {
    return LiveStrip(
      LiveStripSource.top,
      fromTop.take(kLiveStripCalls).toList(),
    );
  }
  final seen = <String>{};
  final fromFeed = [
    for (final e in feed ?? const <CallFeedEntry>[])
      if (_liveCall(e, now) && seen.add(e.call.id)) LiveCallItem(e),
  ];
  if (fromFeed.isNotEmpty) {
    return LiveStrip(
      LiveStripSource.feed,
      fromFeed.take(kLiveStripCalls).toList(),
    );
  }
  final open =
      (markets ?? const <VenueMarket>[])
          .where((m) => isLiveOpenMarket(m, now))
          .toList()
        ..sort((a, b) => a.closesAt!.compareTo(b.closesAt!));
  if (open.isNotEmpty) {
    return LiveStrip(LiveStripSource.markets, [
      for (final m in open.take(kLiveStripMarkets)) LiveMarketItem(m),
    ]);
  }
  return LiveStrip.empty;
}

/// W1's phone: real people's calls first (live ones, then recently settled
/// ones with their result), then markets open on Panta to fill the screen.
/// Only rows the server returned; a source still loading is passed as null.
class WelcomeFeed {
  const WelcomeFeed(this.items);
  static const empty = WelcomeFeed([]);
  final List<LiveItem> items;
  bool get isEmpty => items.isEmpty;
  bool get hasCalls => items.any((i) => i is LiveCallItem);

  /// For analytics: what the phone ended up showing.
  String get source =>
      isEmpty
          ? 'none'
          : hasCalls
          ? 'calls'
          : 'markets';
}

/// How many cards the phone aims to show.
const int kWelcomeFeedTarget = 5;

WelcomeFeed chooseWelcomeFeed({
  List<TopCall>? top,
  List<CallFeedEntry>? feed,
  List<VenueMarket>? markets,
  required DateTime now,
}) {
  final seen = <String>{};
  final live = <LiveItem>[];
  final settled = <LiveItem>[];
  for (final e in [
    for (final t in top ?? const <TopCall>[]) entryOfTopCall(t),
    ...?feed,
  ]) {
    if (e.call.visibility != CallVisibility.public ||
        !isShowablePerson(
          displayName: e.author.displayName,
          handle: e.author.handle,
        ) ||
        !seen.add(e.call.id)) {
      continue;
    }
    if (isLiveOpenMarket(e.market, now)) {
      live.add(LiveCallItem(e));
    } else if (e.result != null && e.result!.outcome != CallOutcome.pending) {
      settled.add(LiveCallItem(e));
    }
  }
  final calls = [...live, ...settled].take(kLiveStripCalls).toList();
  final open =
      (markets ?? const <VenueMarket>[])
          .where((m) => isLiveOpenMarket(m, now))
          .toList()
        ..sort((a, b) => a.closesAt!.compareTo(b.closesAt!));
  final fill = kWelcomeFeedTarget - calls.length;
  return WelcomeFeed([
    ...calls,
    if (fill > 0)
      for (final m in open.take(fill)) LiveMarketItem(m),
  ]);
}

// ── People (P) ──────────────────────────────────────────────────────────────

/// The record line under a person (§6 P): accuracy only when the server
/// published one; otherwise the evidence as counts.
String recordLine(
  PublicRecord record, {
  required String Function(int correct, int decided) accuracy,
  required String Function(int decided) building,
  required String Function(int open) open,
  required String none,
}) {
  if (record.hasAccuracy) return accuracy(record.correct, record.decided);
  if (record.decided > 0) return building(record.decided);
  if (record.pending > 0) return open(record.pending);
  return none;
}

/// P is worth showing with two real callers, or one real friend (§4.3).
bool peopleWorthShowing({required int suggestions, required int friends}) =>
    suggestions >= 2 || friends >= 1;

/// Composes suggestions from the people reads that are already deployed, for
/// a server without `people.suggested` (§13.3 fallback): ranked people, then
/// authors of top calls, then people building a record. Self and people
/// already followed are left out; nobody appears twice; nobody is padded in.
/// Feed-only authors are not added here: the feed carries no public record
/// for them, and a row without one would be guesswork.
List<PersonSuggestion> composeSuggestions({
  Leaderboard? allTime,
  List<TopCall> top = const [],
  required String? viewerUserId,
  Set<String> alreadyFollowing = const {},
  required DateTime now,
  int limit = 10,
}) {
  final out = <PersonSuggestion>[];
  final seen = <String>{};
  LatestLiveCall? latestFor(String personId) {
    final live =
        top
            .where(
              (t) =>
                  t.author.id == personId &&
                  t.call.visibility == CallVisibility.public &&
                  isLiveOpenMarket(t.market, now),
            )
            .toList()
          ..sort((a, b) => b.call.lockedAt.compareTo(a.call.lockedAt));
    final t = live.firstOrNull;
    if (t == null) return null;
    return LatestLiveCall(
      callId: t.call.id,
      side: t.call.side,
      marketId: t.market.id,
      question: t.market.question,
      closesAt: t.market.closesAt,
    );
  }

  void add(PersonCard person, SuggestionReason reason) {
    if (out.length >= limit) return;
    if (person.id == viewerUserId || alreadyFollowing.contains(person.id)) {
      return;
    }
    if (person.viewerIsFollowing) return;
    if (!isShowablePerson(
      displayName: person.displayName,
      handle: person.handle,
    )) {
      return;
    }
    // Only people with at least one public free call (§13.3).
    if (person.record.total == 0) return;
    if (!seen.add(person.id)) return;
    out.add(
      PersonSuggestion(
        person: person,
        reason: reason,
        latestLiveCall: latestFor(person.id),
      ),
    );
  }

  for (final row in allTime?.ranked ?? const <LeaderboardRow>[]) {
    add(row.person, SuggestionReason.ranked);
  }
  final byVolume = [...top]..sort((a, b) => b.responses.compareTo(a.responses));
  for (final t in byVolume) {
    add(t.author, SuggestionReason.topCall);
  }
  for (final row in allTime?.building ?? const <LeaderboardRow>[]) {
    add(row.person, SuggestionReason.building);
  }
  return out;
}

// ── Home arrival (§6) ───────────────────────────────────────────────────────

/// Following only when the person followed someone and that feed has a call
/// to show; otherwise Global. Never a fake personalised feed.
CallFeedMode homeArrivalMode({
  required int followed,
  required int followingFeedEntries,
}) =>
    followed > 0 && followingFeedEntries > 0
        ? CallFeedMode.following
        : CallFeedMode.global;

// ── Markets "For you" ───────────────────────────────────────────────────────

/// Chosen-topic markets first (in their existing order), then the rest under
/// "More on Panta". Nothing is hidden and nothing else is reordered.
({List<VenueMarket> chosen, List<VenueMarket> more}) forYouOrder(
  List<VenueMarket> rows,
  Set<String> topics,
) {
  final chosen = <VenueMarket>[];
  final more = <VenueMarket>[];
  for (final m in rows) {
    (topics.contains(m.category.trim().toLowerCase()) ? chosen : more).add(m);
  }
  return (chosen: chosen, more: more);
}

/// Home's top calls with chosen-topic calls first, otherwise in the server's
/// order (a stable partition).
List<TopCall> topCallsForTopics(List<TopCall> calls, Set<String> topics) {
  if (topics.isEmpty) return calls;
  return [
    ...calls.where(
      (t) => topics.contains(t.market.category.trim().toLowerCase()),
    ),
    ...calls.where(
      (t) => !topics.contains(t.market.category.trim().toLowerCase()),
    ),
  ];
}
