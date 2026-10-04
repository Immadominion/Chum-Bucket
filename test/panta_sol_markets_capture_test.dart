// Opt-in: renders the screens SOL-quoted Panta markets touch — the Markets
// tab with a mixed USDC/SOL catalog, a SOL market's detail, and the author's
// own call on a SOL market (no trade offered), and the composer on a SOL
// market — at 390dp and 320dp/2x text.
//
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_SOL_MARKETS=true \
//   --dart-define=CAPTURE_DIR=/path/to/dir \
//   test/panta_sol_markets_capture_test.dart
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_fakes.dart' show loadBrandFonts;
import 'panta_sol_markets_test.dart' show PantaOwnCallRepository;
import 'ui_market_layout_discovery_test.dart'
    show CatalogRepository, market, mount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CAPTURE_SOL_MARKETS');
  const dir = String.fromEnvironment('CAPTURE_DIR', defaultValue: '/tmp');

  setUpAll(() async {
    if (enabled) await loadBrandFonts();
  });

  VenueMarket sol(VenueMarket m) => VenueMarket.fromJson({
    ...m.toJson(),
    'payloadVersion': 2,
    'quoteCurrency': 'SOL',
    'tradable': false,
  });
  VenueMarket usdc(VenueMarket m) => VenueMarket.fromJson({
    ...m.toJson(),
    'quoteCurrency': 'USDC',
    'tradable': true,
  });
  SharePriceSnapshot quote(String id, String yes, String no, ShareCurrency c) =>
      SharePriceSnapshot(
        id: 'capture-$id',
        marketId: id,
        yesPrice: yes,
        noPrice: no,
        observedAt: DateTime.now().millisecondsSinceEpoch,
        currency: c,
      );

  final markets = [
    usdc(
      market(
        'TRAM',
        const Duration(hours: 21),
        category: 'pop-culture',
        question: 'Will Tram finish in the Top 3 of BBNaija Season 11?',
      ),
    ),
    usdc(
      market(
        'FRA',
        const Duration(hours: 42),
        category: 'sports',
        question:
            'France will concede in the first 25 minutes against Belgium on '
            'the 05 October.',
      ),
    ),
    sol(
      market(
        'HYPE',
        const Duration(days: 87),
        question: r'Will HYPE reach $100 by December 31, 2026?',
      ),
    ),
    sol(
      market(
        'OBI',
        const Duration(days: 239),
        category: 'politics',
        question:
            'Will Peter Obi be Elected President of Nigeria in the 2027 '
            'Presidential Election?',
      ),
    ),
  ];
  final prices = {
    'TRAM': quote('TRAM', '0.5', '0.5', ShareCurrency.usdc),
    'FRA': quote('FRA', '0.501445429', '0.498554571', ShareCurrency.usdc),
    'HYPE': quote('HYPE', '0.671739755', '0.328260245', ShareCurrency.sol),
    'OBI': quote('OBI', '0.382192122', '0.617807878', ShareCurrency.sol),
  };

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    final tag = '${width.toInt()}-${scale.toInt()}x';
    testWidgets('markets tab, mixed USDC and SOL ($tag)', (tester) async {
      final provider = CallsProvider(
        repository: CatalogRepository(markets, prices: prices),
      );
      addTearDown(provider.dispose);
      await mount(
        tester,
        provider,
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: ColoredBox(
            color: const Color(0xFFF4F4F4),
            child: CallMarketsScreen(embedded: true, onActivityTap: () {}),
          ),
        ),
        width: width,
        scale: scale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(Uri.file('$dir/sol-markets-tab-$tag.png')),
      );
    }, skip: !enabled);

    testWidgets('SOL market detail ($tag)', (tester) async {
      final provider = CallsProvider(
        repository: CatalogRepository(markets, prices: prices),
      );
      addTearDown(provider.dispose);
      await mount(
        tester,
        provider,
        const RepaintBoundary(
          key: ValueKey('capture'),
          child: MarketDetailScreen(marketId: 'HYPE'),
        ),
        width: width,
        scale: scale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(Uri.file('$dir/sol-market-detail-$tag.png')),
      );
    }, skip: !enabled);

    testWidgets('composer on a SOL market ($tag)', (tester) async {
      final provider = CallsProvider(
        repository: CatalogRepository(markets, prices: prices),
      )..setViewer(PantaOwnCallRepository.viewer);
      addTearDown(provider.dispose);
      await mount(
        tester,
        provider,
        RepaintBoundary(
          key: const ValueKey('capture'),
          child: ColoredBox(
            color: Colors.white,
            child: CallComposerSheet(
              market: markets[2],
              sharePrice: prices['HYPE'],
              initialSide: Side.yes,
            ),
          ),
        ),
        width: width,
        scale: scale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(Uri.file('$dir/sol-composer-$tag.png')),
      );
    }, skip: !enabled);

    testWidgets('own call on a SOL market, no trade ($tag)', (tester) async {
      final provider = CallsProvider(
        repository: PantaOwnCallRepository(quote: 'SOL', tradable: false),
      )..setViewer(PantaOwnCallRepository.viewer);
      addTearDown(provider.dispose);
      await mount(
        tester,
        provider,
        const RepaintBoundary(
          key: ValueKey('capture'),
          child: CallDetailScreen(callId: 'call_you_fed'),
        ),
        width: width,
        scale: scale,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const ValueKey('capture')),
        matchesGoldenFile(Uri.file('$dir/sol-own-call-$tag.png')),
      );
    }, skip: !enabled);
  }
}
