/// The people layer's view models and their wire parsing: leaderboard, people
/// search, the viewer's following list, Home's top calls and the thesis
/// thread.
///
/// Same posture as `calls_bff_payloads.dart`: a shape that is not what the
/// server contract says is a [CallVocabularyException], never a silent default
/// — and a missing *optional* field is not drift.
///
/// Two rules travel with these types, because they are what make the surfaces
/// honest:
///
/// * [PublicRecord.accuracy] is non-null ONLY when the server sent an accuracy,
///   which it does only at or above [PublicRecord.minimumDecided] decided
///   calls. Below that a client has no percentage to render, so it cannot.
/// * [TopCall.split] is non-null ONLY once the viewer has their own call on that
///   market. The server withholds it; null stays null here.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';

// ---------------------------------------------------------------------------
// The public record
// ---------------------------------------------------------------------------

/// A person's record as the public may see it: public free calls, withdrawn
/// ones included, followers-only excluded, trades never blended in.
class PublicRecord {
  final int correct;
  final int incorrect;
  final int voided;
  final int decided;
  final int pending;

  /// `correct / decided`, present only when the sample is large enough.
  final double? accuracy;
  final int minimumDecided;

  const PublicRecord({
    required this.correct,
    required this.incorrect,
    required this.voided,
    required this.decided,
    required this.pending,
    required this.minimumDecided,
    this.accuracy,
  });

  static const PublicRecord empty = PublicRecord(
    correct: 0,
    incorrect: 0,
    voided: 0,
    decided: 0,
    pending: 0,
    minimumDecided: 10,
  );

  /// Every call counted, resolved or not.
  int get total => decided + voided + pending;

  bool get hasAccuracy => accuracy != null;

  /// How many more decided calls before a percentage (and a rank) is shown.
  int get decidedToRank =>
      decided >= minimumDecided ? 0 : minimumDecided - decided;

  /// `{ counts: {...}, display: { mode, accuracy?, minimumDecided } }`.
  ///
  /// The counts must close (decided = correct + incorrect); an accuracy is read
  /// only from an `accuracy`-mode display, and only if it agrees with the
  /// counts it claims to summarise.
  factory PublicRecord.fromJson(Map<String, dynamic> json) {
    final counts = requireJsonMap(json['counts'], 'PublicRecord.counts');
    final display = requireJsonMap(json['display'], 'PublicRecord.display');
    final correct = requireWireCount(counts['correct'], 'counts.correct');
    final incorrect = requireWireCount(counts['incorrect'], 'counts.incorrect');
    final decided = requireWireCount(counts['decided'], 'counts.decided');
    if (decided != correct + incorrect) {
      throw const CallVocabularyException(
        'A record must count every decided call, misses included.',
      );
    }
    final minimum = requireWireCount(
      display['minimumDecided'],
      'display.minimumDecided',
      fallback: 10,
    );
    double? accuracy;
    switch (display['mode']) {
      case 'counts':
        accuracy = null;
      case 'accuracy':
        final raw = display['accuracy'];
        if (raw is! num || decided < minimum || decided == 0) {
          throw const CallVocabularyException(
            'An accuracy needs its full decided sample.',
          );
        }
        accuracy = raw.toDouble();
      default:
        throw CallVocabularyException(
          'Unknown record display mode "${display['mode']}"',
        );
    }
    return PublicRecord(
      correct: correct,
      incorrect: incorrect,
      voided: requireWireCount(counts['voided'], 'counts.voided'),
      decided: decided,
      pending: requireWireCount(counts['pending'], 'counts.pending'),
      accuracy: accuracy,
      minimumDecided: minimum,
    );
  }
}

// ---------------------------------------------------------------------------
// People
// ---------------------------------------------------------------------------

/// A person as the people surfaces list them. Never a wallet.
class PersonCard {
  final String id;
  final String handle;
  final String displayName;
  final String? avatarUrl;
  final PublicRecord record;
  final bool viewerIsFollowing;

