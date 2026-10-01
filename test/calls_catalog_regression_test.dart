import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';

void main() {
  test('Panta catalog parses and expires locally at the deadline', () async {
    var now = kNowMs;
    final server = FakeBffServer.replying({
      'markets': [
        {...marketJson(venue: 'panta'), 'closesAt': now + 1000},
        {...marketJson(id: 'expired', venue: 'panta'), 'closesAt': now},
        {...marketJson(id: 'future', venue: 'panta'), 'opensAt': now + 1000},
      ],
      'nextCursor': null,
    });
    final provider = CallsProvider(
      repository: BffCallsRepository(
        baseUrl: 'https://test.invalid',
        httpClient: server.client,
      ),
      clock: () => DateTime.fromMillisecondsSinceEpoch(now),
    );
    await provider.loadOpenMarkets();
    expect(provider.openMarkets, hasLength(1));
    expect(provider.openMarkets.single.venue, MarketVenue.panta);
    now += 1000;
    expect(provider.openMarkets.map((m) => m.id), ['future']);
    expect(server.received, hasLength(1));
    provider.dispose();
  });

  test(
    'venue schema drift produces a visible error, not an empty successful catalog',
    () async {
      final server = FakeBffServer.replying({
        'markets': [marketJson(venue: 'unknown-venue')],
        'nextCursor': null,
      });
      final provider = CallsProvider(
        repository: BffCallsRepository(
          baseUrl: 'https://test.invalid',
          httpClient: server.client,
        ),
      );
      await provider.loadOpenMarkets();
      expect(provider.openMarkets, isEmpty);
      expect(provider.isLoadingOpenMarkets, isFalse);
      expect(provider.openMarketsError, contains('format changed'));
      provider.dispose();
    },
  );
}
