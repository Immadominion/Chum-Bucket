// Opt-in captures of market discovery — the Markets tab, its filter sheet,
// state screens, market detail and the market picker — with the real fonts
// and synthetic data, at 390dp and at 320dp with twice the text. Writes
// nothing unless asked:
//
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_MARKETS=/abs/output/dir \
//   test/ui_markets_capture_test.dart
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_picker_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/chumbucket_bottom_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'onboarding_fakes.dart' show loadBrandFonts;
import 'ui_market_layout_discovery_test.dart' show CatalogRepository, market;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outDir = String.fromEnvironment('CAPTURE_MARKETS');

  setUpAll(() async {
    if (outDir.isEmpty) return;
    await loadBrandFonts();
  });

  SharePriceSnapshot quote(String id, String? yes, String? no) =>
      SharePriceSnapshot(
        id: 'capture-$id',
        marketId: id,
        yesPrice: yes,
        noPrice: no,
        observedAt: DateTime.now().millisecondsSinceEpoch,
      );

  VenueMarket withVolume(VenueMarket m, String volume) =>
      VenueMarket.fromJson({...m.toJson(), 'volumeUsdc': volume});

  List<VenueMarket> catalog() => [
    market(
      'JUMP',
      const Duration(hours: 5),
      question: r'Will the $JUMP token sale exceed $35m by the deadline?',
    ),
    withVolume(
      market(
        'BTC',
        const Duration(days: 2, hours: 3),
        question: r'Will BTC close above $90,000 on Friday?',
      ),
      '1200',
    ),
    market(
      'NFL',
      const Duration(hours: 30),
      category: 'sports',
      question:
          'Over 38.5 combined score in the Steelers vs. Browns game on '
          'Thursday?',
    ),
    market(
      'BBN',
      const Duration(days: 3),
      category: 'pop-culture',
      question: 'Will a female housemate win BBNaija this season?',
    ),
    market(
      'GTA',
      const Duration(days: 49),
      category: 'gaming',
      question: 'Will GTA 6 release on November 19th?',
    ),
  ];

  Map<String, SharePriceSnapshot> prices() => {
    'JUMP': quote('JUMP', '0.31', '0.71'),
    'BTC': quote('BTC', '0.620000000000000001', '0.430000000000000001'),
    'NFL': quote('NFL', '0.502247129', '0.497752871'),
    'BBN': quote('BBN', '0.44', null),
  };

  Future<void> pumpScene(
    WidgetTester tester,
    CallsProvider provider,
    Widget child, {
    required double width,
    required double scale,
    double height = 844,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Above the app, as in main.dart, so sheets (their own routes) see it.
    await tester.pumpWidget(
      ChangeNotifierProvider<CallsProvider>.value(
        value: provider,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: Scaffold(
                  backgroundColor: AppColors.background,
                  body: child,
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        await precacheImage(image.image, element);
      }
    });
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(Uri.file('$outDir/markets-$name.png')),
    );
  }

  Widget tab() => Stack(
    children: [
      CallMarketsScreen(embedded: true, onActivityTap: () {}),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: ChumbucketBottomNavigation(selectedIndex: 1, onSelected: (_) {}),
      ),
    ],
  );

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    final size = '${width.toInt()}-${scale.toInt()}x';

    testWidgets('list $size', (tester) async {
      final provider = CallsProvider(
        repository: CatalogRepository(catalog(), prices: prices()),
      );
      addTearDown(provider.dispose);
      await pumpScene(tester, provider, tab(), width: width, scale: scale);
      expect(tester.takeException(), isNull);
      await shot(tester, 'list-$size');
    }, skip: outDir.isEmpty);

    testWidgets('filters $size', (tester) async {
      final provider = CallsProvider(
        repository: CatalogRepository(catalog(), prices: prices()),
      );
      addTearDown(provider.dispose);
      await pumpScene(tester, provider, tab(), width: width, scale: scale);
      await tester.tap(find.byKey(const ValueKey('market-filters-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This week'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crypto'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shot(tester, 'filter-sheet-$size');
      await tester.tap(find.text('Show markets'));
      await tester.pumpAndSettle();
      await shot(tester, 'filtered-$size');
    }, skip: outDir.isEmpty);

    testWidgets('no match $size', (tester) async {
      final provider = CallsProvider(
        repository: CatalogRepository(catalog(), prices: prices()),
      );
      addTearDown(provider.dispose);
      await pumpScene(tester, provider, tab(), width: width, scale: scale);
      await tester.enterText(find.byType(TextField), 'elections');
      await tester.pumpAndSettle();
      await shot(tester, 'no-match-$size');
    }, skip: outDir.isEmpty);

    testWidgets('error $size', (tester) async {
      final repo = CatalogRepository([])..simulateFailure = true;
      final provider = CallsProvider(repository: repo);
      addTearDown(provider.dispose);
      await pumpScene(tester, provider, tab(), width: width, scale: scale);
      await shot(tester, 'error-$size');
    }, skip: outDir.isEmpty);

    testWidgets('detail $size', (tester) async {
      final markets = catalog();
      final provider = CallsProvider(
        repository: CatalogRepository(markets, prices: prices()),
      );
      addTearDown(provider.dispose);
      await pumpScene(
        tester,
        provider,
        MarketDetailScreen(marketId: markets[1].id),
        width: width,
        scale: scale,
        height: scale > 1 ? 1300 : 844,
      );
      expect(tester.takeException(), isNull);
      await shot(tester, 'detail-$size');
      await tester.tap(find.text('Rules & details'));
      await tester.pumpAndSettle();
      await shot(tester, 'detail-rules-$size');
    }, skip: outDir.isEmpty);

    testWidgets('picker $size', (tester) async {
      final provider = CallsProvider(
        repository: CatalogRepository(catalog(), prices: prices()),
      )..setViewer('capture-person');
      addTearDown(provider.dispose);
      await pumpScene(
        tester,
        provider,
        Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed: () => showMarketPickerSheet(context: context),
                  child: const Text('open'),
                ),
              ),
        ),
        width: width,
        scale: scale,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await shot(tester, 'picker-$size');
    }, skip: outDir.isEmpty);
  }
}