  const PersonCard({
    required this.id,
    required this.handle,
    required this.displayName,
    required this.record,
    this.avatarUrl,
    this.viewerIsFollowing = false,
  });

  String get initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}';
    return parts.first.substring(0, 1);
  }

  /// [record] arrives either beside the identity fields or (on a leaderboard
  /// row) one level up; [recordJson] lets the caller say which.
  factory PersonCard.fromJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? recordJson,
  }) => PersonCard(
    id: requireWireString(json['id'], 'PersonCard.id'),
    handle: requireWireString(json['handle'], 'PersonCard.handle'),
    displayName: requireWireString(
      json['displayName'],
      'PersonCard.displayName',
    ),
    avatarUrl: json['avatarUrl'] as String?,
    record: PublicRecord.fromJson(
      recordJson ?? requireJsonMap(json['record'], 'PersonCard.record'),
    ),
    viewerIsFollowing: requireWireBool(
      json['viewerIsFollowing'],
      'PersonCard.viewerIsFollowing',
    ),
  );
}

List<PersonCard> personCardsFromJson(Object? value, String field) =>
    requireJsonList(value, field).map(PersonCard.fromJson).toList();

// ---------------------------------------------------------------------------
// Leaderboard
// ---------------------------------------------------------------------------

enum LeaderboardWindow {
  week('7d', '7D', 'the last 7 days'),
  month('30d', '30D', 'the last 30 days'),
  all('all', 'All', 'all time');

  const LeaderboardWindow(this.wire, this.label, this.phrase);
  final String wire;
  final String label;

  /// "in the last 7 days" style copy for empty states.
  final String phrase;

  static LeaderboardWindow fromWire(Object? raw) =>
      LeaderboardWindow.values.firstWhere(
        (w) => w.wire == raw,
        orElse:
            () =>
                throw CallVocabularyException(
                  'Unknown leaderboard window "$raw"',
                ),
      );
}

class LeaderboardRow {
  /// 1-based; null for anyone below the minimum decided sample.
  final int? rank;
  final PersonCard person;

  const LeaderboardRow({required this.rank, required this.person});

  PublicRecord get record => person.record;

  factory LeaderboardRow.fromJson(Map<String, dynamic> json) {
    final rank = json['rank'];
    final record = requireJsonMap(json['record'], 'LeaderboardRow.record');
    final person = requireJsonMap(json['person'], 'LeaderboardRow.person');
    final row = LeaderboardRow(
      rank: rank == null ? null : requireWireCount(rank, 'LeaderboardRow.rank'),
      person: PersonCard.fromJson(person, recordJson: record),
    );
    if (row.rank != null && !row.record.hasAccuracy) {
      throw const CallVocabularyException(
        'A ranked row must carry the accuracy it was ranked on.',
      );
    }
    return row;
  }
}

class Leaderboard {
  final LeaderboardWindow window;
  final List<LeaderboardRow> ranked;
  final List<LeaderboardRow> building;

  /// The signed-in viewer's own row, or null when signed out.
  final LeaderboardRow? viewer;
  final int minimumDecided;

  /// The server's plain-language ranking rule.
  final String rule;
  final int servedAt;

  const Leaderboard({
    required this.window,
    required this.ranked,
    required this.building,
    required this.minimumDecided,
    required this.rule,
    required this.servedAt,
    this.viewer,
  });

  bool get isEmpty => ranked.isEmpty && building.isEmpty;

