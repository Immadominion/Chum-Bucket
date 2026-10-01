import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
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
      expect(server.received.first.input, {'limit': 100});
      expect(server.received.last.input, {'limit': 100, 'cursor': 'a'});
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
