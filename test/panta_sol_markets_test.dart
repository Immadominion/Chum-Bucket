// Panta's SOL-quoted markets: callable, priced in their own unit, never
// offered a trade. The server reads them from Panta's program (the partner
// API lists only USDC markets) and marks each served market with its
// `quoteCurrency` and whether Chumbucket can trade it (`tradable`).
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/onboarding/domain/onboarding_data.dart';
import 'package:chumbucket/features/onboarding/onboarding_copy.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/welcome_phone.dart';
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

  group('market detail with your own call', () {
    // The one place a Trade action can appear is beside the viewer's own
    // call, so that is where a SOL-quoted market must still have none. The
    // USDC case pins the control by name: rename it in a redesign and this
    // pair fails together instead of the SOL half passing vacuously.
    for (final (quote, tradable) in [('SOL', false), ('USDC', true)]) {
      testWidgets(
        '$quote: ${tradable ? 'Trade beside' : 'no Trade, no trade copy beside'} your call',
        (tester) async {
          final provider = CallsProvider(
            repository: _OwnCallMarketRepository(
              quote: quote,
              tradable: tradable,
            ),
          )..setViewer(PantaOwnCallRepository.viewer);
          addTearDown(provider.dispose);
          await mount(
            tester,
            provider,
            const MarketDetailScreen(marketId: _uuid),
          );
          tester.view.physicalSize = const Size(390, 5000);
          await tester.pumpAndSettle();
          final trade = find.widgetWithText(OutlinedButton, 'Trade');
          if (tradable) {
            expect(trade, findsOneWidget);
            expect(
              tester.widget<OutlinedButton>(trade).onPressed,
              isNotNull,
              reason: 'your own call on a USDC market opens its trade',
            );
          } else {
            expect(find.text('Trade'), findsNothing);
            final tradeCopy =
                _everything(tester)
                    .where(
                      (s) => RegExp('trad', caseSensitive: false).hasMatch(s),
                    )
                    .toList();
            expect(tradeCopy, isEmpty, reason: 'a SOL market offered a trade');
            _expectNoUsdc(tester);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('no USDC anywhere a SOL market is read', () {
    // A tall viewport lays out every section, so nothing hides below a fold.
    Future<void> tall(WidgetTester tester, CallsProvider provider, Widget w) =>
        mount(tester, provider, w).then((_) async {
          tester.view.physicalSize = const Size(390, 5000);
          await tester.pumpAndSettle();
        });
    final solMarket = VenueMarket.fromJson(
      _market(quote: 'SOL', tradable: false),
    );
    final solPrice = SharePriceSnapshot.fromJson({
      ..._price('SOL'),
      'observedAt': DateTime.now().millisecondsSinceEpoch,
    });

    testWidgets('market detail', (tester) async {
      final m = VenueMarket.fromJson({
        ...market('M', const Duration(days: 30)).toJson(),
        'payloadVersion': 2,
        'quoteCurrency': 'SOL',
        'tradable': false,
      });
      final provider = CallsProvider(
        repository: CatalogRepository(
          [m],
          prices: {
            'M': SharePriceSnapshot(
              id: 'p',
              marketId: 'M',
              yesPrice: '0.671739755',
              noPrice: '0.328260245',
              observedAt: DateTime.now().millisecondsSinceEpoch,
              currency: ShareCurrency.sol,
            ),
          },
        ),
      );
      addTearDown(provider.dispose);
      await tall(tester, provider, const MarketDetailScreen(marketId: 'M'));
      expect(find.textContaining('0.67'), findsWidgets);
      _expectNoUsdc(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('your own call', (tester) async {
      final provider = CallsProvider(
        repository: PantaOwnCallRepository(quote: 'SOL', tradable: false),
      )..setViewer(PantaOwnCallRepository.viewer);
      addTearDown(provider.dispose);
      await tall(
        tester,
        provider,
        const CallDetailScreen(callId: 'call_you_fed'),
      );
      expect(find.textContaining('SOL/share'), findsWidgets);
      _expectNoUsdc(tester);
      // Whatever a redesign calls the trade box, none of it reaches a SOL call.
      final offer =
          _everything(tester)
              .where(
                (s) =>
                    RegExp('trad|position', caseSensitive: false).hasMatch(s),
              )
              .toList();
      expect(offer, isEmpty, reason: 'a SOL call offered a trade: $offer');
      expect(tester.takeException(), isNull);
    });

    for (final compact in [false, true]) {
      testWidgets('the composer (compact=$compact)', (tester) async {
        final provider = CallsProvider(
          repository: MockCallsRepository(latency: Duration.zero),
        )..setViewer(MockCallsRepository.demoViewerUserId);
        addTearDown(provider.dispose);
        await tall(
          tester,
          provider,
          CallComposerSheet(
            market: solMarket,
            sharePrice: solPrice,
            initialSide: Side.yes,
            compact: compact,
          ),
        );
        expect(find.textContaining('SOL/share'), findsWidgets);
        _expectNoUsdc(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('welcome phone', () {
    // The approved onboarding phone names one unit for its strip. With USDC
    // and SOL markets side by side it names none: never a unitless
    // "per share", never one unit for both.
    for (final (quotes, label) in [
      (['USDC', 'USDC'], 'USDC/share'),
      (['SOL', 'SOL'], 'SOL/share'),
      (['USDC', 'SOL'], null),
    ]) {
      testWidgets('${quotes.join('+')} strip reads ${label ?? 'no unit'}', (
        tester,
      ) async {
        final markets = [
          for (final (i, q) in quotes.indexed)
            VenueMarket.fromJson({
              ...market('W$i', Duration(days: 3 + i)).toJson(),
              'payloadVersion': q == 'SOL' ? 2 : 1,
              'quoteCurrency': q,
              'tradable': q == 'USDC',
            }),
        ];
        final provider = CallsProvider(repository: CatalogRepository(markets));
        addTearDown(provider.dispose);
        await mount(
          tester,
          provider,
          Builder(
            builder:
                (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: SizedBox(
                    height: 760,
                    child: WelcomePhone(
                      feed: WelcomeFeed([
                        for (final m in markets) LiveMarketItem(m),
                      ]),
                      now: DateTime.now(),
                      onOpenCall: (_) {},
                      onOpenMarket: (_) {},
                    ),
                  ),
                ),
          ),
        );
        if (label == null) {
          expect(find.textContaining('/share'), findsNothing);
          expect(find.textContaining('per share'), findsNothing);
        } else {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
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

/// Every string a person can see or hear on screen: text, rich text,
/// selectable text, and semantics labels. Layout-independent on purpose, so a
/// redesign of these screens still has to keep a SOL price out of USDC.
List<String> _everything(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate()) ...[
    (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '',
    (e.widget as Text).semanticsLabel ?? '',
  ],
  for (final e in find.byType(RichText).evaluate())
    (e.widget as RichText).text.toPlainText(),
  for (final e in find.byType(SelectableText).evaluate())
    (e.widget as SelectableText).data ?? '',
  for (final e in find.byType(Semantics).evaluate())
    (e.widget as Semantics).properties.label ?? '',
];

void _expectNoUsdc(WidgetTester tester) {
  final usdc = _everything(tester).where((s) => s.contains('USDC')).toList();
  expect(usdc, isEmpty, reason: 'a SOL-quoted market read in USDC: $usdc');
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

/// Market detail for the demo viewer's own call, on an open Panta market of
/// one quote: the screen's own-call state, where a trade could be offered.
class _OwnCallMarketRepository extends PantaOwnCallRepository {
  _OwnCallMarketRepository({required super.quote, required super.tradable});

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) async {
    final own =
        (await fetchCall(
          callId: 'call_you_fed',
          viewerUserId: PantaOwnCallRepository.viewer,
        )).entry;
    final market = VenueMarket.fromJson({
      ..._market(quote: quote, tradable: tradable),
      'payloadVersion': quote == 'SOL' ? 2 : 1,
      'closesAt':
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
    });
    return MarketDetail(
      market: market,
      snapshot: null,
      sharePrice: SharePriceSnapshot.fromJson({
        ..._price(quote),
        'observedAt': DateTime.now().millisecondsSinceEpoch,
      }),
      servedAt: DateTime.now().millisecondsSinceEpoch,
      viewerCall: CallFeedEntry(
        call: own.call,
        author: own.author,
        market: market,
        result: null,
        backCount: own.backCount,
        fadeCount: own.fadeCount,
        viewerHasCalled: own.viewerHasCalled,
      ),
    );
  }
}