  factory Leaderboard.fromJson(Map<String, dynamic> json) {
    final viewer = optionalJsonMap(json['viewer'], 'Leaderboard.viewer');
    return Leaderboard(
      window: LeaderboardWindow.fromWire(json['window']),
      ranked:
          requireJsonList(
            json['ranked'],
            'Leaderboard.ranked',
          ).map(LeaderboardRow.fromJson).toList(),
      building:
          requireJsonList(
            json['building'],
            'Leaderboard.building',
          ).map(LeaderboardRow.fromJson).toList(),
      viewer: viewer == null ? null : LeaderboardRow.fromJson(viewer),
      minimumDecided: requireWireCount(
        json['minimumDecided'],
        'Leaderboard.minimumDecided',
      ),
      rule: requireWireString(json['rule'], 'Leaderboard.rule'),
      servedAt: requireWireTimestampMs(
        json['servedAt'],
        'Leaderboard.servedAt',
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top calls
// ---------------------------------------------------------------------------

/// Backs and fades on one call. Only ever handed over once the viewer has
/// their own call on the market.
class TopCallSplit {
  final int backs;
  final int fades;
  const TopCallSplit({required this.backs, required this.fades});
}

class TopCall {
  final Call call;
  final PersonCard author;
  final VenueMarket market;

  /// Backs + fades + challenges. Engagement, with no direction.
  final int responses;
  final TopCallSplit? split;
  final bool viewerHasCalled;

  const TopCall({
    required this.call,
    required this.author,
    required this.market,
    required this.responses,
    this.split,
    this.viewerHasCalled = false,
  });

  factory TopCall.fromJson(Map<String, dynamic> json) {
    final call = Call.fromJson(requireJsonMap(json['call'], 'TopCall.call'));
    final market = VenueMarket.fromJson(
      requireJsonMap(json['market'], 'TopCall.market'),
    );
    final author = requireJsonMap(json['author'], 'TopCall.author');
    final split = optionalJsonMap(json['split'], 'TopCall.split');
    final viewerHasCalled = requireWireBool(
      json['viewerHasCalled'],
      'TopCall.viewerHasCalled',
    );
    if (split != null && !viewerHasCalled) {
      throw const CallVocabularyException(
        'A crowd split arrived before the viewer made a call.',
      );
    }
    if (call.marketId != market.id) {
      throw const CallVocabularyException('Top call/market mismatch.');
    }
    return TopCall(
      call: call,
      author: PersonCard.fromJson({...author, 'viewerIsFollowing': false}),
      market: market,
      responses: requireWireCount(json['responses'], 'TopCall.responses'),
      split:
          split == null
              ? null
              : TopCallSplit(
                backs: requireWireCount(split['backs'], 'split.backs'),
                fades: requireWireCount(split['fades'], 'split.fades'),
              ),
      viewerHasCalled: viewerHasCalled,
    );
  }
}

List<TopCall> topCallsFromJson(Map<String, dynamic> json) =>
    requireJsonList(
      json['entries'],
      'TopCallsPage.entries',
    ).map(TopCall.fromJson).toList();

// ---------------------------------------------------------------------------
// The thesis thread
// ---------------------------------------------------------------------------

/// One timestamped follow-up the author appended after locking. The original
/// thesis on [Call] is never changed by one.
class ThesisUpdate {
  final String id;
  final String callId;
  final String authorUserId;
  final String body;
  final int createdAt;

  const ThesisUpdate({
    required this.id,
    required this.callId,
    required this.authorUserId,
    required this.body,
    required this.createdAt,
  });

  DateTime get createdAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true);

  factory ThesisUpdate.fromJson(Map<String, dynamic> json) => ThesisUpdate(
    id: requireWireString(json['id'], 'ThesisUpdate.id'),
    callId: requireWireString(json['callId'], 'ThesisUpdate.callId'),
    authorUserId: requireWireString(
      json['authorUserId'],
      'ThesisUpdate.authorUserId',
    ),
    body: requireWireString(json['body'], 'ThesisUpdate.body'),
    createdAt: requireWireTimestampMs(
      json['createdAt'],
      'ThesisUpdate.createdAt',
    ),
  );
}

/// Most a thread may carry; the server enforces it, this only words the UI.
const int kMaxThesisUpdatesPerCall = 20;
