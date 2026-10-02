/// Wire ⇄ view-model translation for the BFF-backed call slice.
///
/// The FROZEN contract types (`Call`, `VenueMarket`, `MarketSnapshot`,
/// `CallResponse`, `CallResult`, every enum) already parse themselves in
/// `call_models.dart`, and that parsing is **reused verbatim** here — an
/// unknown wire value must surface as a [CallVocabularyException], never be
/// coerced into a neighbouring member.
///
/// What this file adds is only the view models declared in
/// `calls_repository.dart` ([Person], [CallFeedEntry], [CallFeedPage],
/// [CrowdSplit], [MarketDetail], [CallDetail], [PersonDetail],
/// [ChallengeInvitation], [CallResponseResult]). Those are Packet-C local and
/// carry no `fromJson` of their own, and both of those files are frozen — so
/// the constructors are called from here instead.
///
/// Shapes are the §5 table in
/// `docs/contracts/integration-requests/packet-c.md`, whose payloads are the
/// FROZEN §3 shapes verbatim.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/people/data/people_models.dart';

// ---------------------------------------------------------------------------
// Structural guards
//
// Same posture as `call_models.dart`: a shape that is not what the contract
// says is a CallVocabularyException, not a silent default. A missing *optional*
// field is not a drift, so those return null.
// ---------------------------------------------------------------------------

Map<String, dynamic> requireJsonMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  throw CallVocabularyException('$field must be a JSON object, got "$value"');
}

Map<String, dynamic>? optionalJsonMap(Object? value, String field) =>
    value == null ? null : requireJsonMap(value, field);

List<Map<String, dynamic>> requireJsonList(Object? value, String field) {
  if (value == null) return const [];
  if (value is! List) {
    throw CallVocabularyException('$field must be a JSON array, got "$value"');
  }
  return value
      .map((element) => requireJsonMap(element, '$field[]'))
      .toList(growable: false);
}

int requireWireTimestampMs(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw CallVocabularyException(
    '$field must be unix milliseconds (integer), got "$value"',
  );
}

int requireWireCount(Object? value, String field, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw CallVocabularyException('$field must be an integer, got "$value"');
}

String requireWireString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw CallVocabularyException(
    '$field must be a non-empty string, got "$value"',
  );
}

bool requireWireBool(Object? value, String field, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  throw CallVocabularyException('$field must be a boolean, got "$value"');
}

// ---------------------------------------------------------------------------
// Person
// ---------------------------------------------------------------------------

/// `Person` is keyed by the canonical `public.users.id`. `walletAddress` is a
/// linked credential and is optional — it is **never** the identity.
Person personFromJson(Map<String, dynamic> json) => Person(
  id: requireWireString(json['id'], 'Person.id'),
  handle: requireWireString(json['handle'], 'Person.handle'),
  displayName: requireWireString(json['displayName'], 'Person.displayName'),
  avatarUrl: json['avatarUrl'] as String?,
  walletAddress: json['walletAddress'] as String?,
  settledCalls: requireWireCount(json['settledCalls'], 'Person.settledCalls'),
  correctCalls: requireWireCount(json['correctCalls'], 'Person.correctCalls'),
  bio: switch (json['bio']) {
    final String bio when bio.trim().isNotEmpty => bio.trim(),
    _ => null,
  },
  joinedAt:
      json['joinedAt'] == null
          ? null
          : requireWireTimestampMs(json['joinedAt'], 'Person.joinedAt'),
);

// ---------------------------------------------------------------------------
// Feed
// ---------------------------------------------------------------------------

/// One `{ call, author, market, result?, backCount, fadeCount,
/// viewerHasCalled }` row.
CallFeedEntry callFeedEntryFromJson(Map<String, dynamic> json) {
  final result = optionalJsonMap(json['result'], 'CallFeedEntry.result');
  final call = Call.fromJson(
    requireJsonMap(json['call'], 'CallFeedEntry.call'),
  );
  final market = VenueMarket.fromJson(
    requireJsonMap(json['market'], 'CallFeedEntry.market'),
  );
  if ((market.venue == MarketVenue.panta) != (call.entryPrice != null) ||
      (call.entryPrice != null && call.entryPrice!.marketId != market.id)) {
    throw const CallVocabularyException(
      'Call/market share-price provenance mismatch',
    );
  }
  return CallFeedEntry(
    call: call,
    author: personFromJson(
      requireJsonMap(json['author'], 'CallFeedEntry.author'),
    ),
    market: market,
    result: result == null ? null : CallResult.fromJson(result),
    backCount: requireWireCount(json['backCount'], 'CallFeedEntry.backCount'),
    fadeCount: requireWireCount(json['fadeCount'], 'CallFeedEntry.fadeCount'),
    viewerHasCalled: requireWireBool(
      json['viewerHasCalled'],
      'CallFeedEntry.viewerHasCalled',
    ),
  );
}

