import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_picker_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
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
          await tester.tap(find.byTooltip('Activity'));
          expect(activity, 1);
          await reveal(tester, find.text('0.620000000000000001'));
          expect(find.text('0.430000000000000001'), findsOneWidget);
          expect(repo.reads, 1);
          expect(tester.takeException(), isNull);
          final filters = tester.widgetList<OutlinedButton>(
            find.byType(OutlinedButton),
          );
          for (final filter in filters) {
            expect(
              filter.style!.minimumSize!.resolve({})!.height,
              greaterThanOrEqualTo(48),
            );
          }
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
      final call = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Make a call'),
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
}
