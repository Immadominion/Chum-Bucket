// Market prices and the catalog stay current without a refresh button: the
// provider re-reads what is due, silently, and never drops the last good
// price while it does.
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_markets_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/market_picker_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'ui_market_layout_discovery_test.dart'
    show CatalogRepository, market, mount;

/// A catalog whose prices are stamped by the test's clock and whose detail
/// reads can be made to fail.
class _ClockedRepository extends CatalogRepository {
  _ClockedRepository(super.markets, this.now);
  final DateTime Function() now;
  bool failDetail = false;
  bool withholdPrice = false;
  int catalogReads = 0;

  /// How old the next prices are when read: past the venue's ten-minute
  /// validity, a price is still shown but cannot be locked.
  Duration priceAge = Duration.zero;

  /// How many times Lock reached the server.
  int locks = 0;

  @override
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  }) {
    locks++;
    return super.createCall(input: input, viewerUserId: viewerUserId);
  }

  @override
  Future<List<VenueMarket>> fetchOpenMarkets({String? category}) {
    catalogReads++;
    return super.fetchOpenMarkets(category: category);
  }

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async {
    reads++;
    if (failDetail) throw const CallsRejectedException('venue unreachable');
    return MarketDetail(
      market: markets.firstWhere((m) => m.id == marketId),
      snapshot: null,
      sharePrice:
          withholdPrice
              ? null
              : SharePriceSnapshot(
                id: 'price-$reads',
                marketId: marketId,
                yesPrice: '0.6$reads',
                noPrice: '0.4$reads',
                observedAt: now().subtract(priceAge).millisecondsSinceEpoch,
              ),
      servedAt: now().millisecondsSinceEpoch,
    );
  }
}