List<CallFeedEntry> callFeedEntriesFromJson(Object? value, String field) =>
    requireJsonList(
      value,
      field,
    ).map(callFeedEntryFromJson).toList(growable: false);

/// `{ entries, nextCursor?, servedAt }`.
///
/// [CallFeedPage.fromCache] is not on the wire and never can be: a page that
/// came from the BFF is by definition live. Only a caching decorator may set
/// it, so it stays false here.
CallFeedPage callFeedPageFromJson(Map<String, dynamic> json) => CallFeedPage(
  entries: callFeedEntriesFromJson(json['entries'], 'CallFeedPage.entries'),
  nextCursor: json['nextCursor'] as String?,
  servedAt: requireWireTimestampMs(json['servedAt'], 'CallFeedPage.servedAt'),
);

// ---------------------------------------------------------------------------
// Market detail
// ---------------------------------------------------------------------------

CrowdSplit crowdSplitFromJson(Map<String, dynamic> json) => CrowdSplit(
  marketId: requireWireString(json['marketId'], 'CrowdSplit.marketId'),
  yesCalls: requireWireCount(json['yesCalls'], 'CrowdSplit.yesCalls'),
  noCalls: requireWireCount(json['noCalls'], 'CrowdSplit.noCalls'),
);

/// `{ market, snapshot?, viewerCall?, crowdSplit?, servedAt }`.
///
/// **`crowdSplit` absent or null means withheld, not zero.** The server
/// withholds it until the viewer has a locked call on the market (§5.1), and
/// an absent split must stay null so the UI renders "hidden until you call"
/// rather than a 0/0 bar that reads as "nobody has called".
MarketDetail marketDetailFromJson(Map<String, dynamic> json) {
  final native = optionalJsonMap(json['sharePrice'], 'MarketDetail.sharePrice');
  final sharePrice =
      native == null ? null : SharePriceSnapshot.fromJson(native);
  final market = VenueMarket.fromJson(
    requireJsonMap(json['market'], 'MarketDetail.market'),
  );
  if (sharePrice != null &&
      (market.venue != MarketVenue.panta ||
          market.id != sharePrice.marketId ||
          json['snapshot'] != null)) {
    throw const CallVocabularyException(
      'Market share-price provenance mismatch',
    );
  }
  final snapshot = optionalJsonMap(json['snapshot'], 'MarketDetail.snapshot');
  final viewerCall = optionalJsonMap(
    json['viewerCall'],
    'MarketDetail.viewerCall',
  );
  final crowdSplit = optionalJsonMap(
    json['crowdSplit'],
    'MarketDetail.crowdSplit',
  );
  return MarketDetail(
    market: market,
    sharePrice: sharePrice,
    snapshot: snapshot == null ? null : MarketSnapshot.fromJson(snapshot),
    viewerCall: viewerCall == null ? null : callFeedEntryFromJson(viewerCall),
    crowdSplit: crowdSplit == null ? null : crowdSplitFromJson(crowdSplit),
    servedAt: requireWireTimestampMs(json['servedAt'], 'MarketDetail.servedAt'),
  );
}

// ---------------------------------------------------------------------------
// Call detail
// ---------------------------------------------------------------------------

/// `{ entry, parent?, responses[], updates[]?, updatesAvailable? }`.
///
/// `updates` is additive: a server without the thesis thread omits it, which
/// reads as an empty thread that cannot take updates — never as an error.
CallDetail callDetailFromJson(Map<String, dynamic> json) {
  final parent = optionalJsonMap(json['parent'], 'CallDetail.parent');
  final entry = callFeedEntryFromJson(
    requireJsonMap(json['entry'], 'CallDetail.entry'),
  );
  final updates = requireJsonList(
    json['updates'],
    'CallDetail.updates',
  ).map(ThesisUpdate.fromJson).toList(growable: false);
  for (final update in updates) {
    if (update.callId != entry.call.id ||
        update.authorUserId != entry.call.userId) {
      throw const CallVocabularyException(
        'A thesis update must belong to this call and its author.',
      );
    }
  }
  return CallDetail(
    entry: entry,
    parent: parent == null ? null : callFeedEntryFromJson(parent),
    responses: requireJsonList(
      json['responses'],
      'CallDetail.responses',
    ).map(CallResponse.fromJson).toList(growable: false),
    updates: [...updates]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    updatesAvailable: requireWireBool(
      json['updatesAvailable'],
      'CallDetail.updatesAvailable',
    ),
  );
}

