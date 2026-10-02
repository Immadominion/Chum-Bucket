import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/widgets/call_receipt_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

Future<CallReceipt> receiptFor(MockCallsRepository repo, String callId) async {
  final detail = await repo.fetchCall(callId: callId, viewerUserId: viewer);
  return CallReceipt.fromEntry(
    detail.entry,
    shareUrl: repo.shareLinkForCall(callId),
  );
}

Widget testApp(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (context, _) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: Center(child: child)),
        ),
      ),
);

void main() {
  group(
    'CallReceipt carries the five required facts and nothing money-shaped',
    () {
      test('a correct call', () async {
        final repo = MockCallsRepository();
        final receipt = await receiptFor(repo, 'call_you_fed');

        // 1. original timestamp
        expect(receipt.lockedAt.isUtc, isTrue);
        // 2. exact side
        expect(receipt.side, Side.yes);
        expect(receipt.sideLabel, 'Yes — 25bp cut');
        // 3. entry probability
        expect(receipt.entryProbability, closeTo(0.64, 1e-9));
        // 4. result
        expect(receipt.outcome, CallOutcome.correct);
        expect(receipt.resolution, Resolution.yes);
        expect(receipt.resolvedAt, isNotNull);
        // 5. source market
        expect(
          receipt.marketQuestion,
          'Did the FOMC cut by 25bp at the September meeting?',
        );
        // The mock's markets are all invented, so they are branded `fixture`
        // and must attribute as demo. Asserting 'Jupiter' here is what let a
        // fabricated result present as live venue evidence.
        expect(receipt.venueLabel, 'Demo catalog');
        expect(receipt.venueIsDemo, isTrue);
        expect(receipt.marketResolutionId, 'res_fomc_sep_2026');
        expect(receipt.shareUrl, 'https://chumbucket.app/c/call_you_fed');
      });

      test('an incorrect call still shows the same five facts', () async {
        final repo = MockCallsRepository();
        final receipt = await receiptFor(repo, 'call_zed_fed');
        expect(receipt.outcome, CallOutcome.incorrect);
        expect(receipt.side, Side.no);
        expect(receipt.resolution, Resolution.yes);
        expect(receipt.entryProbability, isNotNull);
      });

      test('a void call is neither a win nor a loss', () async {
        final repo = MockCallsRepository();
        final receipt = await receiptFor(repo, 'call_kemi_listing');
        expect(receipt.outcome, CallOutcome.voided);
        expect(receipt.isVoid, isTrue);
        expect(receipt.shareCaption, contains('void, not a loss'));
      });

      test('a pending call is not a receipt yet', () async {
        final repo = MockCallsRepository();
        final receipt = await receiptFor(repo, 'call_ada_btc');
        expect(receipt.outcome, CallOutcome.pending);
        expect(receipt.isSettled, isFalse);
      });

      test('the share caption never mentions money', () async {
        final repo = MockCallsRepository();
        for (final id in [
          'call_you_fed',
          'call_zed_fed',
          'call_kemi_listing',
        ]) {
          final caption =
              (await receiptFor(repo, id)).shareCaption.toLowerCase();
          for (final forbidden in [
            'stake',
            'staked',
            '\$',
            'usdc',
            'sol',
            'profit',
            'pnl',
            'wager',
            'bet',
          ]) {
            expect(
              caption.contains(forbidden),
              isFalse,
              reason: '$id caption must not contain "$forbidden"',
            );
          }
        }
      });
    },
  );

  group('CallReceiptCard renders the required facts, and no stake', () {
    testWidgets('a correct receipt', (tester) async {
      final repo = MockCallsRepository();
      final receipt = await receiptFor(repo, 'call_you_fed');

      await tester.pumpWidget(testApp(CallReceiptCard(receipt: receipt)));
      await tester.pump();

      expect(find.text('Called it.'), findsOneWidget);
      // The exact side.
      expect(find.text('Yes — 25bp cut'), findsOneWidget);
      // The original timestamp.
      expect(
        find.text(CallsFormat.timestampUtc(receipt.lockedAt)),
        findsOneWidget,
      );
      // The entry probability.
      expect(find.text('64%'), findsOneWidget);
      // The source market.
      expect(find.text(receipt.marketQuestion), findsOneWidget);
      expect(find.text('Demo catalog'), findsOneWidget);
      // The evidence is stated in words; its raw record ID sits behind a
      // disclosure so a shared image shows facts, not identifiers (M21).
      expect(find.text('Demo catalog published the result'), findsOneWidget);
      expect(find.textContaining('res_fomc_sep_2026'), findsNothing);
      await tester.ensureVisible(find.text('Record IDs'));
      await tester.tap(find.text('Record IDs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('res_fomc_sep_2026'), findsOneWidget);
      // And the explicit denial of a stake.
      expect(
        find.text('Free call. No stake, no position, no money.'),
        findsOneWidget,
      );
    });

    testWidgets('an incorrect receipt reads unmistakably as a loss', (
      tester,
    ) async {
      final repo = MockCallsRepository();
      final receipt = await receiptFor(repo, 'call_zed_fed');
      await tester.pumpWidget(testApp(CallReceiptCard(receipt: receipt)));
      await tester.pump();
      expect(find.text('Missed this one.'), findsOneWidget);
      expect(find.text('Called it.'), findsNothing);
    });

    testWidgets('a void receipt says void, never win or loss', (tester) async {
      final repo = MockCallsRepository();
      final receipt = await receiptFor(repo, 'call_kemi_listing');
      await tester.pumpWidget(testApp(CallReceiptCard(receipt: receipt)));
      await tester.pump();

      expect(find.text('Market voided.'), findsOneWidget);
      expect(find.text('Called it.'), findsNothing);
      expect(find.text('Missed this one.'), findsNothing);
      expect(
        find.text(CallsFormat.outcomeSentence(CallOutcome.voided)),
        findsOneWidget,
      );
      expect(find.text('VOID — cancelled'), findsOneWidget);
    });

    testWidgets('no rendered string on a receipt looks like an amount', (
      tester,
    ) async {
      final repo = MockCallsRepository();
      for (final id in ['call_you_fed', 'call_zed_fed', 'call_kemi_listing']) {
        final receipt = await receiptFor(repo, id);
        await tester.pumpWidget(testApp(CallReceiptCard(receipt: receipt)));
        await tester.pump();

        final texts =
            tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => (t.data ?? '').toLowerCase())
                .toList();
        for (final rendered in texts) {
          for (final forbidden in [
            'stake',
            'usdc',
            'lamports',
            'pnl',
            'payout',
          ]) {
            expect(
              rendered.contains(forbidden) && !rendered.contains('no stake'),
              isFalse,
              reason: '$id rendered "$rendered"',
            );
          }
        }
      }
    });

    testWidgets('a demo-venue receipt is labelled as demo data', (
      tester,
    ) async {
      final repo = MockCallsRepository();
      // Resolve the demo market so a settled receipt exists for it.
      repo.debugResolveMarket(
        marketId: 'market_sol_flip',
        resolution: Resolution.no,
      );
      final detail = await repo.fetchCall(
        callId: 'call_zed_sol',
        viewerUserId: 'user_zed',
      );
      final receipt = CallReceipt.fromEntry(
        detail.entry,
        shareUrl: repo.shareLinkForCall('call_zed_sol'),
      );

      expect(receipt.venueIsDemo, isTrue);
      expect(receipt.outcome, CallOutcome.correct);

      await tester.pumpWidget(testApp(CallReceiptCard(receipt: receipt)));
      await tester.pump();
      expect(
        find.text('DEMO DATA — sample catalog, not a live market result.'),
        findsOneWidget,
      );
    });
  });

  group('CallsFormat never invents a number', () {
    test('a null probability renders as an em dash, not 0%', () {
      expect(CallsFormat.probability(null), '—');
      expect(CallsFormat.probability(double.nan), '—');
      expect(CallsFormat.probability(0), '0%');
    });

    test('a missing price says so instead of showing an age of zero', () {
      expect(CallsFormat.dataAge(null), 'No price published yet');
      expect(CallsFormat.dataAge(const Duration(hours: 5)), 'Price 5h old');
    });

    test('a missing close time says so', () {
      expect(CallsFormat.untilClose(null), 'No close time published');
    });

    test('outcome sentences are all distinct and name VOID explicitly', () {
      final sentences =
          CallOutcome.values.map(CallsFormat.outcomeSentence).toSet();
      expect(sentences.length, CallOutcome.values.length);
      expect(
        CallsFormat.outcomeSentence(CallOutcome.voided),
        contains('Not a win, not a loss'),
      );
    });

    test('the shared CAPTION says demo — the chrome does not travel', () async {
      // Every other demo affordance lives on a screen. The caption is the only
      // thing that reaches WhatsApp or X, where no badge follows it. Without a
      // marker here, a fabricated receipt about a real-world event posts as a
      // real result under the product's name.
      final repo = MockCallsRepository();
      final feed = await repo.fetchFeed(mode: CallFeedMode.global);
      final settled = feed.entries.firstWhere((e) => e.result != null);
      final receipt = CallReceipt.fromEntry(
        settled,
        shareUrl: repo.shareLinkForCall(settled.call.id),
      );

      expect(receipt.venueIsDemo, isTrue);
      expect(receipt.shareCaption, contains('DEMO DATA'));
      expect(receipt.shareCaption, contains('not a real market result'));
    });

    test('every market the mock invents is branded fixture', () {
      // The regression this guards: five of six mock markets used to claim
      // `venue: jupiter`, so isDemo was false and NO demo affordance rendered
      // for them — including a fabricated FOMC resolution with a
      // federalreserve.gov source string.
      final repo = MockCallsRepository();
      for (final m in repo.debugMarkets) {
        expect(
          m.venue,
          MarketVenue.fixture,
          reason:
              'Mock market "${m.question}" claims venue ${m.venue.name}. '
              'Everything the mock serves is invented, so it must brand as '
              'fixture or the demo labelling silently does nothing.',
        );
      }
    });

    test('a demo market is attributed as demo, not as a live venue', () async {
      final repo = MockCallsRepository();
      // Both markets are constructed here rather than borrowed from the seed.
      // This asserts a property of venueAttribution, so it must not depend on
      // how the mock happens to brand its catalog — and the mock's markets are
      // all `fixture` now, because every one of them is invented.
      final demo = repo.debugMarkets.firstWhere((m) => m.venue.isDemo);
      final live = demo.copyWith(venue: MarketVenue.jupiter);
      expect(
        CallsFormat.venueAttribution(demo),
        'Demo catalog · not a live market',
      );
      expect(CallsFormat.venueAttribution(live), 'Priced by Jupiter');
    });
  });
}
