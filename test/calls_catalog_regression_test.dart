import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';

void main() {
  test(
    'current Polymarket catalog parses and expires locally at the deadline',
    () async {
      var now = kNowMs;
      final server = FakeBffServer.replying([
        {...marketJson(venue: 'polymarket'), 'closesAt': now + 1000},
        {...marketJson(id: 'expired'), 'closesAt': now},
        {...marketJson(id: 'future'), 'opensAt': now + 1000},
      ]);
      final provider = CallsProvider(
        repository: BffCallsRepository(
          baseUrl: 'https://test.invalid',
          httpClient: server.client,
        ),
        clock: () => DateTime.fromMillisecondsSinceEpoch(now),
      );
      await provider.loadOpenMarkets();
      expect(provider.openMarkets, hasLength(1));
      expect(provider.openMarkets.single.venue, MarketVenue.polymarket);
      now += 1000;
      expect(provider.openMarkets.map((m) => m.id), ['future']);
      expect(server.received, hasLength(1));
      provider.dispose();
    },
  );

  test(
    'venue schema drift produces a visible error, not an empty successful catalog',
    () async {
      final server = FakeBffServer.replying([
        marketJson(venue: 'unknown-venue'),
      ]);
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
