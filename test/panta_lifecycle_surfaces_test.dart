// Receipts, market detail and feed cards after the money lifecycle:
// "Resolved by Panta" links to panta.market (never the authenticated API),
// raw IDs sit behind a disclosure, funded calls say so without an amount, and
// the call cut-off window is shown. Synthetic data only.
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/widgets/call_receipt_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bff_calls_fixtures.dart';

const _marketId = '20000000-0000-4000-8000-000000000001';
const _priceId = '60000000-0000-4000-8000-000000000001';
const _resultId = '70000000-0000-4000-8000-000000000001';
const _callId = '30000000-0000-4000-8000-000000000001';
const _venueMarketId = '4uQeVj5tqViQh7yWWGStvkEG1Zmhx6uasJtWCJziofM';
const _apiUrl = 'https://live-api.panta.market/api/v1/markets/$_venueMarketId/';

final _now = DateTime.now().toUtc().millisecondsSinceEpoch;

VenueMarket pantaMarket({int? closesAt}) => VenueMarket(
  id: _marketId,
  venue: MarketVenue.panta,
  venueEventId: _venueMarketId,
  venueMarketId: _venueMarketId,
  question: 'Will the synthetic asset close above the threshold?',
  rulesText: 'Synthetic rules for a synthetic market.',
  category: 'crypto',
  outcomes: const [
    MarketOutcome(side: Side.yes, label: 'Yes'),
    MarketOutcome(side: Side.no, label: 'No'),
  ],
  status: MarketStatus.open,
  rawStatus: 'primary',
  opensAt: null,
  closesAt: closesAt ?? _now + 3600000,
  resolvesAt: null,
  resolutionSource: _apiUrl,
  lastSyncedAt: _now,
  payloadVersion: 1,
);

CallFeedEntry pantaEntry({bool funded = false}) => CallFeedEntry(
  call: Call(
    id: _callId,
    userId: 'user_ada',
    marketId: _marketId,
    side: Side.yes,
    confidence: null,
    thesis: null,
    entryProbability: null,
    snapshotId: null,
    entryPrice: SharePriceSnapshot(
      id: _priceId,
      marketId: _marketId,
      yesPrice: '0.52',
      noPrice: '0.5',
      observedAt: _now - 60000,
    ),
    visibility: CallVisibility.public,
    createdAt: _now - 60000,
    lockedAt: _now - 60000,
    parentCallId: null,
    fundingState: FundingState.none,
  ),
  author: const Person(id: 'user_ada', handle: 'ada', displayName: 'Ada'),
  market: pantaMarket(),
  result: CallResult(
    callId: _callId,
    outcome: CallOutcome.correct,
    resolution: Resolution.yes,
    resolvedAt: _now,
    marketResolutionId: _resultId,
    derivedAt: _now,
  ),
  funding: funded ? CallFunding(fundedAt: _now) : null,
);

Widget app(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (_, _) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
);

class _PantaRepo extends MockCallsRepository {
  _PantaRepo(this.detail);
  final MarketDetail detail;
  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async => detail;
}

