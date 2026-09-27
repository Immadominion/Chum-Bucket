import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'live public catalog decodes through the shipped repository',
    () async {
      final repository = BffCallsRepository();
      final markets = await repository.fetchOpenMarkets(category: 'crypto');
      expect(markets, isNotEmpty);
      final current = markets.where(
        (m) =>
            m.closesAt != null &&
            m.closesAt! > DateTime.now().millisecondsSinceEpoch,
      );
      expect(current, isNotEmpty);
      final detail = await repository.fetchMarketDetail(
        marketId: current.first.id,
      );
      expect(detail.market.id, current.first.id);
      expect(detail.snapshot, isNotNull);
      expect(detail.crowdSplit, isNull);
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_READS'),
  );
}
