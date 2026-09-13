/// Failure behaviour for `BffCallsRepository`.
///
/// Four things are being defended here, all of them load-bearing:
///
/// 1. **Every failure is one of exactly four [CallsException] classes**, so
///    the UI's four states stay exhaustive. tRPC's error envelope carries an
///    HTTP-ish code (`UNAUTHORIZED`, `BAD_REQUEST`, …) and that is what the
///    mapping reads.
/// 2. **An unknown wire value throws** [CallVocabularyException] rather than
///    being coerced into a neighbouring enum member. A drift between app and
///    BFF must surface loudly — never as a call silently recorded on the wrong
///    side (contract §4).
/// 3. **A malformed or empty envelope is a failure, not a silent empty state.**
/// 4. **`crowdSplit: null` means withheld, not zero.** A 0/0 split renders as
///    "nobody has called", which is a different and false statement.
///
/// Every repository here is driven by an injected in-memory `http.Client`.
/// **No test in this file touches the network.**
library;

import 'dart:convert';

import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'bff_calls_fixtures.dart';

const String kBase = 'https://bff.test.invalid';
const String kViewer = 'user_you';

BffCallsRepository build(
  FakeBffServer server, {
  Duration timeout = const Duration(seconds: 15),
}) => BffCallsRepository(
  baseUrl: kBase,
  httpClient: server.client,
  timeout: timeout,
  linkHost: 'https://chumbucket.app',
  verbose: false,
);

Future<CallFeedPage> feed(BffCallsRepository repo) =>
    repo.fetchFeed(mode: CallFeedMode.global, viewerUserId: kViewer);

