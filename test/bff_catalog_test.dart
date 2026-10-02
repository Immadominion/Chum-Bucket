import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'bff_calls_fixtures.dart';

void main() {
  test(
    'catalog consumes every cached page and does not ask for crypto or prices',
    () async {
      final server = FakeBffServer(
        (request) => okResponse({
          'markets': [
            marketJson(
              id: request.input['cursor'] == null ? 'a' : 'b',
              venue: 'panta',
            ),
          ],
          'nextCursor': request.input['cursor'] == null ? 'a' : null,
        }),
      );
      final repo = BffCallsRepository(
        baseUrl: 'https://bff.test.invalid',
        httpClient: server.client,
      );
      final markets = await repo.fetchMarketCatalog();
      expect(markets.map((m) => m.id), ['a', 'b']);
      expect(server.received.map((r) => r.procedurePath).toSet(), {
        'predictions.catalog',
      });
      // The open slice, soonest to close first; never a crypto-only cut.
      expect(server.received.first.input, {
        'limit': 100,
        'scope': 'open',
        'sort': 'closing',
      });
      expect(server.received.last.input, {
        'limit': 100,
        'scope': 'open',
        'sort': 'closing',
        'cursor': 'a',
      });
    },
  );
  test(
    'broken cursors fail instead of returning a deceptively complete catalog',
    () async {
      final server = FakeBffServer.replying({
        'markets': [],
        'nextCursor': 'same',
      });
      final repo = BffCallsRepository(
        baseUrl: 'https://bff.test.invalid',
        httpClient: server.client,
      );
      await expectLater(
        repo.fetchMarketCatalog(),
        throwsA(isA<CallVocabularyException>()),
      );
      expect(server.received, hasLength(2));
    },
  );
  test('other live venues cannot enter Panta discovery', () async {
    final server = FakeBffServer.replying({
      'markets': [marketJson(venue: 'jupiter')],
      'nextCursor': null,
    });
    final repo = BffCallsRepository(
      baseUrl: 'https://bff.test.invalid',
      httpClient: server.client,
    );
    await expectLater(
      repo.fetchMarketCatalog(),
      throwsA(isA<CallVocabularyException>()),
    );
  });
  test(
    'an older BFF that refuses the open scope still yields its whole catalog',
    () async {
      final server = FakeBffServer((request) {
        if (request.input.containsKey('scope')) {
          return errorResponse(
            code: 'BAD_REQUEST',
            httpStatus: 400,
            message: 'Unrecognized key(s) in object',
            path: 'predictions.catalog',
          );
        }
        return okResponse({
          'markets': [marketJson(id: 'legacy', venue: 'panta')],
          'nextCursor': null,
        });
      });
      final repo = BffCallsRepository(
        baseUrl: 'https://bff.test.invalid',
        httpClient: server.client,
      );
      final markets = await repo.fetchMarketCatalog();
      expect(markets.map((m) => m.id), ['legacy']);
      expect(server.received.map((r) => r.input).toList(), [
        {'limit': 100, 'scope': 'open', 'sort': 'closing'},
        {'limit': 100},
      ]);
    },
  );
  test('a server failure is not mistaken for an older BFF', () async {
    final server = FakeBffServer.failing(
      code: 'BAD_GATEWAY',
      httpStatus: 502,
      message: 'Panta read failed',
    );
    final repo = BffCallsRepository(
      baseUrl: 'https://bff.test.invalid',
      httpClient: server.client,
    );
    await expectLater(repo.fetchMarketCatalog(), throwsA(isA<CallsFailure>()));
    expect(server.received, hasLength(1));
  });
  test(
    "Panta's reported volume is kept verbatim; anything else is unavailable",
    () async {
      final server = FakeBffServer.replying({
        'markets': [
          {...marketJson(id: 'busy', venue: 'panta'), 'volumeUsdc': '1200.50'},
          {...marketJson(id: 'quiet', venue: 'panta'), 'volumeUsdc': null},
          {...marketJson(id: 'odd', venue: 'panta'), 'volumeUsdc': 12},
          {...marketJson(id: 'neg', venue: 'panta'), 'volumeUsdc': '-3'},
          marketJson(id: 'old', venue: 'panta'),
        ],
        'nextCursor': null,
      });
      final repo = BffCallsRepository(
        baseUrl: 'https://bff.test.invalid',
        httpClient: server.client,
      );
      final markets = {
        for (final m in await repo.fetchMarketCatalog()) m.id: m.volumeUsdc,
      };
      expect(markets, {
        'busy': '1200.50',
        'quiet': null,
        'odd': null,
        'neg': null,
        'old': null,
      });
    },
  );
  test('malformed catalog is an error, not an empty market list', () async {
    final server = FakeBffServer.replying({'nextCursor': null});
    final repo = BffCallsRepository(
      baseUrl: 'https://bff.test.invalid',
      httpClient: server.client,
    );
    await expectLater(
      repo.fetchMarketCatalog(),
      throwsA(isA<CallVocabularyException>()),
    );
  });
}
