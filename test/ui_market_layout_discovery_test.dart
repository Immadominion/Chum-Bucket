import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_picker_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

VenueMarket market(
  String id,
  Duration untilClose, {
  MarketVenue venue = MarketVenue.panta,
  MarketStatus status = MarketStatus.open,
  String? question,
  String category = 'crypto',
}) => VenueMarket(
  id: id,
  venue: venue,
  venueEventId: 'test-event',
  venueMarketId: 'test-venue-$id',
  question: question ?? 'Will $id close above the exact test threshold?',
  rulesText:
      'Exact test rules. Only the named closing observation counts.\n\nAn earlier price spike does not count.',
  category: category,
  outcomes: const [
    MarketOutcome(side: Side.yes, label: 'YES'),
    MarketOutcome(side: Side.no, label: 'NO'),
  ],
  status: status,
  rawStatus: status.wire,
  opensAt: null,
  closesAt: DateTime.now().add(untilClose).millisecondsSinceEpoch,
  resolvesAt:
      DateTime.now()
          .add(untilClose + const Duration(hours: 1))
          .millisecondsSinceEpoch,
  resolutionSource: 'Test source · official closing observation',
  lastSyncedAt: DateTime.now().millisecondsSinceEpoch,
  payloadVersion: 1,
);

SharePriceSnapshot price(
  String id, {
  String? no = '0.430000000000000001',
  bool stale = false,
}) => SharePriceSnapshot(
  id: 'test-price',
  marketId: id,
  yesPrice: '0.620000000000000001',
  noPrice: no,
  observedAt:
      DateTime.now()
          .subtract(stale ? const Duration(hours: 2) : Duration.zero)
          .millisecondsSinceEpoch,
);

class CatalogRepository extends MockCallsRepository {
  CatalogRepository(
    this.markets, {
    this.prices = const {},
    this.crowd,
    this.wait = Duration.zero,
  });
  final List<VenueMarket> markets;
  final Map<String, SharePriceSnapshot> prices;
  final CrowdSplit? crowd;
  final Duration wait;
  int reads = 0;

  @override
  Future<List<VenueMarket>> fetchOpenMarkets({String? category}) async {
    await Future<void>.delayed(wait);
    if (simulateOffline) throw const CallsOfflineException();
    if (simulateFailure) {
      throw const CallsRejectedException('Could not load test catalog.');
    }
    return markets;
  }

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async {
    reads++;
    return MarketDetail(
      market: markets.firstWhere((m) => m.id == marketId),
      snapshot: null,
      sharePrice: prices[marketId],
      servedAt: DateTime.now().millisecondsSinceEpoch,
      crowdSplit: crowd,
    );
  }
}