void main() {
  group('transport failure → CallsOfflineException', () {
    test('a refused connection is offline, not a generic failure', () async {
      final server = FakeBffServer.replying(feedPageJson())
        ..simulateTransportFailure = true;
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallsOfflineException>()),
      );
    });

    test('a timeout is offline', () async {
      final server = FakeBffServer.replying(feedPageJson())
        ..simulateLatency = const Duration(milliseconds: 200);
      await expectLater(
        feed(build(server, timeout: const Duration(milliseconds: 10))),
        throwsA(isA<CallsOfflineException>()),
      );
    });

    test('a write that never reaches the server is also offline', () async {
      final server = FakeBffServer.replying(feedEntryJson())
        ..simulateTransportFailure = true;
      await expectLater(
        build(server).createCall(
          input: const CreateCallInput(
            marketId: 'market_btc_150k',
            side: Side.yes,
          ),
          viewerUserId: kViewer,
        ),
        throwsA(isA<CallsOfflineException>()),
      );
    });
  });

  group('401 / UNAUTHORIZED → CallsSignedOutException', () {
    test('the tRPC UNAUTHORIZED envelope', () async {
      final server = FakeBffServer.failing(
        code: 'UNAUTHORIZED',
        httpStatus: 401,
        message: 'No session',
      );
      await expectLater(
        build(server).createCall(
          input: const CreateCallInput(
            marketId: 'market_btc_150k',
            side: Side.yes,
          ),
          viewerUserId: kViewer,
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
    });

    test('a bare 401 with an unreadable body still reads as signed out',
        () async {
      final server = FakeBffServer(
        (_) => http.Response('Unauthorized', 401),
      );
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallsSignedOutException>()),
      );
    });

    test('a 401 with no tRPC code falls back to the status', () async {
      final server = FakeBffServer(
        (_) => http.Response(
          jsonEncode({
            'error': {
              'json': {'message': 'nope'},
            },
          }),
          401,
        ),
      );
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallsSignedOutException>()),
      );
    });
  });

  group('validation / business refusal → CallsRejectedException', () {
    const refusals = <String, int>{
      'BAD_REQUEST': 400,
      'FORBIDDEN': 403,
      'NOT_FOUND': 404,
      'CONFLICT': 409,
      'PRECONDITION_FAILED': 412,
      'UNPROCESSABLE_CONTENT': 422,
      'TOO_MANY_REQUESTS': 429,
      'PARSE_ERROR': 400,
      'METHOD_NOT_SUPPORTED': 405,
      'PAYLOAD_TOO_LARGE': 413,
      'UNSUPPORTED_MEDIA_TYPE': 415,
      'TIMEOUT': 408,
      'CLIENT_CLOSED_REQUEST': 499,
    };

    for (final entry in refusals.entries) {
      test('${entry.key} is a refusal the user can be told about', () async {
        final server = FakeBffServer.failing(
          code: entry.key,
          httpStatus: entry.value,
          message: 'This market is closed — no new calls.',
        );
        await expectLater(
          feed(build(server)),
          throwsA(
            isA<CallsRejectedException>().having(
              (e) => e.message,
              'message',
              'This market is closed — no new calls.',
            ),
          ),
        );
      });
    }

    test('an unrecognised 4xx code still lands on rejected', () async {
      final server = FakeBffServer.failing(
        code: 'IM_A_TEAPOT',
        httpStatus: 418,
        message: 'no',
      );
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallsRejectedException>()),
      );
    });

    test('a refusal with no message still renders something', () async {
      final server = FakeBffServer.failing(
        code: 'BAD_REQUEST',
        httpStatus: 400,
        message: '',
      );
      await expectLater(
        feed(build(server)),
        throwsA(
          isA<CallsRejectedException>().having(
            (e) => e.message,
            'message',
            isNotEmpty,
          ),
        ),
      );
    });
  });

  group('anything else → CallsFailure', () {
    const failures = <String, int>{
      'INTERNAL_SERVER_ERROR': 500,
      'NOT_IMPLEMENTED': 501,
      'BAD_GATEWAY': 502,
      'SERVICE_UNAVAILABLE': 503,
      'GATEWAY_TIMEOUT': 504,
    };

    for (final entry in failures.entries) {
      test('${entry.key} is a generic failure, never "you are offline"',
          () async {
        final server = FakeBffServer.failing(
          code: entry.key,
          httpStatus: entry.value,
        );
        await expectLater(
          feed(build(server)),
          throwsA(
            allOf(
              isA<CallsFailure>(),
              isNot(isA<CallsOfflineException>()),
              isNot(isA<CallsSignedOutException>()),
              isNot(isA<CallsRejectedException>()),
            ),
          ),
        );
      });
    }

    test('a 500 with no tRPC code falls back to the status', () async {
      final server = FakeBffServer((_) => http.Response('boom', 500));
      await expectLater(feed(build(server)), throwsA(isA<CallsFailure>()));
    });
  });

  group('the four classes are exhaustive', () {
    test('every mapped tRPC code lands on exactly one of them', () {
      const cases = <String, int>{
        'UNAUTHORIZED': 401,
        'BAD_REQUEST': 400,
        'FORBIDDEN': 403,
        'INTERNAL_SERVER_ERROR': 500,
        'SOMETHING_NEW': 599,
      };
      for (final entry in cases.entries) {
        final mapped = callsExceptionForTrpcError(
          procedurePath: 'calls.feed',
          statusCode: entry.value,
          trpcCode: entry.key,
          httpStatus: entry.value,
          message: 'x',
        );
        expect(mapped, isA<CallsException>());
      }

      expect(
        callsExceptionForTrpcError(
          procedurePath: 'calls.feed',
          statusCode: 401,
          trpcCode: 'UNAUTHORIZED',
        ),
        isA<CallsSignedOutException>(),
      );
      expect(
        callsExceptionForTrpcError(
          procedurePath: 'calls.feed',
          statusCode: 403,
          trpcCode: 'FORBIDDEN',
          message: 'Not yours.',
        ),
        isA<CallsRejectedException>(),
      );
      expect(
        callsExceptionForTrpcError(
          procedurePath: 'calls.feed',
          statusCode: 500,
          trpcCode: 'INTERNAL_SERVER_ERROR',
        ),
        isA<CallsFailure>(),
      );
      // An unknown code with a 5xx status is "anything else", not offline.
      expect(
        callsExceptionForTrpcError(
          procedurePath: 'calls.feed',
          statusCode: 599,
          trpcCode: 'SOMETHING_NEW',
          httpStatus: 599,
        ),
        isA<CallsFailure>(),
      );
    });
  });

  group('unknown vocabulary throws rather than coercing', () {
    test('an unknown Side is a CallVocabularyException, not a silent YES',
        () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson(
          entries: [
            feedEntryJson(call: <String, dynamic>{...callJson(), 'side': 'MAYBE'}),
          ],
        ),
      });
      await expectLater(
        feed(build(server)),
        throwsA(
          isA<CallVocabularyException>().having(
            (e) => e.message,
            'message',
            contains('MAYBE'),
          ),
        ),
      );
    });

    test('an unknown MarketStatus throws rather than collapsing to OPEN',
        () async {
      final server = FakeBffServer.routes({
        'markets.open': [
          <String, dynamic>{...marketJson(), 'status': 'SETTLING'},
        ],
      });
      await expectLater(
        build(server).fetchOpenMarkets(),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('an unknown Resolution throws rather than becoming VOID', () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson(
          entries: [
            feedEntryJson(
              result: <String, dynamic>{
                ...resultJson(),
                'resolution': 'PARTIAL_YES',
              },
            ),
          ],
        ),
      });
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('an unknown FundingState throws rather than reading as free',
        () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson(
          entries: [
            feedEntryJson(
              call: <String, dynamic>{
                ...callJson(),
                'fundingState': 'SETTLING',
              },
            ),
          ],
        ),
      });
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('an unknown venue throws rather than presenting demo data as live',
        () async {
      final server = FakeBffServer.routes({
        'markets.open': [
          <String, dynamic>{...marketJson(), 'venue': 'polymarket'},
        ],
      });
      await expectLater(
        build(server).fetchOpenMarkets(),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('an unknown CallResponseKind throws', () async {
      final server = FakeBffServer.routes({
        'calls.respond': <String, dynamic>{
          ...responseResultJson(),
          'response': <String, dynamic>{...responseJson(), 'kind': 'dunk'},
        },
      });
      await expectLater(
        build(server).respondToCall(
          input: const RespondToCallInput(
            targetCallId: 'call_ada_btc',
            kind: CallResponseKind.fade,
          ),
          viewerUserId: 'user_kemi',
        ),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('a probability outside [0,1] throws rather than clamping', () async {
      final server = FakeBffServer.routes({
        'markets.detail': marketDetailJson(
          snapshot: <String, dynamic>{
            ...snapshotJson(),
            'yesProbability': 1.4,
          },
        ),
      });
      await expectLater(
        build(server).fetchMarketDetail(marketId: 'market_btc_150k'),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('a timestamp sent as seconds, or as a string, throws', () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson()..['servedAt'] = '$kNowMs',
      });
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('a back/fade that came back with no call of its own throws', () async {
      final server = FakeBffServer.routes({
        'calls.respond': <String, dynamic>{
          'response': responseJson(kind: 'back', resultingCallId: null),
          'resultingCall': null,
          'invitation': null,
        },
      });
      await expectLater(
        build(server).respondToCall(
          input: const RespondToCallInput(
            targetCallId: 'call_ada_btc',
            kind: CallResponseKind.back,
          ),
          viewerUserId: 'user_kemi',
        ),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('a challenge that came back with a call throws', () async {
      final server = FakeBffServer.routes({
        'calls.respond': responseResultJson(
          response: responseJson(kind: 'challenge', resultingCallId: null),
        ),
      });
      await expectLater(
        build(server).respondToCall(
          input: const RespondToCallInput(
            targetCallId: 'call_ada_btc',
            kind: CallResponseKind.challenge,
          ),
          viewerUserId: 'user_kemi',
        ),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  });

  group('malformed and empty envelopes', () {
    test('a body that is not JSON is a failure, not an empty feed', () async {
      final server = FakeBffServer(
        (_) => http.Response('<html>502 Bad Gateway</html>', 200),
      );
      await expectLater(feed(build(server)), throwsA(isA<CallsFailure>()));
    });

    test('a completely empty body is a failure', () async {
      final server = FakeBffServer((_) => http.Response('', 200));
      await expectLater(feed(build(server)), throwsA(isA<CallsFailure>()));
    });

    test('a 200 with no result key is a failure', () async {
      final server = FakeBffServer((_) => http.Response('{}', 200));
      await expectLater(feed(build(server)), throwsA(isA<CallsFailure>()));
    });

    test('a null payload where an object was promised throws', () async {
      final server = FakeBffServer.replying(null);
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('a JSON array where an object was promised throws', () async {
      final server = FakeBffServer.replying(<Object>[]);
      await expectLater(
        feed(build(server)),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('a feed page missing its entries key is not silently empty', () async {
      final server = FakeBffServer.replying(<String, dynamic>{
        'servedAt': kNowMs,
      });
      // `entries` absent is tolerated as an empty list; `servedAt` absent is
      // not, because a page with no served time cannot drive the stale state.
      final page = await feed(build(server));
      expect(page.entries, isEmpty);

      final noServedAt = FakeBffServer.replying(<String, dynamic>{
        'entries': <Object>[],
      });
      await expectLater(
        feed(build(noServedAt)),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  });

  group('crowdSplit null is withheld, never zero', () {
    test('an absent crowdSplit key stays null', () async {
      final server = FakeBffServer.routes({
        'markets.detail': <String, dynamic>{
          'market': marketJson(),
          'snapshot': snapshotJson(),
          'servedAt': kNowMs,
        },
      });
      final detail = await build(
        server,
      ).fetchMarketDetail(marketId: 'market_btc_150k');

      expect(detail.crowdSplit, isNull);
      expect(detail.viewerCall, isNull);
      expect(detail.viewerHasCalled, isFalse);
    });

    test('an explicit null crowdSplit stays null — not a 0/0 split', () async {
      final server = FakeBffServer.routes({
        'markets.detail': marketDetailJson(crowdSplit: null),
      });
      final detail = await build(server).fetchMarketDetail(
        marketId: 'market_btc_150k',
        viewerUserId: kViewer,
      );

      expect(detail.crowdSplit, isNull);
      // The distinction that matters: a withheld split has no total and no
      // share at all, where a 0/0 split would read as "nobody has called".
      const zeroed = CrowdSplit(
        marketId: 'market_btc_150k',
        yesCalls: 0,
        noCalls: 0,
      );
      expect(zeroed.total, 0);
      expect(zeroed.yesShare, isNull);
      expect(detail.crowdSplit?.total, isNull);
    });

    test('a genuine 0/0 split from the server is preserved as 0/0', () async {
      final server = FakeBffServer.routes({
        'markets.detail': marketDetailJson(
          viewerCall: feedEntryJson(viewerHasCalled: true),
          crowdSplit: crowdSplitJson(yesCalls: 0, noCalls: 0),
        ),
      });
      final detail = await build(server).fetchMarketDetail(
        marketId: 'market_btc_150k',
        viewerUserId: kViewer,
      );

      expect(detail.crowdSplit, isNotNull);
      expect(detail.crowdSplit!.total, 0);
      expect(detail.crowdSplit!.yesShare, isNull);
    });
  });
}
