// Panta's SOL-quoted markets: callable, priced in their own unit, never
// offered a trade. The server reads them from Panta's program (the partner
// API lists only USDC markets) and marks each served market with its
// `quoteCurrency` and whether Chumbucket can trade it (`tradable`).
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'ui_market_layout_discovery_test.dart'
    show CatalogRepository, market, mount;

const _uuid = '9e1b0f47-eea1-58b0-86ed-9ad51e45698e';

Map<String, dynamic> _price(String currency) => {
  'id': '56fcd920-6a6b-54c2-85e4-e6d7e7fbe7fe',
  'marketId': _uuid,
  'venue': 'panta',
  'currency': currency,
  'unit': 'per_share',
  'yesPrice': '0.671739755',
  'noPrice': '0.328260245',
  'observedAt': 1791074597766,
  'source': 'venue',
  'attribution': 'Powered by Panta',
  'executable': false,
};

Map<String, dynamic> _market({
  Object? quote,
  Object? tradable,
  String venue = 'panta',
}) => {
  'id': _uuid,
  'venue': venue,
  'venueEventId': 'Dhtmh7zc6c2281UTSBdSzxBAiL7wasK51BqWS2waShd6',
  'venueMarketId': 'Dhtmh7zc6c2281UTSBdSzxBAiL7wasK51BqWS2waShd6',
  'question': 'Will HYPE reach \$100 by December 31, 2026?',
  'rulesText':
      'Resolve YES, if HYPE reaches or exceeds \$100. Else resolve NO.',
  'category': 'crypto',
  'outcomes': [
    {'side': 'YES', 'label': 'Yes'},
    {'side': 'NO', 'label': 'No'},
  ],
  'status': 'OPEN',
  'rawStatus': 'secondary',
  'opensAt': null,
  'closesAt': 1798671600000,
  'resolvesAt': 1798671600000,
  'resolutionSource':
      'https://explorer.solana.com/address/Dhtmh7zc6c2281UTSBdSzxBAiL7wasK51BqWS2waShd6',
  'lastSyncedAt': 1791074597766,
  'payloadVersion': 2,
  if (quote != null) 'quoteCurrency': quote,
  if (tradable != null) 'tradable': tradable,
};