void main() {
  group('wire', () {
    test('a funded marker is read only for a confirmed Panta fill', () {
      final funded = callFeedEntryFromJson({
        ...feedEntryJson(),
        'funding': {'state': 'FILLED', 'venue': 'panta', 'fundedAt': kNowMs},
      });
      expect(funded.isFunded, isTrue);
      expect(funded.call.fundingState, FundingState.none);
      for (final bogus in [
        null,
        {'state': 'SUBMITTED', 'venue': 'panta', 'fundedAt': kNowMs},
        {'state': 'FILLED', 'venue': 'elsewhere', 'fundedAt': kNowMs},
        'FILLED',
      ]) {
        expect(
          callFeedEntryFromJson({
            ...feedEntryJson(),
            'funding': bogus,
          }).isFunded,
          isFalse,
        );
      }
    });

    test('market detail carries the server call window when it sends one', () {
      final detail = marketDetailFromJson({
        ...marketDetailJson(),
        'callsCloseAt': kNowMs + kHour,
        'callCutoffMs': 30 * kMinute,
      });
      expect(detail.callsCloseAt, kNowMs + kHour);
      expect(detail.callCutoffMs, 30 * kMinute);
      expect(marketDetailFromJson(marketDetailJson()).callsCloseAt, isNull);
    });
  });

  group('receipt', () {
    testWidgets(
      'resolved by Panta links panta.market; IDs are behind a disclosure',
      (tester) async {
        final receipt = CallReceipt.fromEntry(
          pantaEntry(),
          shareUrl: 'https://chumbucket.app/c/$_callId',
        );
        await tester.pumpWidget(app(CallReceiptCard(receipt: receipt)));
        await tester.pumpAndSettle();
        expect(
          find.text('Panta · panta.market/market/$_venueMarketId'),
          findsOneWidget,
        );
        expect(find.text('Check the result on Panta'), findsOneWidget);
        expect(find.textContaining('live-api'), findsNothing);
        expect(find.textContaining(_priceId), findsNothing);
        expect(find.textContaining(_resultId), findsNothing);
        expect(find.textContaining('Call $_callId'), findsNothing);
        expect(
          find.text('Free call. No stake, no position, no money.'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Record IDs'));
        await tester.tap(find.text('Record IDs'));
        await tester.pumpAndSettle();
        expect(find.textContaining(_priceId), findsOneWidget);
        expect(find.textContaining(_resultId), findsOneWidget);
      },
    );

    testWidgets('a funded call says so, without an amount', (tester) async {
      final receipt = CallReceipt.fromEntry(
        pantaEntry(funded: true),
        shareUrl: 'https://chumbucket.app/c/$_callId',
      );
      expect(receipt.fundedOnPanta, isTrue);
      await tester.pumpWidget(app(CallReceiptCard(receipt: receipt)));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Backed with a confirmed Panta position. Chumbucket doesn’t show the amount.',
        ),
        findsOneWidget,
      );
      // Share prices read "USDC/share"; no amount of USDC appears anywhere.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data ?? '').replaceAll('USDC/share', '').contains('USDC'),
        ),
        findsNothing,
      );
      expect(receipt.shareCaption, isNot(contains('USDC')));
    });
  });

  testWidgets('a funded call card reads Funded; a free one reads Free call', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Column(
          children: [
            CallCard(entry: pantaEntry(funded: true)),
            CallCard(entry: pantaEntry()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Funded'), findsOneWidget);
    expect(find.text('Free call'), findsOneWidget);
  });

  group('market detail', () {
    Future<void> open(WidgetTester tester, MarketDetail detail) async {
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = CallsProvider(repository: _PantaRepo(detail));
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                home: ChangeNotifierProvider<CallsProvider>.value(
                  value: provider,
                  child: const MarketDetailScreen(marketId: _marketId),
                ),
              ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the call window and closes calls inside it', (
      tester,
    ) async {
      final market = pantaMarket(closesAt: _now + 20 * 60000);
      await open(
        tester,
        MarketDetail(
          market: market,
          snapshot: null,
          servedAt: _now,
          callsCloseAt: market.closesAt! - 30 * 60000,
          callCutoffMs: 30 * 60000,
        ),
      );
      expect(find.byKey(const ValueKey('market-call-window')), findsOneWidget);
      expect(
        find.text('Calls closed 30 min before the market closes.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Calls are closed: they close 30 min before the market does.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an open window names when calls close', (tester) async {
      final market = pantaMarket(closesAt: _now + 2 * 3600000);
      await open(
        tester,
        MarketDetail(
          market: market,
          snapshot: null,
          servedAt: _now,
          callsCloseAt: market.closesAt! - 30 * 60000,
          callCutoffMs: 30 * 60000,
        ),
      );
      expect(
        find.textContaining('min before the market closes'),
        findsOneWidget,
      );
      expect(find.textContaining('Calls close '), findsOneWidget);
    });

    testWidgets(
      'resolved by Panta, never the API URL; IDs behind a disclosure',
      (tester) async {
        await open(
          tester,
          MarketDetail(market: pantaMarket(), snapshot: null, servedAt: _now),
        );
        await tester.ensureVisible(find.text('Read the full market rules'));
        await tester.tap(find.text('Read the full market rules'));
        await tester.pumpAndSettle();
        expect(find.text('Resolved by '), findsOneWidget);
        expect(find.textContaining('live-api'), findsNothing);
        expect(find.textContaining('Resolution source'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Market IDs'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Clear the bottom action bar before tapping.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(find.text(_venueMarketId), findsNothing);
        await tester.tap(find.text('Market IDs'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text(_venueMarketId),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(_venueMarketId), findsOneWidget);
        expect(find.text(_marketId), findsOneWidget);
      },
    );
  });
}