Future<void> mount(
  WidgetTester tester,
  CallsProvider provider,
  Widget child, {
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
              child: Scaffold(body: child),
            ),
          ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable:
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'time filters are optional discovery filters, never call eligibility',
    () {
      final now = DateTime.now();
      final markets = [
        market('soon', const Duration(hours: 12)),
        market('week', const Duration(days: 4)),
        market('too-fast', const Duration(hours: 1)),
        market('too-long', const Duration(days: 8)),
        market(
          'closed',
          const Duration(hours: 12),
          status: MarketStatus.closedPendingResolution,
        ),
        market('other', const Duration(hours: 12), venue: MarketVenue.jupiter),
      ];
      expect(
        discoveryMarkets(
          markets,
          window: MarketDiscoveryWindow.endingSoon,
          now: now,
        ).map((m) => m.id),
        ['too-fast', 'soon'],
      );
      expect(
        discoveryMarkets(
          markets,
          window: MarketDiscoveryWindow.thisWeek,
          now: now,
        ).map((m) => m.id),
        ['too-fast', 'soon', 'week'],
      );
      expect(
        discoveryMarkets(
          markets,
          window: MarketDiscoveryWindow.all,
          now: now,
        ).map((m) => m.id),
        ['too-fast', 'soon', 'week', 'too-long'],
      );
      final sports = market(
        'sport',
        const Duration(days: 30),
        category: 'sports',
      );
      expect(discoveryMarkets([sports], window: MarketDiscoveryWindow.all), [
        sports,
      ]);
      expect(
        discoveryMarkets(
          [sports],
          window: MarketDiscoveryWindow.all,
          category: 'crypto',
        ),
        isEmpty,
      );
    },
  );

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'embedded catalog $width dp / $scale text preserves prices and nav room',
        (tester) async {
          final m = market('BTC', const Duration(hours: 12));
          final repo = CatalogRepository([m], prices: {m.id: price(m.id)});
          final provider = CallsProvider(repository: repo);
          addTearDown(provider.dispose);
          var activity = 0;
          await mount(
            tester,
            provider,
            CallMarketsScreen(embedded: true, onActivityTap: () => activity++),
            width: width,
            scale: scale,
          );
          expect(find.text('Markets'), findsOneWidget);
          expect(find.text('Saved'), findsNothing);
          // Chips are drawn at 40 or 32dp; each still takes 48dp of touch.
          final filters = find.byType(OutlinedButton);
          expect(filters, findsWidgets);
          for (final filter in filters.evaluate()) {
            expect(
              tester.getSize(find.byWidget(filter.widget)).height,
              greaterThanOrEqualTo(48),
            );
          }
          await tester.tap(find.byTooltip('Activity'));
          expect(activity, 1);
          // Rows read at two decimals; the exact venue strings are on detail.
          await reveal(tester, find.text('0.62'));
          expect(find.text('0.43'), findsOneWidget);
          expect(find.text('0.620000000000000001'), findsNothing);
          expect(repo.reads, 1);
          expect(tester.takeException(), isNull);
          final padding =
              tester
                      .widgetList<SliverPadding>(find.byType(SliverPadding))
                      .last
                      .padding
                  as EdgeInsets;
          expect(padding.bottom, greaterThanOrEqualTo(128));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('search and time filters change actual markets', (tester) async {
    final provider = CallsProvider(
      repository: CatalogRepository([
        market('BTC', const Duration(hours: 12)),
        market('ETH', const Duration(days: 4)),
      ]),
    );
    addTearDown(provider.dispose);
    await mount(tester, provider, const CallMarketsScreen());
    expect(find.textContaining('Will BTC'), findsOneWidget);
    await tester.tap(find.text('Ending soon'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Will ETH'), findsNothing);
    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'eTh');
    await tester.pumpAndSettle();
    expect(find.textContaining('Will ETH'), findsOneWidget);
    expect(find.textContaining('Will BTC'), findsNothing);
    await tester.enterText(find.byType(TextField), 'not a market');
    await tester.pumpAndSettle();
    expect(find.text('No matching questions'), findsOneWidget);
  });

  for (final picker in [false, true]) {
    testWidgets('Panta attribution and units appear once (picker=$picker)', (
      tester,
    ) async {
      final markets = [
        market('BTC', const Duration(hours: 12), question: 'Will BTC rise?'),
        market('ETH', const Duration(hours: 13), question: 'Will ETH rise?'),
      ];
      final provider = CallsProvider(repository: CatalogRepository(markets))
        ..setViewer('test-person');
      addTearDown(provider.dispose);
      await mount(
        tester,
        provider,
        picker ? const MarketPickerSheet() : const CallMarketsScreen(),
      );
      expect(find.textContaining('Powered by Panta'), findsOneWidget);
      expect(find.textContaining('Prices in USDC/share'), findsOneWidget);
      expect(find.byType(CallMarketCard), findsNWidgets(2));
      for (final card in find.byType(CallMarketCard).evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(card.widget),
            matching: find.textContaining('Powered by Panta'),
          ),
          findsNothing,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'compact row keeps its complete question, exact price and units',
    (tester) async {
      final m = market(
        'BTC',
        const Duration(hours: 12),
        question: 'Will BTC rise?',
      );
      final provider = CallsProvider(repository: CatalogRepository([m]));
      addTearDown(provider.dispose);
      var opened = false;
      await mount(
        tester,
        provider,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: CallMarketCard(
            market: m,
            sharePrice: SharePriceSnapshot(
              id: 'compact-test',
              marketId: m.id,
              yesPrice: '0.62',
              noPrice: '0.43',
              observedAt: DateTime.now().millisecondsSinceEpoch,
            ),
            onTap: () => opened = true,
          ),
        ),
      );
      final rowSize = tester.getSize(find.byType(CallMarketCard));
      // A one-line question at the prototype's spacing (18dp padding, 14dp
      // to the price cells) is 131dp.
      expect(rowSize.height, lessThanOrEqualTo(140));
      expect(rowSize.height, greaterThanOrEqualTo(48));
      final question = tester.widget<Text>(find.text(m.question));
      expect(question.maxLines, isNull);
      expect(question.overflow, isNot(TextOverflow.ellipsis));
      expect(
        tester.widget<Text>(find.text('0.62')).semanticsLabel,
        '0.62 USDC per share, indicative',
      );
      expect(find.textContaining('Powered by Panta'), findsNothing);
      await tester.tap(find.byType(CallMarketCard));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long compact-row question is never clipped at 320dp / 2x', (
    tester,
  ) async {
    final m = market(
      'OIL',
      const Duration(hours: 12),
      question:
          'Will ICE Brent Crude Oil Futures (December 2026 Contract) settle at or above '
          r'$104.00 per barrel on Thursday, October 1, 2026, at 6:30 PM BST?',
    );
    final provider = CallsProvider(repository: CatalogRepository([m]));
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      SingleChildScrollView(
        child: CallMarketCard(market: m, sharePrice: price(m.id), onTap: () {}),
      ),
      width: 320,
      scale: 2,
    );
    final question = tester.widget<Text>(find.text(m.question));
    expect(question.maxLines, isNull);
    expect(question.overflow, isNot(TextOverflow.ellipsis));
    await reveal(tester, find.text('0.43'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing side stays unavailable; stale price stays labelled', (
    tester,
  ) async {
    final m = market('BTC', const Duration(hours: 12));
    final provider = CallsProvider(repository: CatalogRepository([m]));
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      SingleChildScrollView(
        child: CallMarketCard(
          market: m,
          sharePrice: price(m.id, no: null, stale: true),
          onTap: () {},
        ),
      ),
      width: 320,
      scale: 2,
    );
    expect(find.text('Price unavailable'), findsOneWidget);
    expect(find.textContaining('Last updated'), findsOneWidget);
    expect(find.text('0.38'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('market detail exposes exact rules and withholds ungated crowd', (
    tester,
  ) async {
    final m = market('BTC', const Duration(hours: 12));
    final provider = CallsProvider(
      repository: CatalogRepository(
        [m],
        prices: {m.id: price(m.id)},
        crowd: CrowdSplit(marketId: m.id, yesCalls: 100, noCalls: 2),
      ),
    );
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      MarketDetailScreen(marketId: m.id),
      width: 320,
      scale: 2,
    );
    expect(find.text('Make a call'), findsOneWidget);
    // Detail reads at two decimals and states the venue's exact figures.
    expect(find.text('0.62'), findsOneWidget);
    expect(
      find.text('Exact: YES 0.620000000000000001 · NO 0.430000000000000001'),
      findsOneWidget,
    );
    final trade = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Trade'),
    );
    expect(trade.onPressed, isNull);
    expect(find.textContaining('existing call'), findsOneWidget);
    await reveal(tester, find.text('Read the full market rules'));
    await tester.tap(find.text('Read the full market rules'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      m.rulesText,
    );
    expect(find.text('Community opinion'), findsNothing);
    expect(find.textContaining('100 calls'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expired open status cannot offer a new call or declare a result',
    (tester) async {
      final m = market('past', const Duration(hours: -1));
      final provider = CallsProvider(repository: CatalogRepository([m]));
      addTearDown(provider.dispose);
      await mount(tester, provider, MarketDetailScreen(marketId: m.id));
      final call = tester.widget<ChumbucketPrimaryButton>(
        find.widgetWithText(ChumbucketPrimaryButton, 'Make a call'),
      );
      expect(call.onPressed, isNull);
      expect(find.text('Closed · awaiting result'), findsWidgets);
      expect(find.text('Resolved'), findsNothing);
    },
  );

  testWidgets('picker scrolls at 320dp and 2x and keeps demo visible', (
    tester,
  ) async {
    final m = market(
      'demo',
      const Duration(hours: 12),
      venue: MarketVenue.fixture,
    );
    final provider = CallsProvider(repository: CatalogRepository([m]))
      ..setViewer('test-person');
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      const MarketPickerSheet(),
      width: 320,
      scale: 2,
    );
    await reveal(tester, find.textContaining('DEMO DATA'));
    expect(find.textContaining('No live share prices'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final offline in [true, false]) {
    testWidgets(
      'catalog failure has explicit retry at large text (offline=$offline)',
      (tester) async {
        final repo =
            CatalogRepository([])
              ..simulateOffline = offline
              ..simulateFailure = !offline;
        final provider = CallsProvider(repository: repo);
        addTearDown(provider.dispose);
        await mount(
          tester,
          provider,
          const CallMarketsScreen(),
          width: 320,
          scale: 2,
        );
        await reveal(tester, find.text('Try again'));
        expect(
          find.text(offline ? "You're offline" : "That didn't load"),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  // ── The whole open catalog: real categories, search, sort, honest counts ──

  VenueMarket withVolume(VenueMarket m, String? volume) =>
      VenueMarket.fromJson({...m.toJson(), 'volumeUsdc': volume});

  // Category chips share one horizontally scrolling row.
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  String firstCard(WidgetTester tester) =>
      tester
          .widget<CallMarketCard>(find.byType(CallMarketCard).first)
          .market
          .id;

  // Today's open Panta catalog has exactly this shape (2026-10-02): six open
  // markets across crypto, pop-culture, sports and gaming.
  List<VenueMarket> liveShapedCatalog() => [
    market(
      'jump',
      const Duration(hours: 1),
      question: r'Will the $JUMP sale exceed $35m?',
    ),
    market(
      'bbn',
      const Duration(hours: 57),
      category: 'pop-culture',
      question: 'Will a female housemate win BBNaija?',
    ),
    market(
      'tram',
      const Duration(hours: 58),
      category: 'pop-culture',
      question: 'Will Tram finish top 3?',
    ),
    market(
      'mufc',
      const Duration(days: 8),
      category: 'sports',
      question: 'Will Manchester United beat Spurs by 2+?',
    ),
    market(
      'gta',
      const Duration(days: 49),
      category: 'gaming',
      question: 'Will GTA 6 release on November 19th?',
    ),
    market(
      'btc',
      const Duration(days: 89),
      question: r'Will bitcoin hit $100,000 by 31 Dec 2026?',
    ),
  ];

  test('category chips come from the open markets themselves', () {
    final now = DateTime.now();
    final markets = [
      ...liveShapedCatalog(),
      market('ended', const Duration(hours: -1), category: 'commodities'),
      market(
        'closed',
        const Duration(days: 2),
        category: 'weather',
        status: MarketStatus.closedPendingResolution,
      ),
      market(
        'foreign',
        const Duration(days: 2),
        category: 'politics',
        venue: MarketVenue.jupiter,
      ),
    ];
    expect(discoveryCategories(markets, now: now), [
      (category: 'crypto', count: 2),
      (category: 'pop-culture', count: 2),
      (category: 'gaming', count: 1),
      (category: 'sports', count: 1),
    ]);
    expect(marketCategoryLabel('pop-culture'), 'Pop culture');
    expect(marketCategoryLabel('meme-coins'), 'Meme coins');
    expect(marketCategoryLabel('CRYPTO'), 'Crypto');
    expect(
      discoveryMarkets(
        markets,
        window: MarketDiscoveryWindow.all,
        category: 'Pop-Culture',
        now: now,
      ).map((m) => m.id),
      ['bbn', 'tram'],
    );
  });

  test('search covers question and category across the whole catalog', () {
    final markets = liveShapedCatalog();
    List<String> search(String q) =>
        discoveryMarkets(
          markets,
          window: MarketDiscoveryWindow.all,
          query: q,
        ).map((m) => m.id).toList();
    expect(search('pop culture'), ['bbn', 'tram']);
    expect(search('  GAMING '), ['gta']);
    expect(search('spurs'), ['mufc']);
    expect(search(r'$100,000'), ['btc']);
    expect(search('nothing like this'), isEmpty);
  });

  test('most active orders by venue-reported volume only, unreported last', () {
    final now = DateTime.now();
    final markets = [
      withVolume(market('quiet', const Duration(hours: 2)), '0.00'),
      withVolume(market('busy', const Duration(days: 3)), '1200.50'),
      market('unknown', const Duration(hours: 1)),
      withVolume(market('mid', const Duration(days: 1)), '75'),
    ];
    expect(
      discoveryMarkets(
        markets,
        window: MarketDiscoveryWindow.all,
        sort: MarketDiscoverySort.mostActive,
        now: now,
      ).map((m) => m.id),
      ['busy', 'mid', 'quiet', 'unknown'],
    );
    expect(
      discoveryMarkets(
        markets,
        window: MarketDiscoveryWindow.all,
        now: now,
      ).map((m) => m.id),
      ['unknown', 'quiet', 'mid', 'busy'],
    );
    expect(discoveryHasActivity(markets, now: now), isTrue);
    expect(
      discoveryHasActivity([
        withVolume(market('z', const Duration(hours: 2)), '0'),
        market('n', const Duration(hours: 2)),
      ], now: now),
      isFalse,
    );
    expect(
      discoveryCountLabel(shown: 6, open: 6),
      '6 open markets · soonest to close first',
    );
    expect(
      discoveryCountLabel(
        shown: 2,
        open: 6,
        sort: MarketDiscoverySort.mostActive,
      ),
      '2 of 6 open markets · most active first',
    );
    expect(
      discoveryCountLabel(shown: 1, open: 1),
      '1 open market · soonest to close first',
    );
  });

  testWidgets('Markets offers every open category and filters by it', (
    tester,
  ) async {
    final provider = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    );
    addTearDown(provider.dispose);
    await mount(tester, provider, const CallMarketsScreen());
    expect(find.text('Crypto only'), findsNothing);
    expect(
      find.text('6 open markets · soonest to close first'),
      findsOneWidget,
    );
    for (final chip in [
      'All categories',
      'Crypto · 2',
      'Pop culture · 2',
      'Gaming · 1',
      'Sports · 1',
    ]) {
      expect(find.text(chip), findsOneWidget);
    }
    // Discovery does not wait for prices: every open market is listed.
    expect(find.byType(CallMarketCard), findsWidgets);
    await tapChip(tester, 'Pop culture · 2');
    expect(
      find.text('2 of 6 open markets · soonest to close first'),
      findsOneWidget,
    );
    expect(find.byType(CallMarketCard), findsNWidgets(2));
    expect(find.textContaining('BBNaija'), findsOneWidget);
    expect(find.textContaining('Tram'), findsOneWidget);
    // Tapping the selected chip again, or "All categories", clears it.
    await tapChip(tester, 'Pop culture · 2');
    expect(
      find.text('6 open markets · soonest to close first'),
      findsOneWidget,
    );
    await tapChip(tester, 'Gaming · 1');
    await tester.tap(find.text('Ending soon'));
    await tester.pumpAndSettle();
    expect(find.text('No open markets match these filters'), findsOneWidget);
    await tester.tap(find.text('Show all markets'));
    await tester.pumpAndSettle();
    expect(
      find.text('6 open markets · soonest to close first'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a market without a price is listed, labelled unavailable', (
    tester,
  ) async {
    final m = market(
      'nil',
      const Duration(hours: 5),
      question: 'Will the unpriced market list?',
    );
    final provider = CallsProvider(repository: CatalogRepository([m]));
    addTearDown(provider.dispose);
    await mount(tester, provider, const CallMarketsScreen());
    expect(find.text(m.question), findsOneWidget);
    expect(find.text('Price unavailable'), findsNWidgets(2));
    expect(find.text('0.00'), findsNothing);
  });

  testWidgets('Most active appears only when the venue reports volume', (
    tester,
  ) async {
    final quiet = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    );
    addTearDown(quiet.dispose);
    await mount(tester, quiet, const CallMarketsScreen());
    expect(find.text('Most active'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    final markets = liveShapedCatalog();
    markets[5] = withVolume(markets[5], '900.00'); // btc, closes last
    markets[3] = withVolume(markets[3], '15.25'); // mufc
    final active = CallsProvider(repository: CatalogRepository(markets));
    addTearDown(active.dispose);
    await mount(tester, active, const CallMarketsScreen());
    expect(firstCard(tester), 'jump'); // soonest to close
    await tester.tap(find.text('Most active'));
    await tester.pumpAndSettle();
    expect(find.text('6 open markets · most active first'), findsOneWidget);
    expect(firstCard(tester), 'btc'); // highest reported volume
    await tester.tap(find.text('Most active'));
    await tester.pumpAndSettle();
    expect(firstCard(tester), 'jump');
    expect(tester.takeException(), isNull);
  });

  testWidgets('category row scrolls at 320dp / 2x with 48dp targets', (
    tester,
  ) async {
    final markets = [
      for (final (i, c)
          in [
            'crypto',
            'pop-culture',
            'sports',
            'gaming',
            'commodities',
            'meme-coins',
            'macroeconomics',
          ].indexed)
        market('m$i', Duration(hours: 10 + i), category: c),
    ];
    final provider = CallsProvider(repository: CatalogRepository(markets));
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      const CallMarketsScreen(),
      width: 320,
      scale: 2,
    );
    // Seven categories cannot fit 320dp at 2x; the last is reached by
    // scrolling the row, not by wrapping chips down the screen.
    final row = find.ancestor(
      of: find.text('All categories'),
      matching: find.byType(SingleChildScrollView),
    );
    expect(tester.getSize(row).width, lessThanOrEqualTo(320));
    await tapChip(tester, 'Macroeconomics · 1');
    expect(find.byType(CallMarketCard), findsOneWidget);
    expect(firstCard(tester), 'm6');
    for (final chip in find.byType(OutlinedButton).evaluate()) {
      expect(
        tester.getSize(find.byWidget(chip.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the market picker browses by category too', (tester) async {
    final provider = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    )..setViewer('test-person');
    addTearDown(provider.dispose);
    await mount(tester, provider, const MarketPickerSheet());
    await tapChip(tester, 'Sports · 1');
    expect(find.byType(CallMarketCard), findsOneWidget);
    expect(find.textContaining('Manchester'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