void main() {
  late DateTime now;
  late VenueMarket btc;
  late _ClockedRepository repo;
  late CallsProvider provider;

  setUp(() {
    now = DateTime.now();
    btc = market('BTC', const Duration(days: 2));
    repo = _ClockedRepository([btc], () => now);
    provider = CallsProvider(repository: repo, clock: () => now);
  });
  tearDown(() => provider.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a price never read is read once; a new one is left alone', () async {
    expect(provider.priceRefreshDue(btc.id), isTrue);
    provider.refreshPriceIfStale(btc.id);
    provider.refreshPriceIfStale(btc.id); // in flight: no second read
    await settle();
    expect(repo.reads, 1);
    expect(provider.marketDetail(btc.id)!.sharePrice!.yesPrice, '0.61');
    now = now.add(const Duration(minutes: 3));
    provider.refreshPriceIfStale(btc.id);
    await settle();
    expect(repo.reads, 1);
  });

  test('a price getting old is read again before it lapses', () async {
    provider.refreshPriceIfStale(btc.id);
    await settle();
    now = now.add(CallsProvider.priceRefreshAfter);
    expect(provider.priceRefreshDue(btc.id), isTrue);
    provider.refreshPriceIfStale(btc.id);
    await settle();
    expect(repo.reads, 2);
    expect(provider.marketDetail(btc.id)!.sharePrice!.yesPrice, '0.62');
  });

  test(
    'a failed read keeps the last good price and waits before retrying',
    () async {
      provider.refreshPriceIfStale(btc.id);
      await settle();
      now = now.add(const Duration(minutes: 5));
      repo.failDetail = true;
      provider.refreshPriceIfStale(btc.id);
      await settle();
      expect(repo.reads, 2);
      // Still on screen: the price that was there.
      expect(provider.marketDetail(btc.id)!.sharePrice!.yesPrice, '0.61');
      // Not asked again on every frame.
      provider.refreshPriceIfStale(btc.id);
      await settle();
      expect(repo.reads, 2);
      now = now.add(CallsProvider.priceRetryAfter);
      repo.failDetail = false;
      provider.refreshPriceIfStale(btc.id);
      await settle();
      expect(repo.reads, 3);
      expect(provider.marketDetail(btc.id)!.sharePrice!.yesPrice, '0.63');
    },
  );

  test(
    'a market without a price is retried, but at most once a minute',
    () async {
      repo.withholdPrice = true;
      provider.refreshPriceIfStale(btc.id);
      await settle();
      expect(provider.priceRefreshDue(btc.id), isFalse);
      now = now.add(const Duration(seconds: 59));
      provider.refreshPriceIfStale(btc.id);
      await settle();
      expect(repo.reads, 1);
      now = now.add(const Duration(seconds: 1));
      provider.refreshPriceIfStale(btc.id);
      await settle();
      expect(repo.reads, 2);
    },
  );

  test('a price stamped ahead of this clock counts as new', () async {
    provider.refreshPriceIfStale(btc.id);
    await settle();
    now = now.subtract(const Duration(minutes: 2));
    expect(provider.priceRefreshDue(btc.id), isFalse);
  });

  test('the catalog is re-read only once it is old', () async {
    await provider.refreshOpenMarketsIfStale();
    expect(repo.catalogReads, 1);
    await provider.refreshOpenMarketsIfStale();
    expect(repo.catalogReads, 1);
    now = now.add(CallsProvider.catalogRefreshAfter);
    await provider.refreshOpenMarketsIfStale();
    expect(repo.catalogReads, 2);
    expect(provider.openMarkets, isNotEmpty);
  });

  test('a new account starts its price reads afresh', () async {
    provider.refreshPriceIfStale(btc.id);
    await settle();
    provider.setViewer('someone-else');
    expect(provider.priceRefreshDue(btc.id), isTrue);
  });

  testWidgets('Markets re-reads due prices on its own, with no button', (
    tester,
  ) async {
    final screenRepo = _ClockedRepository([btc], () => now);
    final screenProvider = CallsProvider(
      repository: screenRepo,
      clock: () => now,
    );
    addTearDown(screenProvider.dispose);
    await mount(tester, screenProvider, const CallMarketsScreen());
    expect(screenRepo.reads, 1);
    expect(find.text('0.61'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsNothing);
    expect(find.textContaining('updated'), findsNothing);
    // Within the window: the timer ticks, nothing is due, nothing is read.
    await tester.pump(CallMarketsScreen.tick);
    await tester.pumpAndSettle();
    expect(screenRepo.reads, 1);
    // Past it: the next tick re-reads behind the price on screen.
    now = now.add(CallsProvider.priceRefreshAfter);
    await tester.pump(CallMarketsScreen.tick);
    await tester.pumpAndSettle();
    expect(screenRepo.reads, 2);
    expect(find.text('0.62'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pull to refresh re-reads the shown prices once', (tester) async {
    final screenRepo = _ClockedRepository([btc], () => now);
    final screenProvider = CallsProvider(
      repository: screenRepo,
      clock: () => now,
    );
    addTearDown(screenProvider.dispose);
    await mount(tester, screenProvider, const CallMarketsScreen());
    expect(screenRepo.reads, 1);
    expect(screenRepo.catalogReads, 1);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(screenRepo.catalogReads, 2);
    expect(screenRepo.reads, 2);
    expect(find.text('0.62'), findsOneWidget);
    // Consumed: later rebuilds go back to reading only what is due.
    await tester.pump(CallMarketsScreen.tick);
    await tester.pumpAndSettle();
    expect(screenRepo.reads, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('market detail keeps its price current with no button', (
    tester,
  ) async {
    final screenRepo = _ClockedRepository([btc], () => now);
    final screenProvider = CallsProvider(
      repository: screenRepo,
      clock: () => now,
    );
    addTearDown(screenProvider.dispose);
    await mount(tester, screenProvider, MarketDetailScreen(marketId: btc.id));
    expect(screenRepo.reads, 1);
    expect(find.text('0.61'), findsOneWidget);
    expect(find.byTooltip('Refresh market'), findsNothing);
    now = now.add(CallsProvider.priceRefreshAfter);
    await tester.pump(MarketDetailScreen.tick);
    await tester.pumpAndSettle();
    expect(screenRepo.reads, 2);
    expect(find.text('0.62'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a market already loaded opens at once and is re-read behind', (
    tester,
  ) async {
    final screenRepo = _ClockedRepository([btc], () => now);
    final screenProvider = CallsProvider(
      repository: screenRepo,
      clock: () => now,
    );
    addTearDown(screenProvider.dispose);
    await screenProvider.loadMarketDetail(btc.id);
    expect(screenRepo.reads, 1);
    await mount(tester, screenProvider, MarketDetailScreen(marketId: btc.id));
    expect(screenRepo.reads, 2);
    expect(find.text('0.62'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  /// The provider sits above the app, as in main.dart, so the composer and
  /// the picker (their own routes) can read it.
  Future<void> mountAbove(
    WidgetTester tester,
    CallsProvider provider,
    Widget child,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<CallsProvider>.value(
        value: provider,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                theme: AppTheme.lightTheme,
                home: Scaffold(body: child),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> lockYes(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(CallJourneySides),
        matching: find.text('YES'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock my YES call'));
    await tester.pumpAndSettle();
  }

  const deadEnd =
      'Panta prices are missing or stale. Refresh this market before calling.';

  /// Lock re-read the lapsed price itself and then went on to lock: the
  /// composer (fleet/ux-calls) never stops to ask the person to check a
  /// fresh price — the server stamps, and re-reads, Panta's price itself.
  void expectLocked(WidgetTester tester, _ClockedRepository repo) {
    expect(repo.locks, 1);
    expect(find.text(deadEnd), findsNothing);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'from market detail, Lock re-reads a lapsed price itself (no refresh '
    'button to send anyone to)',
    (tester) async {
      final screenRepo = _ClockedRepository([btc], () => now)
        ..priceAge = const Duration(minutes: 20);
      final screenProvider = CallsProvider(
        repository: screenRepo,
        clock: () => now,
      )..setViewer('viewer-1');
      addTearDown(screenProvider.dispose);
      await mountAbove(
        tester,
        screenProvider,
        MarketDetailScreen(marketId: btc.id),
      );
      expect(screenRepo.reads, 1);
      // Shown (inside the hour lists keep a last good price), not lockable.
      expect(find.text('0.61'), findsOneWidget);
      await tester.tap(find.text('Make a call'));
      await tester.pumpAndSettle();
      screenRepo.priceAge = Duration.zero;
      await lockYes(tester);
      expect(screenRepo.reads, 2);
      expectLocked(tester, screenRepo);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('from the picker, Lock re-reads a lapsed price itself', (
    tester,
  ) async {
    final screenRepo = _ClockedRepository([btc], () => now)
      ..priceAge = const Duration(minutes: 20);
    final screenProvider = CallsProvider(
      repository: screenRepo,
      clock: () => now,
    )..setViewer('viewer-1');
    addTearDown(screenProvider.dispose);
    await mountAbove(tester, screenProvider, const MarketPickerSheet());
    final before = screenRepo.reads;
    await tester.tap(find.text(btc.question));
    await tester.pumpAndSettle();
    // Picking reads the market once more before the composer opens.
    expect(screenRepo.reads, before + 1);
    screenRepo.priceAge = Duration.zero;
    await lockYes(tester);
    expect(screenRepo.reads, before + 2);
    expectLocked(tester, screenRepo);
    await tester.pumpWidget(const SizedBox());
  });
}
