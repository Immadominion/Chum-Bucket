import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/widgets/call_receipt_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'bff_calls_fixtures.dart';

const marketId = '11111111-1111-5111-8111-111111111111';
Map<String, dynamic> priceJson() => {
  'id': '22222222-2222-5222-8222-222222222222',
  'marketId': marketId,
  'venue': 'panta',
  'currency': 'USDC',
  'unit': 'per_share',
  'yesPrice': '1.250000000000000001',
  'noPrice': '0.35',
  'observedAt': kNowMs,
  'source': 'venue',
  'attribution': 'Powered by Panta',
  'executable': false,
};
Map<String, dynamic> nativeCall() => {
  ...callJson(marketId: marketId, entryProbability: null, snapshotId: null),
  'lockedAt': kNowMs,
  'createdAt': kNowMs,
  'entryPrice': priceJson(),
};
Widget app(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (_, __) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
);

void main() {
  test('independent decimal strings round trip without complementary odds', () {
    final p = SharePriceSnapshot.fromJson(priceJson());
    expect(p.toJson(), priceJson());
    expect(p.priceFor(Side.no), '0.35');
    // A price above a whole share is kept verbatim but has no honest odds.
    expect(p.yesPrice, '1.250000000000000001');
    expect(CallsFormat.odds(p.yesPrice), isNull);
    expect(CallsFormat.sidesOdds(p), 'YES — · NO 35%');
    expect(MarketVenue.fromWire('panta'), MarketVenue.panta);
  });
  for (final patch in <Map<String, dynamic>>[
    {'yesPrice': 1.25},
    {'noPrice': '-1'},
    {'yesPrice': '1e3'},
    {'currency': 'USD'},
    {'unit': 'probability'},
    {'executable': true},
    {'stake': '123'},
    {'observedAt': -1},
  ]) {
    test('rejects malformed ${patch.keys.first}: ${patch.values.first}', () {
      expect(
        () => SharePriceSnapshot.fromJson({...priceJson(), ...patch}),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  }
  test('freshness distinguishes stale, future and missing side prices', () {
    final p = SharePriceSnapshot.fromJson(priceJson());
    expect(p.isUsableAt(DateTime.fromMillisecondsSinceEpoch(kNowMs)), isTrue);
    expect(
      p.isUsableAt(DateTime.fromMillisecondsSinceEpoch(kNowMs + 600001)),
      isFalse,
    );
    expect(
      p.isUsableAt(DateTime.fromMillisecondsSinceEpoch(kNowMs - 1)),
      isFalse,
    );
    expect(
      SharePriceSnapshot.fromJson({
        ...priceJson(),
        'noPrice': null,
      }).isUsableAt(DateTime.fromMillisecondsSinceEpoch(kNowMs)),
      isFalse,
    );
    expect(CallsFormat.odds(null), isNull);
  });
  test(
    'call pins native prices while historical probability calls still parse',
    () {
      final c = Call.fromJson(nativeCall());
      expect(c.entryProbability, isNull);
      expect(c.snapshotId, isNull);
      expect(c.toJson()['entryPrice'], priceJson());
      expect(Call.fromJson(callJson()).entryPrice, isNull);
      for (final patch in [
        {'marketId': 'other'},
        {'entryProbability': 0.5},
        {'snapshotId': 'probability-row'},
        {'lockedAt': kNowMs - 1},
      ]) {
        expect(
          () => Call.fromJson({...nativeCall(), ...patch}),
          throwsA(isA<CallVocabularyException>()),
        );
      }
    },
  );
  test(
    'market response carries native prices and refuses cross-provider evidence',
    () {
      final json = {
        ...marketDetailJson(
          market: marketJson(id: marketId, venue: 'panta'),
          snapshot: null,
        ),
        'sharePrice': priceJson(),
      };
      expect(
        marketDetailFromJson(json).sharePrice?.yesPrice,
        priceJson()['yesPrice'],
      );
      expect(marketDetailFromJson(json).snapshot, isNull);
      expect(
        () => marketDetailFromJson({
          ...json,
          'market': marketJson(id: marketId, venue: 'polymarket'),
        }),
        throwsA(isA<CallVocabularyException>()),
      );
      expect(
        () => marketDetailFromJson({...json, 'snapshot': snapshotJson()}),
        throwsA(isA<CallVocabularyException>()),
      );
    },
  );
  testWidgets(
    'receipt card shows the odds at call, timestamp and Panta attribution',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final entry = callFeedEntryFromJson(
        feedEntryJson(
          call: nativeCall(),
          market: marketJson(id: marketId, venue: 'panta'),
          result: resultJson(),
        ),
      );
      final receipt = CallReceipt.fromEntry(
        entry,
        shareUrl: 'https://chumbucket.fun/c/test',
      );
      await tester.pumpWidget(app(CallReceiptCard(receipt: receipt)));
      await tester.pumpAndSettle();
      // Odds, never a per-share figure: a side above a whole share has no
      // honest percent and reads "—".
      expect(find.text('Odds at call'), findsOneWidget);
      expect(find.text('YES — · NO 35%'), findsOneWidget);
      expect(find.text('1.250000000000000001'), findsNothing);
      expect(find.text('0.35'), findsNothing);
      expect(find.text('Entry probability'), findsNothing);
      expect(find.text('Powered by Panta'), findsOneWidget);
      expect(find.text('Odds observed'), findsOneWidget);
      expect(find.byKey(const ValueKey('free-marker')), findsOneWidget);
      expect(receipt.shareCaption, contains('Powered by Panta'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'composer leaves pricing to the server and says a refusal plainly',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final provider = CallsProvider(
        repository: MockCallsRepository(latency: Duration.zero),
      );
      provider.setViewer(MockCallsRepository.demoViewerUserId);
      addTearDown(provider.dispose);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => MaterialApp(
                home: ChangeNotifierProvider.value(
                  value: provider,
                  child: Scaffold(
                    body: CallComposerSheet(
                      market: VenueMarket.fromJson(
                        marketJson(id: marketId, venue: 'panta'),
                      ),
                      initialSide: Side.yes,
                    ),
                  ),
                ),
              ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call YES'));
      await tester.pumpAndSettle();
      // No price on the phone is not a reason to refuse here: the server
      // stamps (and, when it lapsed, re-reads) Panta's price itself. This
      // market is unknown to the seeded catalog, so the lock is refused —
      // beside the button, with the spinner stopped, never as "stale".
      expect(find.byKey(const ValueKey('call-inline-error')), findsOneWidget);
      expect(find.textContaining('stale'), findsNothing);
      expect(find.text('Please wait…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
