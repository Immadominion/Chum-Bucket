/// Shared fixtures for the `BffCallsRepository` tests.
///
/// **No test in this suite may open a socket.** Every repository under test is
/// constructed with [FakeBffServer.client], an in-memory `http.Client` that
/// records what was sent and replies with a canned tRPC envelope. If a test
/// ever hit the network it would be flaky, slow, and would silently pass
/// against a server nobody is running.
///
/// The payloads below are the FROZEN §3 shapes verbatim
/// (`docs/contracts/pivot-contracts-v1.md`), with realistic values rather than
/// `"x"` placeholders, so a drift in a field name or a timestamp unit fails
/// here rather than in production.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Fake transport
// ---------------------------------------------------------------------------

/// One request the repository actually sent.
class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.url,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  /// The tRPC procedure path, e.g. `calls.feed`.
  String get procedurePath => url.pathSegments.last;

  /// The raw `{"json": …}` envelope, from the query string for a GET and from
  /// the body for a POST.
  Map<String, dynamic> get envelope {
    final raw = method == 'GET' ? url.queryParameters['input'] : body;
    if (raw == null || raw.isEmpty) return const {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  /// The procedure input — what is inside the `json` key.
  Map<String, dynamic> get input {
    final json = envelope['json'];
    return json is Map<String, dynamic> ? json : const {};
  }
}

/// An in-memory tRPC server.
class FakeBffServer {
  FakeBffServer(this.handler);

  /// Replies to every procedure with the same success payload.
  factory FakeBffServer.replying(Object? data) =>
      FakeBffServer((_) => okResponse(data));

  /// Routes by procedure path; an unrouted path is a NOT_FOUND, which is what
  /// a real tRPC server does.
  factory FakeBffServer.routes(Map<String, Object?> byProcedure) =>
      FakeBffServer((request) {
        if (!byProcedure.containsKey(request.procedurePath)) {
          return errorResponse(
            code: 'NOT_FOUND',
            httpStatus: 404,
            message: 'No procedure "${request.procedurePath}"',
          );
        }
        return okResponse(byProcedure[request.procedurePath]);
      });

  /// Replies to every procedure with the same tRPC error envelope.
  factory FakeBffServer.failing({
    required String code,
    required int httpStatus,
    String message = 'refused',
  }) => FakeBffServer(
    (_) => errorResponse(code: code, httpStatus: httpStatus, message: message),
  );

  final http.Response Function(RecordedRequest request) handler;

  /// Every request the repository sent, in order.
  final List<RecordedRequest> received = <RecordedRequest>[];

  /// Set to make the client fail the way a dead network does.
  bool simulateTransportFailure = false;

  /// Set to make the client hang past the repository's timeout.
  Duration? simulateLatency;

  late final http.Client client = MockClient((request) async {
    final recorded = RecordedRequest(
      method: request.method,
      url: request.url,
      headers: Map<String, String>.from(request.headers),
      body: request.body,
    );
    received.add(recorded);
    if (simulateTransportFailure) {
      throw http.ClientException('Connection refused', request.url);
    }
    final latency = simulateLatency;
    if (latency != null) await Future<void>.delayed(latency);
    return handler(recorded);
  });

  RecordedRequest get lastRequest => received.last;

  RecordedRequest requestFor(String procedurePath) =>
      received.firstWhere((r) => r.procedurePath == procedurePath);
}

/// `{"result":{"data":{"json": … }}}` — the superjson-wrapped success envelope.
http.Response okResponse(Object? data) => http.Response(
  jsonEncode({
    'result': {
      'data': {'json': data},
    },
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// A success envelope that was *not* superjson-wrapped. The transport must
/// fall back to the raw `data`, exactly as `_decodeTrpcResponse` does.
http.Response okResponseUnwrapped(Object? data) => http.Response(
  jsonEncode({
    'result': {'data': data},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// `{"error":{"json":{"message":…,"data":{"code":…,"httpStatus":…}}}}` — the
/// shape tRPC actually emits.
http.Response errorResponse({
  required String code,
  required int httpStatus,
  String message = 'refused',
  String path = 'calls.feed',
}) => http.Response(
  jsonEncode({
    'error': {
      'json': {
        'message': message,
        'code': -32600,
        'data': {'code': code, 'httpStatus': httpStatus, 'path': path},
      },
    },
  }),
  httpStatus,
  headers: {'content-type': 'application/json'},
);

// ---------------------------------------------------------------------------
// Timestamps — unix milliseconds, integer, UTC. Never a string, never seconds.
// ---------------------------------------------------------------------------

/// 13 September 2026, 12:00:00 UTC.
const int kNowMs = 1789214400000;

const int kMinute = 60 * 1000;
const int kHour = 60 * kMinute;
const int kDay = 24 * kHour;

// ---------------------------------------------------------------------------
// FROZEN §3 payloads
// ---------------------------------------------------------------------------

Map<String, dynamic> marketJson({
  String id = 'market_btc_150k',
  String venue = 'jupiter',
  String status = 'OPEN',
  String rawStatus = 'active',
}) => <String, dynamic>{
  'id': id,
  'venue': venue,
  'venueEventId': 'evt_btc_eoy',
  'venueMarketId': 'jup:btc-above-150000-2026-12-31',
  'question': r'Will BTC trade above $150,000 before 31 Dec 2026?',
  'rulesText':
      'This market resolves YES if the Coinbase BTC-USD spot price prints at '
      'or above 150,000.00 USD at any point before 23:59 UTC on 31 Dec 2026, '
      'as recorded by the Coinbase Exchange public trade feed. Wicks count.',
  'category': 'crypto',
  'outcomes': <Map<String, dynamic>>[
    {'side': 'YES', 'label': 'Yes — it prints 150k'},
    {'side': 'NO', 'label': 'No — it never gets there'},
  ],
  'status': status,
  'rawStatus': rawStatus,
  'opensAt': kNowMs - 90 * kDay,
  'closesAt': kNowMs + 40 * kDay,
  'resolvesAt': kNowMs + 41 * kDay,
  'resolutionSource': 'Coinbase Exchange BTC-USD public trade feed',
  'lastSyncedAt': kNowMs - 2 * kMinute,
  'payloadVersion': 1,
};

Map<String, dynamic> snapshotJson({
  String id = 'snap_btc_1',
  String marketId = 'market_btc_150k',
  double yesProbability = 0.38,
  String source = 'venue',
}) => <String, dynamic>{
  'id': id,
  'marketId': marketId,
  'yesProbability': yesProbability,
  'observedAt': kNowMs - 2 * kMinute,
  'source': source,
};

Map<String, dynamic> personJson({
  String id = 'user_ada',
  String handle = 'ada',
  String displayName = 'Ada Okafor',
  String? walletAddress = '7xKXtg2CW3Mock1AdaWa11etAddre55F0rDem0Use',
  int settledCalls = 31,
  int correctCalls = 19,
}) => <String, dynamic>{
  'id': id,
  'handle': handle,
  'displayName': displayName,
  'avatarUrl': null,
  'walletAddress': walletAddress,
  'settledCalls': settledCalls,
  'correctCalls': correctCalls,
};

Map<String, dynamic> callJson({
  String id = 'call_ada_btc',
  String userId = 'user_ada',
  String marketId = 'market_btc_150k',
  String side = 'YES',
  double? confidence = 0.7,
  String? thesis =
      'Supply on exchanges keeps falling while the ETF bid is steady.',
  double? entryProbability = 0.36,
  String? snapshotId = 'snap_btc_1',
  String visibility = 'public',
  String? parentCallId,
  String fundingState = 'NONE',
}) => <String, dynamic>{
  'id': id,
  'userId': userId,
  'marketId': marketId,
  'side': side,
  'confidence': confidence,
  'thesis': thesis,
  'entryProbability': entryProbability,
  'snapshotId': snapshotId,
  'visibility': visibility,
  'createdAt': kNowMs - 3 * kHour,
  'lockedAt': kNowMs - 3 * kHour,
  'parentCallId': parentCallId,
  'fundingState': fundingState,
};

Map<String, dynamic> resultJson({
  String callId = 'call_you_fed',
  String outcome = 'CORRECT',
  String? resolution = 'YES',
  String? marketResolutionId = 'res_fomc_sep_2026',
}) => <String, dynamic>{
  'callId': callId,
  'outcome': outcome,
  'resolution': resolution,
  'resolvedAt': resolution == null ? null : kNowMs - 5 * kDay,
  'marketResolutionId': marketResolutionId,
  'derivedAt': kNowMs - 5 * kDay,
};

Map<String, dynamic> feedEntryJson({
  Map<String, dynamic>? call,
  Map<String, dynamic>? author,
  Map<String, dynamic>? market,
  Map<String, dynamic>? result,
  int backCount = 2,
  int fadeCount = 1,
  bool viewerHasCalled = false,
}) => <String, dynamic>{
  'call': call ?? callJson(),
  'author': author ?? personJson(),
  'market': market ?? marketJson(),
  'result': result,
  'backCount': backCount,
  'fadeCount': fadeCount,
  'viewerHasCalled': viewerHasCalled,
};

Map<String, dynamic> feedPageJson({
  List<Map<String, dynamic>>? entries,
  String? nextCursor = '20',
}) => <String, dynamic>{
  'entries': entries ?? <Map<String, dynamic>>[feedEntryJson()],
  'nextCursor': nextCursor,
  'servedAt': kNowMs,
};

/// Sentinel meaning "leave the fixture's default in place".
///
/// Needed because `null` is a *meaningful* value for several of these fields —
/// a market with no snapshot and a withheld crowd split are both states the UI
/// must render — so `x ?? default` would quietly make them untestable.
const Object kKeepDefault = Object();

Map<String, dynamic>? _override(Object? value, Map<String, dynamic> fallback) =>
    identical(value, kKeepDefault) ? fallback : value as Map<String, dynamic>?;

Map<String, dynamic> marketDetailJson({
  Map<String, dynamic>? market,
  Object? snapshot = kKeepDefault,
  Map<String, dynamic>? viewerCall,
  Map<String, dynamic>? crowdSplit,
}) => <String, dynamic>{
  'market': market ?? marketJson(),
  'snapshot': _override(snapshot, snapshotJson()),
  'viewerCall': viewerCall,
  'crowdSplit': crowdSplit,
  'servedAt': kNowMs,
};

Map<String, dynamic> crowdSplitJson({
  String marketId = 'market_btc_150k',
  int yesCalls = 14,
  int noCalls = 9,
}) => <String, dynamic>{
  'marketId': marketId,
  'yesCalls': yesCalls,
  'noCalls': noCalls,
};

Map<String, dynamic> responseJson({
  String id = 'response_kemi_fade',
  String actorUserId = 'user_kemi',
  String targetCallId = 'call_ada_btc',
  String kind = 'fade',
  String? resultingCallId = 'call_kemi_btc_fade',
}) => <String, dynamic>{
  'id': id,
  'actorUserId': actorUserId,
  'targetCallId': targetCallId,
  'kind': kind,
  'resultingCallId': resultingCallId,
  'createdAt': kNowMs - 2 * kHour,
};

Map<String, dynamic> callDetailJson({
  Map<String, dynamic>? entry,
  Object? parent = kKeepDefault,
  List<Map<String, dynamic>>? responses,
}) => <String, dynamic>{
  'entry':
      entry ??
      feedEntryJson(
        call: callJson(
          id: 'call_kemi_btc_fade',
          userId: 'user_kemi',
          side: 'NO',
          parentCallId: 'call_ada_btc',
          thesis: 'Faded. The ETF bid is already in the price.',
        ),
        author: personJson(
          id: 'user_kemi',
          handle: 'kemi',
          displayName: 'Kemi Balogun',
          walletAddress: null,
          settledCalls: 12,
          correctCalls: 8,
        ),
      ),
  'parent': _override(parent, feedEntryJson()),
  'responses': responses ?? <Map<String, dynamic>>[responseJson()],
};

Map<String, dynamic> personDetailJson({
  Map<String, dynamic>? person,
  List<Map<String, dynamic>>? calls,
}) => <String, dynamic>{
  'person': person ?? personJson(),
  'calls': calls ?? <Map<String, dynamic>>[feedEntryJson()],
  'servedAt': kNowMs,
};

Map<String, dynamic> invitationJson({
  String id = 'invite_zed_you',
  String fromUserId = 'user_zed',
  String toUserId = 'user_you',
  String? note = 'Rematch. Go on record on BTC.',
}) => <String, dynamic>{
  'id': id,
  'fromUserId': fromUserId,
  'toUserId': toUserId,
  'marketId': 'market_btc_150k',
  'sourceCallId': 'call_you_fed',
  'responseId': 'response_zed_challenge',
  'note': note,
  'createdAt': kNowMs - 4 * kDay,
};

Map<String, dynamic> responseResultJson({
  Map<String, dynamic>? response,
  Map<String, dynamic>? resultingCall,
  Map<String, dynamic>? invitation,
}) => <String, dynamic>{
  'response': response ?? responseJson(),
  'resultingCall':
      resultingCall ??
      feedEntryJson(
        call: callJson(
          id: 'call_kemi_btc_fade',
          userId: 'user_kemi',
          side: 'NO',
          parentCallId: 'call_ada_btc',
        ),
        author: personJson(
          id: 'user_kemi',
          handle: 'kemi',
          displayName: 'Kemi Balogun',
          walletAddress: null,
        ),
        viewerHasCalled: true,
      ),
  'invitation': invitation,
};

// ---------------------------------------------------------------------------
// Money guard
// ---------------------------------------------------------------------------

/// Any key that would mean this loop had started to carry money, a credential
/// or an on-chain artefact. A call is free and is not a trade (contract §0
/// invariant 1), so none of these may ever appear in a request this client
/// sends.
const Set<String> kForbiddenRequestKeys = <String>{
  'amount',
  'amountbaseunits',
  'stake',
  'stakebaseunits',
  'escrow',
  'wager',
  'bet',
  'price',
  'fee',
  'lamports',
  'mint',
  'currency',
  'token',
  'usdc',
  'sol',
  'balance',
  'wallet',
  'walletaddress',
  'signature',
  'txsignature',
  'transaction',
  'quote',
  'order',
};

/// Every key in a JSON tree, lower-cased, including nested objects and arrays.
Set<String> collectJsonKeys(Object? node) {
  final keys = <String>{};
  void walk(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        keys.add(entry.key.toString().toLowerCase());
        walk(entry.value);
      }
    } else if (value is List) {
      value.forEach(walk);
    }
  }

  walk(node);
  return keys;
}
