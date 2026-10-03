/// The real [CallsRepository]: the Bun/tRPC BFF behind the same seam
/// `MockCallsRepository` sits behind.
///
/// Swapping `MockCallsRepository()` for `BffCallsRepository()` in the one
/// place the provider is constructed (`lib/main.dart`, see
/// `docs/contracts/integration-requests/packet-c.md` §1) is the entire
/// migration. Nothing above `calls_repository.dart` changes, because nothing
/// above it knows a wire shape (contract §4).
///
/// ## The procedure surface
///
/// Exactly the §5 table of `integration-requests/packet-c.md`, whose payloads
/// are the FROZEN §3 shapes verbatim:
///
/// | Method | Procedure | Kind |
/// | --- | --- | --- |
/// | `fetchFeed` | `calls.feed` | query |
/// | `fetchOpenMarkets` | `markets.open` | query |
/// | `fetchMarketDetail` | `markets.detail` | query |
/// | `fetchCall` | `calls.get` | query |
/// | `fetchPerson` | `people.get` | query |
/// | `createCall` | `calls.create` | mutation |
/// | `respondToCall` | `calls.respond` | mutation |
/// | `fetchInvitations` | `calls.invitations` | query |
/// | `setFollowing` | `people.follow` / `people.unfollow` | mutation |
///
/// And the people layer ([PeopleRepository]), additive on the same BFF:
///
/// | Method | Procedure | Kind |
/// | --- | --- | --- |
/// | `fetchLeaderboard` | `people.leaderboard` | query |
/// | `searchPeople` | `people.search` | query |
/// | `fetchFollowing` | `people.following` | query |
/// | `fetchTopCalls` | `calls.top` | query |
/// | `appendThesisUpdate` | `calls.addUpdate` | mutation |
///
/// ## Identity
///
/// **`viewerUserId` is never sent.** The §5 inputs carry no viewer field, and
/// that is deliberate: contract §8 finding 4 records that "several tRPC read
/// procedures take `wallet: z.string()` on `publicProcedure` with no proof at
/// all" as a live security defect. A client-supplied identity is a claim, not
/// a credential. The session token ([CallsBffAuthTokenProvider]) is what the
/// server authorises on; `viewerUserId` is used here only to decide, locally
/// and before any request is sent, whether a **write** may be attempted at all.
///
/// Reading never requires a session. Only writing does.
///
/// ## Money
///
/// No method on this class sends an amount, a stake, an escrow, a wallet or a
/// signature, and no response shape has anywhere to put one. A call is not a
/// trade (contract §0 invariant 1).
library;

import 'package:http/http.dart' as http;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_repository.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';

