import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_filters.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_picker_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_state_view.dart';
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

const filtersButton = ValueKey('market-filters-button');

Future<void> openFilters(WidgetTester tester) async {
  await tester.tap(find.byKey(filtersButton).last);
  await tester.pumpAndSettle();
}

/// The filter button's count badge.
Finder badge(String count) =>
    find.descendant(of: find.byKey(filtersButton), matching: find.text(count));

/// Taps an active filter's pill, which turns that filter off.
Future<void> clearPill(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('market-active-filters')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the filter sheet, taps one choice and closes it again.
Future<void> chooseFilter(WidgetTester tester, String label) async {
  await openFilters(tester);
  final chip = find.descendant(
    of: find.byType(MarketFilterSheet),
    matching: find.text(label),
  );
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Show markets'));
  await tester.tap(find.text('Show markets'));
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
          // One control row: the search field and a 48dp filter button.
          expect(find.byType(TextField), findsOneWidget);
          final filters = tester.getSize(find.byKey(filtersButton));
          expect(filters.height, greaterThanOrEqualTo(48));
          expect(filters.width, greaterThanOrEqualTo(48));
          // No chip rows on the page itself until a filter is on.
          expect(find.byType(OutlinedButton), findsNothing);
          await tester.tap(find.byTooltip('Activity'));
          expect(activity, 1);
          // Rows read as odds; never the venue's per-share strings.
          await reveal(tester, find.text('62%'));
          expect(find.text('43%'), findsOneWidget);
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
    await chooseFilter(tester, 'Ending soon');
    expect(find.textContaining('Will ETH'), findsNothing);
    await chooseFilter(tester, 'This week');
    await tester.enterText(find.byType(TextField), 'eTh');
    await tester.pumpAndSettle();
    expect(find.textContaining('Will ETH'), findsOneWidget);
    expect(find.textContaining('Will BTC'), findsNothing);
    await tester.enterText(find.byType(TextField), 'not a market');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches these filters'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    // The search field's own cross clears it.
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Will BTC'), findsOneWidget);
    expect(find.textContaining('Will ETH'), findsOneWidget);
  });

  for (final picker in [false, true]) {
    testWidgets(
      'lists carry no attribution, unit, count or sort lines (picker=$picker)',
      (tester) async {
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
        expect(find.byType(CallMarketCard), findsNWidgets(2));
        for (final text in [
          'Powered by Panta',
          'USDC',
          'open market',
          'soonest',
          'Venue prices',
          'No money involved',
          'Closing within',
        ]) {
          expect(find.textContaining(text), findsNothing, reason: text);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact row keeps its complete question, price and time left', (
    tester,
  ) async {
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
    expect(rowSize.height, lessThanOrEqualTo(140));
    expect(rowSize.height, greaterThanOrEqualTo(48));
    final question = tester.widget<Text>(find.text(m.question));
    expect(question.maxLines, isNull);
    expect(question.overflow, isNot(TextOverflow.ellipsis));
    expect(
      tester.widget<Text>(find.text('62%')).semanticsLabel,
      '62% chance',
    );
    // Time left, not a timestamp; the exact close is its spoken label.
    expect(find.text('11h left'), findsOneWidget);
    final spoken =
        tester
            .widget<Semantics>(
              find
                  .ancestor(
                    of: find.text('11h left'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .label;
    expect(spoken, matches(RegExp(r'^Closes .* UTC$')));
    expect(find.textContaining('Powered by Panta'), findsNothing);
    await tester.tap(find.byType(CallMarketCard));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('time left reads in the largest whole unit, then the date', () {
    final now = DateTime.utc(2026, 10, 4, 12);
    String? left(Duration d) => marketTimeLeft(now.add(d), now: now);
    expect(left(const Duration(seconds: 20)), '1m left');
    expect(left(const Duration(minutes: 45)), '45m left');
    expect(left(const Duration(hours: 6, minutes: 59)), '6h left');
    expect(left(const Duration(hours: 47)), '47h left');
    expect(left(const Duration(days: 3, hours: 2)), '3d left');
    expect(left(const Duration(days: 89)), 'Ends 1 Jan');
    expect(left(const Duration(minutes: -5)), 'Closed');
    expect(marketTimeLeft(null, now: now), isNull);
    expect(marketEndingSoon(now.add(const Duration(hours: 5)), now: now), true);
    expect(marketEndingSoon(now.add(const Duration(days: 2)), now: now), false);
  });

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
    await reveal(tester, find.text('43%'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a missing side or an outdated price is a quiet dash, never a '
      'warning', (tester) async {
    final m = market('BTC', const Duration(hours: 12));
    final provider = CallsProvider(repository: CatalogRepository([m]));
    addTearDown(provider.dispose);
    await mount(
      tester,
      provider,
      SingleChildScrollView(
        child: Column(
          children: [
            CallMarketCard(
              market: m,
              sharePrice: price(m.id, no: null),
              onTap: () {},
            ),
            CallMarketCard(
              market: m,
              sharePrice: price(m.id, stale: true),
              onTap: () {},
            ),
          ],
        ),
      ),
      width: 320,
      scale: 2,
    );
    // First row: YES shows, NO is a dash. Second row (2h old): both dashes.
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(
      tester
          .widgetList<Text>(find.text('—'))
          .map((t) => t.semanticsLabel)
          .toSet(),
      {'Odds unavailable'},
    );
    for (final text in ['Last updated', 'stale', 'incomplete', 'unavailable']) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
    expect(find.text('38%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('market detail reads odds, keeps no per-share figures and '
      'withholds ungated crowd', (tester) async {
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
    // Detail reads as odds and names the venue once.
    expect(find.text('62%'), findsOneWidget);
    expect(find.textContaining('Powered by Panta'), findsOneWidget);
    // No refresh button, no "updated" line, no scary price state.
    expect(find.byTooltip('Refresh market'), findsNothing);
    for (final text in ['updated', 'Last synced', 'stale', 'cached']) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
    // Without a call of your own there is nothing to trade yet: no disabled
    // Trade button, no paragraph explaining it.
    expect(find.text('Trade'), findsNothing);
    expect(find.textContaining('existing call'), findsNothing);
    expect(
      find.text('YES 0.620000000000000001 · NO 0.430000000000000001'),
      findsNothing,
    );
    await reveal(tester, find.text('Rules & details'));
    await tester.tap(find.text('Rules & details'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      m.rulesText,
    );
    // Not even behind the disclosure: a price is a percent everywhere.
    expect(find.textContaining('0.620000000000000001'), findsNothing);
    expect(find.textContaining('per share'), findsNothing);
    expect(find.text('How people called'), findsNothing);
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
    await reveal(tester, find.text('Demo data · no live prices'));
    expect(tester.takeException(), isNull);
  });

  for (final offline in [true, false]) {
    testWidgets(
      'catalog failure is one state screen with one retry (offline=$offline)',
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
        // One short line under the brand art, and one action.
        expect(
          find.text(offline ? "You're offline" : "Markets didn't load"),
          findsOneWidget,
        );
        expect(find.byType(ChumbucketStateArt), findsOneWidget);
        // The server's own wording stays out of the way.
        expect(find.text('Could not load test catalog.'), findsNothing);
        expect(find.text('Try again'), findsOneWidget);
        repo
          ..simulateOffline = false
          ..simulateFailure = false;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Try again'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a failed background refresh keeps the rows, silently', (
    tester,
  ) async {
    final repo = CatalogRepository([market('BTC', const Duration(hours: 12))]);
    final provider = CallsProvider(repository: repo);
    addTearDown(provider.dispose);
    await mount(tester, provider, const CallMarketsScreen());
    repo.simulateFailure = true;
    // Not awaited: the repository's delay runs on the test's fake clock.
    provider.loadOpenMarkets(force: true);
    await tester.pumpAndSettle();
    expect(find.byType(CallMarketCard), findsOneWidget);
    expect(find.text('Could not load test catalog.'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Offline'), findsNothing);
    // Offline with saved rows: a one-word pill, never a refresh button.
    repo
      ..simulateFailure = false
      ..simulateOffline = true;
    // Not awaited: the repository's delay runs on the test's fake clock.
    provider.loadOpenMarkets(force: true);
    await tester.pumpAndSettle();
    expect(find.byType(CallMarketCard), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byTooltip('Refresh'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ── The whole open catalog: real categories, search, sort ──

  VenueMarket withVolume(VenueMarket m, String? volume) =>
      VenueMarket.fromJson({...m.toJson(), 'volumeUsdc': volume});

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

  test('category choices come from the open markets themselves', () {
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
  });

  test('filters count what is on, and each choice clears on its own', () {
    const none = MarketFilters.none;
    expect(none.activeCount, 0);
    expect(none.isEmpty, isTrue);
    final all = none
        .withWindow(MarketDiscoveryWindow.thisWeek)
        .withTopic(category: 'crypto')
        .withSort(MarketDiscoverySort.mostActive);
    expect(all.activeCount, 3);
    expect(all.withTopic(forYou: true).category, isNull);
    expect(all.withTopic(forYou: true).activeCount, 3);
    expect(all.withTopic().activeCount, 2);
    expect(all.withWindow(MarketDiscoveryWindow.all).activeCount, 2);
    expect(all.withSort(MarketDiscoverySort.closingSoon).activeCount, 2);
    expect(
      none.withTopic(category: 'crypto'),
      none.withTopic(category: 'crypto'),
    );
  });

  testWidgets('Markets offers every open category in its filter sheet', (
    tester,
  ) async {
    final provider = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    );
    addTearDown(provider.dispose);
    await mount(tester, provider, const CallMarketsScreen());
    // Six open; the lazy list builds what fits the screen.
    expect(find.byType(CallMarketCard), findsAtLeastNWidgets(5));
    expect(find.byKey(const ValueKey('market-active-filters')), findsNothing);
    await openFilters(tester);
    final sheet = find.byType(MarketFilterSheet);
    for (final (chip, count) in [
      ('Crypto', '2'),
      ('Pop culture', '2'),
      ('Gaming', '1'),
      ('Sports', '1'),
    ]) {
      final button = find.ancestor(
        of: find.descendant(of: sheet, matching: find.text(chip)),
        matching: find.byType(OutlinedButton),
      );
      expect(button, findsOneWidget, reason: chip);
      expect(
        find.descendant(of: button, matching: find.text(count)),
        findsOneWidget,
        reason: chip,
      );
    }
    // Defaults have no chip of their own: nothing selected is every topic
    // and any time, and a selected chip turns off when tapped again.
    for (final none in ['All', 'Any time', 'All dates']) {
      expect(
        find.descendant(of: sheet, matching: find.text(none)),
        findsNothing,
        reason: none,
      );
    }
    // No volume reported: no sort to offer.
    expect(find.text('Most active'), findsNothing);
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('Pop culture')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show markets'));
    await tester.pumpAndSettle();
    expect(find.byType(CallMarketCard), findsNWidgets(2));
    expect(find.textContaining('BBNaija'), findsOneWidget);
    expect(find.textContaining('Tram'), findsOneWidget);
    // One pill names it; its cross clears it.
    expect(badge('1'), findsOneWidget);
    await clearPill(tester, 'Pop culture');
    await tester.pumpAndSettle();
    // Six open; the lazy list builds what fits the screen.
    expect(find.byType(CallMarketCard), findsAtLeastNWidgets(5));
    expect(find.byKey(const ValueKey('market-active-filters')), findsNothing);
    await chooseFilter(tester, 'Gaming');
    await chooseFilter(tester, 'Ending soon');
    expect(badge('2'), findsOneWidget);
    expect(find.text('Nothing matches these filters'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    // Six open; the lazy list builds what fits the screen.
    expect(find.byType(CallMarketCard), findsAtLeastNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chosen time or topic turns off when tapped again', (
    tester,
  ) async {
    final provider = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    );
    addTearDown(provider.dispose);
    await mount(tester, provider, const CallMarketsScreen());
    for (final choice in ['This week', 'Gaming']) {
      await chooseFilter(tester, choice);
      expect(badge('1'), findsOneWidget, reason: choice);
      await chooseFilter(tester, choice);
      expect(badge('1'), findsNothing, reason: choice);
      expect(
        find.byKey(const ValueKey('market-active-filters')),
        findsNothing,
        reason: choice,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed-out picker is one state: art, a line, Sign in', (
    tester,
  ) async {
    final provider = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    );
    addTearDown(provider.dispose);
    await mount(tester, provider, const MarketPickerSheet());
    expect(find.text('Sign in to make a call'), findsOneWidget);
    expect(find.byType(ChumbucketStateArt), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    // Nothing to search while nothing can be picked.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('No wallet, no money'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a market without a price is listed, its prices a quiet dash', (
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
    expect(find.text('—'), findsNWidgets(2));
    expect(
      tester
          .widgetList<Text>(find.text('—'))
          .map((t) => t.semanticsLabel)
          .toSet(),
      {'Odds unavailable'},
    );
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('Most active is a sort in the sheet, offered only with volume', (
    tester,
  ) async {
    final quiet = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    );
    addTearDown(quiet.dispose);
    await mount(tester, quiet, const CallMarketsScreen());
    await openFilters(tester);
    expect(find.text('Most active'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    final markets = liveShapedCatalog();
    markets[5] = withVolume(markets[5], '900.00'); // btc, closes last
    markets[3] = withVolume(markets[3], '15.25'); // mufc
    final active = CallsProvider(repository: CatalogRepository(markets));
    addTearDown(active.dispose);
    await mount(tester, active, const CallMarketsScreen());
    expect(firstCard(tester), 'jump'); // soonest to close
    await chooseFilter(tester, 'Most active');
    expect(firstCard(tester), 'btc'); // highest reported volume
    expect(find.textContaining('most active first'), findsNothing);
    await clearPill(tester, 'Most active');
    expect(firstCard(tester), 'jump');
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter sheet fits 320dp / 2x with 48dp targets', (tester) async {
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
    await openFilters(tester);
    for (final chip in find.byType(OutlinedButton).evaluate()) {
      expect(
        tester.getSize(find.byWidget(chip.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
    final last = find.descendant(
      of: find.byType(MarketFilterSheet),
      matching: find.text('Macroeconomics'),
    );
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show markets'));
    await tester.tap(find.text('Show markets'));
    await tester.pumpAndSettle();
    expect(find.byType(CallMarketCard), findsOneWidget);
    expect(firstCard(tester), 'm6');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the market picker browses by category too', (tester) async {
    final provider = CallsProvider(
      repository: CatalogRepository(liveShapedCatalog()),
    )..setViewer('test-person');
    addTearDown(provider.dispose);
    await mount(tester, provider, const MarketPickerSheet());
    await chooseFilter(tester, 'Sports');
    expect(find.byType(CallMarketCard), findsOneWidget);
    expect(find.textContaining('Manchester'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