void main() {
  group('share prices', () {
    test('a SOL price parses, keeps its unit and round-trips', () {
      final p = SharePriceSnapshot.fromJson(_price('SOL'));
      expect(p.currency, ShareCurrency.sol);
      expect(p.toJson(), _price('SOL'));
      expect(
        SharePriceSnapshot.fromJson(_price('USDC')).currency,
        ShareCurrency.usdc,
      );
    });

    test('an unknown currency is refused, never coerced', () {
      for (final bad in ['USD', 'sol', null, 1]) {
        expect(
          () =>
              SharePriceSnapshot.fromJson({..._price('SOL'), 'currency': bad}),
          throwsA(isA<CallVocabularyException>()),
        );
      }
    });

    test('a price reads in its own unit, never converted', () {
      final sol = SharePriceSnapshot.fromJson(_price('SOL'));
      expect(
        CallsFormat.sharePrice('0.67', currency: sol.currency),
        '0.67 SOL/share',
      );
      expect(CallsFormat.sharePrice('0.52'), '0.52 USDC/share');
      expect(
        CallsFormat.nativePrices(sol),
        'YES 0.671739755 SOL/share · NO 0.328260245 SOL/share',
      );
      expect(
        OnboardingCopy.recordLockedAt('0.67', currency: ShareCurrency.sol),
        'Locked at 0.67 SOL/share',
      );
      expect(CallsFormat.nativePrices(sol), isNot(contains('USDC')));
      expect(CallsFormat.nativePrices(sol), isNot(contains('%')));
    });
  });

  group('tradability', () {
    test('a SOL-quoted market is callable but not tradable', () {
      final m = VenueMarket.fromJson(_market(quote: 'SOL', tradable: false));
      expect(m.quoteCurrency, ShareCurrency.sol);
      expect(m.tradable, isFalse);
      expect(VenueMarket.fromJson(m.toJson()).tradable, isFalse);
    });

    test(
      'the server flag decides; an older server (no flag) only served USDC',
      () {
        expect(
          VenueMarket.fromJson(_market(quote: 'USDC', tradable: true)).tradable,
          isTrue,
        );
        expect(VenueMarket.fromJson(_market()).tradable, isTrue);
        expect(VenueMarket.fromJson(_market(quote: 'SOL')).tradable, isFalse);
        expect(
          VenueMarket.fromJson(
            _market(quote: 'USDC', tradable: false),
          ).tradable,
          isFalse,
        );
        expect(
          VenueMarket.fromJson(_market(venue: 'fixture')).tradable,
          isFalse,
        );
      },
    );
  });

  group('market detail', () {
    for (final (quote, tradable) in [('SOL', false), ('USDC', true)]) {
      testWidgets(
        'a $quote market ${tradable ? 'shows' : 'has no'} Trade button',
        (tester) async {
          final m = VenueMarket.fromJson({
            ...market('M', const Duration(days: 30)).toJson(),
            'payloadVersion': quote == 'SOL' ? 2 : 1,
            'quoteCurrency': quote,
            'tradable': tradable,
          });
          final provider = CallsProvider(
            repository: CatalogRepository(
              [m],
              prices: {
                'M': SharePriceSnapshot(
                  id: 'p',
                  marketId: 'M',
                  yesPrice: '0.67',
                  noPrice: '0.33',
                  observedAt: DateTime.now().millisecondsSinceEpoch,
                  currency: ShareCurrency.tryWire(quote)!,
                ),
              },
            ),
          );
          addTearDown(provider.dispose);
          await mount(
            tester,
            provider,
            const MarketDetailScreen(marketId: 'M'),
          );
          await tester.pumpAndSettle();
          expect(find.text('Trade'), tradable ? findsOneWidget : findsNothing);
          expect(find.textContaining('Make a call'), findsOneWidget);
          expect(find.textContaining('$quote per share'), findsOneWidget);
          if (!tradable) {
            expect(find.textContaining('Trading'), findsNothing);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('call detail', () {
    for (final (label, quote, tradable) in [
      ('SOL-quoted', 'SOL', false),
      ('USDC-quoted', 'USDC', true),
    ]) {
      testWidgets(
        'own call on a $label Panta market ${tradable ? 'offers' : 'never offers'} a trade',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(390, 844);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = PantaOwnCallRepository(quote: quote, tradable: tradable);
          final provider = CallsProvider(repository: repo)
            ..setViewer(MockCallsRepository.demoViewerUserId);
          addTearDown(provider.dispose);
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: provider,
              child: ScreenUtilInit(
                designSize: const Size(390, 844),
                builder:
                    (_, _) => const MaterialApp(
                      home: Scaffold(
                        body: CallDetailScreen(callId: 'call_you_fed'),
                      ),
                    ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // The call's own price reads in its market's unit, near the top.
          expect(find.textContaining('$quote/share'), findsWidgets);
          final offer = find.textContaining('Want a position too?');
          final list = find.byType(Scrollable).first;
          for (var i = 0; i < 12 && offer.evaluate().isEmpty; i++) {
            await tester.drag(list, const Offset(0, -300));
            await tester.pumpAndSettle();
          }
          expect(offer, tradable ? findsOneWidget : findsNothing);
          expect(
            find.textContaining('Review a'),
            tradable ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

/// The demo viewer's own call, moved onto a live Panta market of one quote.
class PantaOwnCallRepository extends MockCallsRepository {
  PantaOwnCallRepository({required this.quote, required this.tradable});
  static const viewer = MockCallsRepository.demoViewerUserId;
  final String quote;
  final bool tradable;

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async {
    final detail = await super.fetchCall(
      callId: callId,
      viewerUserId: viewerUserId,
    );
    final e = detail.entry;
    final market = VenueMarket.fromJson({
      ...e.market.toJson(),
      'id': _uuid,
      'venue': 'panta',
      'payloadVersion': quote == 'SOL' ? 2 : 1,
      'quoteCurrency': quote,
      'tradable': tradable,
    });
    final price = SharePriceSnapshot.fromJson({
      ..._price(quote),
      'observedAt': e.call.lockedAt - 1000,
    });
    final call = Call.fromJson({
      ...e.call.toJson(),
      'marketId': _uuid,
      'entryPrice': price.toJson(),
      'entryProbability': null,
      'snapshotId': null,
    });
    return CallDetail(
      entry: CallFeedEntry(
        call: call,
        author: e.author,
        market: market,
        result: e.result,
        backCount: e.backCount,
        fadeCount: e.fadeCount,
        viewerHasCalled: e.viewerHasCalled,
      ),
      parent: detail.parent,
      responses: detail.responses,
    );
  }
}