class BffCallsRepository
    implements
        CallsRepository,
        CallsCatalogRepository,
        PeopleRepository,
        PeopleSuggestionsRepository {
  /// [httpClient] is the test seam: inject one and no socket is ever opened.
  /// [authToken] supplies the session; returning null simply means signed out.
  BffCallsRepository({
    CallsBffTransport? transport,
    String? baseUrl,
    http.Client? httpClient,
    CallsBffAuthTokenProvider? authToken,
    Duration timeout = const Duration(seconds: 15),
    String? linkHost,
    bool verbose = true,
  }) : _transport =
           transport ??
           CallsBffTransport(
             baseUrl: baseUrl,
             httpClient: httpClient,
             authToken: authToken,
             timeout: timeout,
             verbose: verbose,
           ),
       _linkHost = normalizeCallsBffBaseUrl(linkHost ?? resolveCallsLinkHost());

  final CallsBffTransport _transport;
  final String _linkHost;

  // --- Procedure paths, §5 -------------------------------------------------

  static const String feedProcedure = 'calls.feed';
  static const String openMarketsProcedure = 'markets.open';
  static const String marketDetailProcedure = 'markets.detail';
  static const String callProcedure = 'calls.get';
  static const String personProcedure = 'people.get';
  static const String followProcedure = 'people.follow';
  static const String unfollowProcedure = 'people.unfollow';
  static const String createCallProcedure = 'calls.create';
  static const String respondProcedure = 'calls.respond';
  static const String invitationsProcedure = 'calls.invitations';
  static const String leaderboardProcedure = 'people.leaderboard';
  static const String searchPeopleProcedure = 'people.search';
  static const String followingProcedure = 'people.following';
  static const String topCallsProcedure = 'calls.top';
  static const String suggestedPeopleProcedure = 'people.suggested';
  static const String addUpdateProcedure = 'calls.addUpdate';

  /// Where this repository is pointed. Useful in a debug screen; never a
  /// hardcoded host.
  String get baseUrl => _transport.baseUrl;

  // -------------------------------------------------------------------------
  // Reads — never require a session
  // -------------------------------------------------------------------------

  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) async {
    // `viewerUserId` is intentionally absent from the input: the server reads
    // the viewer from the session, so `viewerHasCalled` and the `following`
    // mode cannot be spoofed by a client that simply names someone else.
    final data = await _transport.query(feedProcedure, {
      'mode': mode.name,
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    });
    return callFeedPageFromJson(requireJsonMap(data, '$feedProcedure result'));
  }

  @override
  Future<List<VenueMarket>> fetchOpenMarkets({String? category}) async {
    final data = await _transport.query(openMarketsProcedure, {
      if (category != null) 'category': category,
    });
    return venueMarketsFromJson(data, '$openMarketsProcedure result');
  }

  static const String catalogProcedure = 'predictions.catalog';

  /// The whole open Panta catalog, soonest to close first. Discovery only:
  /// no price is required here, and call eligibility stays a server decision.
  @override
  Future<List<VenueMarket>> fetchMarketCatalog() async {
    try {
      return await _walkCatalog(const {'scope': 'open', 'sort': 'closing'});
    } on CallsRejectedException {
      // A BFF older than the open-scope catalog refuses unknown input keys
      // (its schema is strict). Its legacy walk returns every mirrored row,
      // which the provider still narrows to markets open right now.
      return _walkCatalog(const {});
    }
  }

  Future<List<VenueMarket>> _walkCatalog(Map<String, Object> options) async {
    final markets = <String, VenueMarket>{};
    final seen = <String>{};
    String? cursor;
    // Bounded traversal of cheap, cached BFF pages; no client provider key.
    for (var page = 0; page < 20; page++) {
      final data = requireJsonMap(
        await _transport.query(catalogProcedure, {
          'limit': 100,
          ...options,
          if (cursor != null) 'cursor': cursor,
        }),
        catalogProcedure,
      );
      if (data['markets'] is! List) {
        throw const CallVocabularyException(
          'Catalog markets must be an array.',
        );
      }
      for (final market in venueMarketsFromJson(
        data['markets'],
        'catalog.markets',
      )) {
        if (market.venue != MarketVenue.panta && !market.venue.isDemo) {
          throw const CallVocabularyException('Unexpected live catalog venue.');
        }
        markets[market.id] = market;
      }
      final next = data['nextCursor'];
      if (next == null) return markets.values.toList(growable: false);
      if (next is! String || next.isEmpty || !seen.add(next)) {
        throw const CallVocabularyException('Invalid catalog pagination.');
      }
      cursor = next;
    }
    throw const CallsFailure(
      'The market catalog is too large to load right now. Please try again.',
    );
  }

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async {
    final data = await _transport.query(marketDetailProcedure, {
      'marketId': marketId,
    });
    // `crowdSplit` arrives null until the viewer has a locked call on this
    // market (§5.1). Null stays null — the UI must render "withheld", never a
    // 0/0 split, which would read as "nobody has called".
    return marketDetailFromJson(
      requireJsonMap(data, '$marketDetailProcedure result'),
    );
  }

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async {
    final data = await _transport.query(callProcedure, {'callId': callId});
    return callDetailFromJson(requireJsonMap(data, '$callProcedure result'));
  }

  @override
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  }) async {
    final data = await _transport.query(personProcedure, {
      'personRef': _normalizePersonRef(personRef),
    });
    return personDetailFromJson(
      requireJsonMap(data, '$personProcedure result'),
    );
  }

  @override
  Future<bool> setFollowing({
    required String personId,
    required bool following,
    required String? viewerUserId,
  }) async {
    _requireViewer(viewerUserId);
    final data = await _transport.mutate(
      following ? followProcedure : unfollowProcedure,
      {'personRef': personId},
    );
    final state = requireJsonMap(data, 'people follow result');
    if (state['personId'] != personId || state['following'] != following) {
      throw const CallVocabularyException(
        'people follow result disagrees with the request',
      );
    }
    return following;
  }

  /// `@ada` and `ada` are the same person. Mirrors `MockCallsRepository`.
  static String _normalizePersonRef(String personRef) {
    final trimmed = personRef.trim();
    return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
  }

  // -------------------------------------------------------------------------
  // Writes — always require a session
  // -------------------------------------------------------------------------

  @override
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  }) async {
    _requireViewer(viewerUserId);

    // The client-side mirror of the server rule, checked first so an obviously
    // invalid composer payload never leaves the device. The server checks it
    // again; this one is for latency, not for trust.
    final invalid = input.validate();
    if (invalid != null) throw CallsRejectedException(invalid);

    // `CreateCallInput.toJson()` verbatim, per §5. Note what is absent: no
    // amount, no wallet, no signature, and no userId.
    final data = await _transport.mutate(createCallProcedure, input.toJson());
    return callFeedEntryFromJson(
      requireJsonMap(data, '$createCallProcedure result'),
    );
  }

  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) async {
    _requireViewer(viewerUserId);

    if (input.thesis != null && input.thesis!.length > kThesisMaxLength) {
      throw const CallsRejectedException(
        'Keep your thesis to $kThesisMaxLength characters.',
      );
    }

    final data = await _transport.mutate(respondProcedure, input.toJson());
    return callResponseResultFromJson(
      requireJsonMap(data, '$respondProcedure result'),
    );
  }

  @override
  Future<List<ChallengeInvitation>> fetchInvitations({
    required String? viewerUserId,
  }) async {
    // Matches `MockCallsRepository`: signed out means "no invitations", not an
    // error — the invitations strip simply has nothing to show. Returning here
    // also means a signed-out app never fires a request that could only 401.
    if (viewerUserId == null || viewerUserId.isEmpty) return const [];

    final data = await _transport.query(invitationsProcedure, const {});
    return challengeInvitationsFromJson(data, '$invitationsProcedure result');
  }

  static void _requireViewer(String? viewerUserId) {
    if (viewerUserId == null || viewerUserId.isEmpty) {
      throw const CallsSignedOutException();
    }
  }

  // -------------------------------------------------------------------------
  // The people layer
  // -------------------------------------------------------------------------
  //
  // These paths are newer than the original surface. A server that has not
  // been updated answers tRPC's own NOT_FOUND, which is a deployment fact,
  // not a refusal to show a person verbatim. tRPC words it two ways:
  //   No procedure found on path "people.leaderboard"    (path unknown: what
  //                                                       an older deploy says)
  //   No "query"-procedure on path "people.leaderboard"  (wrong procedure type)
  static final RegExp _missingProcedure = RegExp(
    r'\bno (?:"\w+"-)?procedure (?:found )?on path\b',
    caseSensitive: false,
  );

  static Future<T> _people<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on CallsRejectedException catch (e) {
      if (_missingProcedure.hasMatch(e.message)) {
        throw const CallsFailure(
          "This isn't available on the server yet. Please try again later.",
        );
      }
      rethrow;
    }
  }

  @override
  Future<Leaderboard> fetchLeaderboard({
    required LeaderboardWindow window,
    int limit = 50,
  }) => _people(() async {
    final data = await _transport.query(leaderboardProcedure, {
      'window': window.wire,
      'limit': limit,
    });
    final board = Leaderboard.fromJson(
      requireJsonMap(data, '$leaderboardProcedure result'),
    );
    if (board.window != window) {
      throw const CallVocabularyException(
        'The leaderboard answered for a different window.',
      );
    }
    return board;
  });

  @override
  Future<List<PersonCard>> searchPeople(String query, {int limit = 20}) =>
      _people(() async {
        final trimmed = query.trim();
        // The server refuses an empty query; there is nothing to ask for.
        if (trimmed.isEmpty) return const <PersonCard>[];
        final data = await _transport.query(searchPeopleProcedure, {
          'query': trimmed.length > 64 ? trimmed.substring(0, 64) : trimmed,
          'limit': limit,
        });
        return personCardsFromJson(
          requireJsonMap(data, '$searchPeopleProcedure result')['people'],
          '$searchPeopleProcedure.people',
        );
      });

  @override
  Future<List<PersonCard>> fetchFollowing() => _people(() async {
    final data = await _transport.query(followingProcedure, const {});
    return personCardsFromJson(
      requireJsonMap(data, '$followingProcedure result')['people'],
      '$followingProcedure.people',
    );
  });

  @override
  Future<List<TopCall>> fetchTopCalls({int limit = 10}) => _people(() async {
    final data = await _transport.query(topCallsProcedure, {'limit': limit});
    return topCallsFromJson(requireJsonMap(data, '$topCallsProcedure result'));
  });

  /// `people.suggested`. A server without it raises
  /// [PeopleSuggestionsUnavailable]: the caller composes from deployed reads.
  @override
  Future<PeopleSuggestions> fetchSuggestedPeople({int limit = 10}) async {
    try {
      final data = await _transport.query(suggestedPeopleProcedure, {
        'limit': limit.clamp(1, 20),
      });
      return PeopleSuggestions.fromJson(
        requireJsonMap(data, '$suggestedPeopleProcedure result'),
      );
    } on CallsRejectedException catch (e) {
      if (_missingProcedure.hasMatch(e.message)) {
        throw const PeopleSuggestionsUnavailable();
      }
      rethrow;
    }
  }

  @override
  Future<ThesisUpdate> appendThesisUpdate({
    required String callId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw const CallsRejectedException(
        'Write something before posting an update.',
      );
    }
    if (trimmed.length > kThesisMaxLength) {
      throw const CallsRejectedException(
        'Keep an update to $kThesisMaxLength characters.',
      );
    }
    final data = await _people(
      () => _transport.mutate(addUpdateProcedure, {
        'callId': callId,
        'body': trimmed,
      }),
    );
    final update = ThesisUpdate.fromJson(
      requireJsonMap(data, '$addUpdateProcedure result'),
    );
    if (update.callId != callId) {
      throw const CallVocabularyException(
        'The update was recorded against a different call.',
      );
    }
    return update;
  }

  // -------------------------------------------------------------------------
  // Links
  // -------------------------------------------------------------------------
  //
  // Not a procedure — these are pure string building against a configured
  // host, which is why the interface keeps them here rather than in a screen.
  // The shapes match `parseCallDeepLink` in `call_deep_link.dart`.

  @override
  String shareLinkForCall(String callId) => '$_linkHost/c/$callId';

  @override
  String shareLinkForPerson(String handleOrId) =>
      '$_linkHost/u/${_normalizePersonRef(handleOrId)}';

  /// Releases the HTTP client, if this repository created it.
  void close() => _transport.close();
}