// ---------------------------------------------------------------------------
// Person detail
// ---------------------------------------------------------------------------

/// `{ person, calls[], viewerIsFollowing, servedAt, followerCount?,
/// followingCount?, record? }`. The last three are additive: absent stays
/// null (unknown), never zero.
PersonDetail personDetailFromJson(Map<String, dynamic> json) {
  final record = optionalJsonMap(json['record'], 'PersonDetail.record');
  return PersonDetail(
    person: personFromJson(
      requireJsonMap(json['person'], 'PersonDetail.person'),
    ),
    calls: callFeedEntriesFromJson(json['calls'], 'PersonDetail.calls'),
    viewerIsFollowing: requireWireBool(
      json['viewerIsFollowing'],
      'PersonDetail.viewerIsFollowing',
    ),
    servedAt: requireWireTimestampMs(
      json['servedAt'],
      'PersonDetail.servedAt',
    ),
    followerCount:
        json['followerCount'] == null
            ? null
            : requireWireCount(
              json['followerCount'],
              'PersonDetail.followerCount',
            ),
    followingCount:
        json['followingCount'] == null
            ? null
            : requireWireCount(
              json['followingCount'],
              'PersonDetail.followingCount',
            ),
    record: record == null ? null : PublicRecord.fromJson(record),
  );
}

// ---------------------------------------------------------------------------
// Challenge invitation
// ---------------------------------------------------------------------------

/// A challenge is a dare to go on record. There is no amount, no escrow and no
/// transaction on this shape, and [ChallengeInvitation.hasEscrow] is
/// structurally false — so a money field on the wire has nowhere to land even
/// if one were ever sent.
ChallengeInvitation challengeInvitationFromJson(
  Map<String, dynamic> json,
) => ChallengeInvitation(
  id: requireWireString(json['id'], 'ChallengeInvitation.id'),
  fromUserId: requireWireString(
    json['fromUserId'],
    'ChallengeInvitation.fromUserId',
  ),
  toUserId: requireWireString(json['toUserId'], 'ChallengeInvitation.toUserId'),
  marketId: requireWireString(json['marketId'], 'ChallengeInvitation.marketId'),
  sourceCallId: requireWireString(
    json['sourceCallId'],
    'ChallengeInvitation.sourceCallId',
  ),
  responseId: requireWireString(
    json['responseId'],
    'ChallengeInvitation.responseId',
  ),
  note: json['note'] as String?,
  createdAt: requireWireTimestampMs(
    json['createdAt'],
    'ChallengeInvitation.createdAt',
  ),
);

List<ChallengeInvitation> challengeInvitationsFromJson(
  Object? value,
  String field,
) => requireJsonList(
  value,
  field,
).map(challengeInvitationFromJson).toList(growable: false);

// ---------------------------------------------------------------------------
// Response result
// ---------------------------------------------------------------------------

/// `{ response, resultingCall?, invitation? }`.
///
/// The contract's own invariant is asserted rather than assumed: `back` and
/// `fade` must come back with the actor's own call, and `challenge` must come
/// back with none. A BFF that drifts here is a correctness bug the user would
/// otherwise see as a call that silently did not happen.
CallResponseResult callResponseResultFromJson(Map<String, dynamic> json) {
  final response = CallResponse.fromJson(
    requireJsonMap(json['response'], 'CallResponseResult.response'),
  );
  final resultingCall = optionalJsonMap(
    json['resultingCall'],
    'CallResponseResult.resultingCall',
  );
  final invitation = optionalJsonMap(
    json['invitation'],
    'CallResponseResult.invitation',
  );

  if (response.kind.createsOwnCall && resultingCall == null) {
    throw CallVocabularyException(
      'A ${response.kind.wire} response must create the actor\'s own call, '
      'but the server returned none.',
    );
  }
  if (!response.kind.createsOwnCall && resultingCall != null) {
    throw const CallVocabularyException(
      'A challenge must create no call for the actor, but the server '
      'returned one.',
    );
  }

  return CallResponseResult(
    response: response,
    resultingCall:
        resultingCall == null ? null : callFeedEntryFromJson(resultingCall),
    invitation:
        invitation == null ? null : challengeInvitationFromJson(invitation),
  );
}

// ---------------------------------------------------------------------------
// Markets list
// ---------------------------------------------------------------------------

List<VenueMarket> venueMarketsFromJson(Object? value, String field) =>
    requireJsonList(
      value,
      field,
    ).map(VenueMarket.fromJson).toList(growable: false);
