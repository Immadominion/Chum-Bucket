// Opt-in: renders the Markets tab with the live catalog's kind of content
// (long venue questions, raw venue prices) so it can be compared with Codex's
// layout prototype in docs/design/2026-09-30-chumbucket-layout.
//
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_MARKETS_REFERENCE=true \
//   test/ui_markets_reference_capture_test.dart
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'ui_market_layout_discovery_test.dart'
    show CatalogRepository, market, mount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CAPTURE_MARKETS_REFERENCE');

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final (family, paths) in [
      (
        'PPNeueMachina',
        [
          'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
          'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
        ],
      ),
      ('Montserrat_regular', ['assets/fonts/Montserrat/Montserrat-Regular.ttf']),
      ('Montserrat_500', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  SharePriceSnapshot quote(String id, String yes, String no) =>
      SharePriceSnapshot(
        id: 'capture-$id',
        marketId: id,
        yesPrice: yes,
        noPrice: no,
        observedAt: DateTime.now().millisecondsSinceEpoch,
      );

  testWidgets('markets tab with live-shaped catalog content', (tester) async {
    final markets = [
      market(
        'OIL',
        const Duration(hours: 6),
        category: 'finance',
        question:
            'Will ICE Brent Crude Oil Futures (December 2026 Contract) settle '
            r'at or above $104.00 per barrel on Thursday, October 1, 2026, at '
            '6:30 PM BST?',
      ),
      market(
        'NFL',
        const Duration(hours: 16),
        category: 'sports',
        question:
            'Over 38.5 combined score in the Pittsburgh Steelers vs. Cleveland '
            'Browns game on Thursday, October 1, 2026?',
      ),
      market(
        'JUMP',
        const Duration(hours: 30),
        question:
            r'Will the target in the $JUMP token sale exceed $35m by the '
            'october 2 deadline?',
      ),
      market(
        'BTC',
        const Duration(days: 2),
        question: r'Will BTC close above $90,000 on Friday?',
      ),
    ];
    final provider = CallsProvider(
      repository: CatalogRepository(
        markets,
        prices: {
          'OIL': quote('OIL', '0.500096044', '0.499903956'),
          'NFL': quote('NFL', '0.502247129', '0.497752871'),
          'JUMP': quote('JUMP', '0.31', '0.71'),
          'BTC': quote('BTC', '0.620000000000000001', '0.430000000000000001'),
        },
      ),
    );
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      RepaintBoundary(
        key: const ValueKey('markets-capture'),
        child: ColoredBox(
          color: const Color(0xFFF4F4F4),
          child: CallMarketsScreen(embedded: true, onActivityTap: () {}),
        ),
      ),
      width: 400,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('markets-capture')),
      matchesGoldenFile(Uri.file('/tmp/chum-markets-400.png')),
    );
  }, skip: !enabled);

  testWidgets('market detail with live-shaped content', (tester) async {
    final m = market(
      'NFL',
      const Duration(hours: 16),
      category: 'sports',
      question:
          'Over 38.5 combined score in the Pittsburgh Steelers vs. Cleveland '
          'Browns game on Thursday, October 1, 2026?',
    );
    final provider = CallsProvider(
      repository: CatalogRepository(
        [m],
        prices: {'NFL': quote('NFL', '0.502247129', '0.497752871')},
      ),
    );
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      RepaintBoundary(
        key: const ValueKey('detail-capture'),
        child: MarketDetailScreen(marketId: m.id),
      ),
      width: 400,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('detail-capture')),
      matchesGoldenFile(Uri.file('/tmp/chum-detail-400.png')),
    );
  }, skip: !enabled);
}
