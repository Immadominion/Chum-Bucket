// Opt-in real Flutter widget captures. Run with:
// flutter test --no-pub --update-goldens --dart-define=CAPTURE_MARKET_LAYOUT=true test/ui_market_layout_visual_test.dart
// Output is local /tmp review evidence, not production assets or live data.
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/chumbucket_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'ui_market_layout_discovery_test.dart' show CatalogRepository, market;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CAPTURE_MARKET_LAYOUT');

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
      (
        'Montserrat',
        [
          'assets/fonts/Montserrat/Montserrat-Regular.ttf',
          'assets/fonts/Montserrat/Montserrat-Medium.ttf',
        ],
      ),
      (
        'Montserrat_regular',
        ['assets/fonts/Montserrat/Montserrat-Regular.ttf'],
      ),
      ('Montserrat_medium', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  for (final scene in ['markets', 'detail']) {
    for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
      testWidgets('capture $scene at $width dp / $scale text', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final btc = market(
          'BTC',
          const Duration(hours: 12),
          question: 'Will BTC close above the published threshold on Friday?',
        );
        final eth = market(
          'ETH',
          const Duration(hours: 28),
          question: 'Will ETH close above the published threshold tomorrow?',
        );
        final sol = market(
          'SOL',
          const Duration(hours: 38),
          question: 'Will SOL close above the published threshold this week?',
        );
        final provider = CallsProvider(
          repository: CatalogRepository(
            [btc, eth, sol],
            prices: {
              for (final m in [btc, eth, sol])
                m.id: SharePriceSnapshot(
                  id: 'synthetic-capture-price',
                  marketId: m.id,
                  yesPrice: '0.62',
                  noPrice: '0.43',
                  observedAt: DateTime.now().millisecondsSinceEpoch,
                ),
            },
          ),
        );
        addTearDown(provider.dispose);
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, _) => MaterialApp(
                  theme: AppTheme.lightTheme,
                  builder:
                      (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!,
                      ),
                  home: ChangeNotifierProvider<CallsProvider>.value(
                    value: provider,
                    child: RepaintBoundary(
                      key: const ValueKey('market-capture'),
                      child: Scaffold(
                        backgroundColor: AppColors.background,
                        body: Column(
                          children: [
                            const ColoredBox(
                              color: AppColors.primaryContainer,
                              child: SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: EdgeInsets.all(6),
                                  child: Text(
                                    'WIDGET TEST · SYNTHETIC DATA',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 12,
                                      color: AppColors.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child:
                                  scene == 'markets'
                                      ? Stack(
                                        children: [
                                          CallMarketsScreen(
                                            embedded: true,
                                            onActivityTap: () {},
                                          ),
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: ChumbucketBottomNavigation(
                                              selectedIndex: 1,
                                              onSelected: (_) {},
                                            ),
                                          ),
                                        ],
                                      )
                                      : MarketDetailScreen(marketId: btc.id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final path =
            '/tmp/chum-ui-$scene-${width.toInt()}-${scale.toInt()}x.png';
        await expectLater(
          find.byKey(const ValueKey('market-capture')),
          matchesGoldenFile(Uri.file(path)),
        );
        await tester.pumpWidget(const SizedBox());
      }, skip: !enabled);
    }
  }
}
