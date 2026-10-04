// Funded-position lifecycle in the app: positions, claims, the order row.
// Synthetic wire fixtures only — no network, wallet, signature or trade.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:chumbucket/features/calls/presentation/widgets/calls_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'panta_trading_controller_test.dart'
    show
        syntheticCall,
        syntheticInput,
        syntheticOrderJson,
        syntheticSigned,
        syntheticTime,
        syntheticUnsigned,
        syntheticVenueMarket,
        syntheticWalletAddress,
        syntheticWire;

const _claimId = '44444444-4444-4444-8444-444444444444';
const _market = '22222222-2222-4222-8222-222222222222';

Map<String, Object?> positionJson({
  String orderId = 'ord_synthetic',
  String status = 'open',
  String? value = '3000000',
  String? pnl = '1000000',
  String? current = '0.75',
  Map<String, Object?>? claim,
}) => {
  'orderId': orderId,
  'callId': syntheticCall,
  'marketId': _market,
  'venueMarketId': syntheticVenueMarket,
  'question': 'Will the synthetic asset close above the threshold?',
  'side': 'YES',
  'owner': syntheticWalletAddress,
  'status': status,
  'costBaseUnits': '2000000',
  'shares': '4',
  'entryPrice': '0.5',
  'currentPrice': current,
  'priceObservedAt': current == null ? null : syntheticTime,
  'valueBaseUnits': value,
  'pnlBaseUnits': pnl,
  'walletShares': '4',
  'claim': claim,
  'pantaUrl': 'https://panta.market/market/$syntheticVenueMarket',
  'submittedAt': syntheticTime,
  'filledAt': status == 'pending' ? null : syntheticTime + 1000,
  'fillTxSignature': null,
};

Map<String, Object?> pageJson(
  List<Map<String, Object?>> positions, {
  String holdings = 'live',
}) => {
  'positions': positions,
  'totals': {
    'costBaseUnits': '2000000',
    'valueBaseUnits': '3000000',
    'pnlBaseUnits': '1000000',
    'counted': positions.isEmpty ? 0 : 1,
  },
  'holdings': holdings,
  'sell': {'supported': false, 'reason': 'Panta has no sell API.'},
  'servedAt': syntheticTime,
  'attribution': 'Powered by Panta',
};

Map<String, Object?> claimViewJson({String state = 'BUILT', String? payout}) =>
    {
      'claimId': _claimId,
      'orderId': 'ord_synthetic',
      'venueMarketId': syntheticVenueMarket,
      'owner': syntheticWalletAddress,
      'state': state,
      'signature': null,
      'payoutBaseUnits': payout,
      'createdAt': syntheticTime,
      'updatedAt': syntheticTime,
      'expiresAt': syntheticTime + 60000,
      'attribution': 'Powered by Panta',
    };

Map<String, Object?> claimPreparedJson({bool inFlight = false}) => {
  'claim': claimViewJson(state: inFlight ? 'SUBMITTED' : 'BUILT'),
  'transaction':
      inFlight
          ? null
          : {
            'venue': 'panta',
            'encoding': 'solana-tx-base64',
            'payload': base64Encode(syntheticUnsigned()),
            'expiresAt': syntheticTime + 60000,
            'demo': false,
          },
  'review':
      inFlight
          ? null
          : {
            'outcome': 'YES',
            'winningShares': '4',
            'estimatedPayoutUsdc': '4',
            'attribution': 'Powered by Panta',
          },
};

class _Wallet implements PantaWalletPort {
  int signs = 0;
  Object? throwOnSign;
  @override
  Future<Uint8List> signTransaction(Uint8List unsigned) async {
    signs++;
    if (throwOnSign != null) throw throwOnSign!;
    return syntheticSigned(unsigned);
  }
}

class _Rig {
  _Rig() {
    transport = MockClient((request) async {
      requests.add(request);
      final name = request.url.path.split('/').last;
      final override = replies[name];
      if (override != null) return override(request);
      return switch (name) {
        'pantaTrading.positions' => syntheticWire(
          pages.isEmpty ? pageJson([]) : pages.removeAt(0),
        ),
        'pantaTrading.claimPrepare' => syntheticWire(claimPreparedJson()),
        'pantaTrading.claimSubmit' => syntheticWire(
          claimViewJson(state: 'SUBMITTED'),
        ),
        'pantaTrading.callOrder' => syntheticWire({
          'order': orders.isEmpty ? null : orders.removeAt(0),
        }),
        'pantaTrading.order' => syntheticWire(
          syntheticOrderJson(
            state: 'SUBMITTED',
            amount: '2000000',
            key: '11111111-1111-4111-8111-111111111111',
            updatedAt: syntheticTime + 1,
          ),
        ),
        _ => throw StateError('unexpected $name'),
      };
    });
    client = PantaTradingClient(
      baseUri: Uri.parse('https://bff.invalid/trpc'),
      session:
          () => const PantaSession(
            accountId: 'acct',
            accessToken: 'synthetic-token',
          ),
      client: transport,
    );
    controller = PantaPositionsController(
      client: client,
      signerFor: (wallet, intent) => signerAvailable ? wallet_ : null,
      now: () => DateTime.fromMillisecondsSinceEpoch(syntheticTime),
      newIdempotencyKey: () => '55555555-5555-4555-8555-555555555555',
      refreshEvery: const Duration(seconds: 15),
    );
  }
  late final MockClient transport;
  late final PantaTradingClient client;
  late final PantaPositionsController controller;
  final requests = <http.Request>[];
  final pages = <Map<String, Object?>>[];
  final orders = <Map<String, Object?>?>[];
  final replies = <String, FutureOr<http.Response> Function(http.Request)>{};
  final wallet_ = _Wallet();
  bool signerAvailable = true;
  List<Map<String, dynamic>> inputs(String name) => [
    for (final r in requests)
      if (r.url.path.endsWith('pantaTrading.$name')) syntheticInput(r),
  ];
  void dispose() {
    controller.dispose();
    client.close();
  }
}

http.Response trpcError(String code, int status) => http.Response(
  jsonEncode({
    'error': {
      'json': {
        'message': 'synthetic',
        'data': {'code': code, 'httpStatus': status},
      },
    },
  }),
  status,
);

Widget host(Widget child, {double scale = 1}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (_, _) => MaterialApp(
        theme: AppTheme.lightTheme,
        builder:
            (context, inner) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: inner!,
            ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
);

/// Lets synthetic HTTP replies land without waiting for a spinner to stop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  group('lifecycle contracts', () {
    test('a positions page parses exactly, with no rounding', () {
      final page = PantaPositionsPage.fromJson(
        pageJson([
          positionJson(),
          positionJson(
            orderId: 'ord_lost',
            status: 'lost',
            value: '0',
            pnl: '-2000000',
            current: '0',
          ),
        ]),
      );
      expect(page.positions.first.status, PantaPositionStatus.open);
      expect(page.positions.first.costBaseUnits, BigInt.from(2000000));
      expect(page.positions.last.pnlBaseUnits, BigInt.from(-2000000));
      expect(
        page.positions.first.pantaUrl.toString(),
        'https://panta.market/market/$syntheticVenueMarket',
      );
      expect(page.sellSupported, isFalse);
      expect(page.holdings, PantaHoldingsState.live);
    });

    test('a contract mismatch is refused, never shown', () {
      for (final bad in [
        positionJson(status: 'mooning'),
        positionJson(value: '3000000', pnl: null),
        positionJson(value: '-1', pnl: '-1'),
        {
          ...positionJson(),
          'pantaUrl': 'https://live-api.panta.market/api/v1/markets/x/',
        },
        {...positionJson(), 'owner': 'not-a-wallet'},
        {...positionJson(), 'costBaseUnits': '1.5'},
      ]) {
        expect(
          () => PantaPositionsPage.fromJson(pageJson([bad])),
          throwsA(isA<PantaException>()),
          reason: '$bad',
        );
      }
      expect(
        () => PantaPositionsPage.fromJson({
          ...pageJson([]),
          'sell': {'supported': true},
        }),
        throwsA(isA<PantaException>()),
      );
      expect(
        () => PantaClaimView.fromJson(claimViewJson(state: 'CONFIRMED')),
        throwsA(isA<PantaException>()),
        reason: 'CONFIRMED without a proven payout',
      );
    });

    test('money reads as exact dollars, prices as odds', () {
      expect(PantaMoney.dollars(BigInt.from(5000000)), '\$5');
      expect(PantaMoney.dollars(BigInt.from(9200000)), '\$9.20');
      expect(
        PantaMoney.dollars(BigInt.from(-1500000), signed: true),
        '-\$1.50',
      );
      expect(PantaMoney.dollars(BigInt.from(1000000), signed: true), '+\$1');
      expect(PantaMoney.dollars(BigInt.zero, signed: true), '\$0');
      expect(PantaMoney.dollars(BigInt.parse('1234567890')), '\$1,234.56789');
      // Never rounded away.
      expect(PantaMoney.dollars(BigInt.from(1)), '\$0.000001');
      expect(CallsFormat.odds('0.520000'), '52%');
      expect(CallsFormat.odds('1'), '100%');
      expect(
        pantaMarketUri('abc').toString(),
        'https://panta.market/market/abc',
      );
    });
  });

  group('client', () {
    test(
      'lifecycle procedures are session-keyed POSTs with no identity input',
      () async {
        final rig = _Rig()..pages.add(pageJson([positionJson()]));
        addTearDown(rig.dispose);
        await rig.client.positions(accountId: 'acct');
        await rig.client.callOrder(callId: syntheticCall, accountId: 'acct');
        final positions = rig.requests.first;
        expect(positions.method, 'POST');
        expect(positions.headers['authorization'], 'Bearer synthetic-token');
        expect(jsonDecode(positions.body), {'json': <String, Object?>{}});
        expect(rig.inputs('callOrder').single, {'callId': syntheticCall});
      },
    );

    test('a server without funded positions reads as unavailable', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.replies['pantaTrading.positions'] =
          (_) => trpcError('FORBIDDEN', 403);
      await expectLater(
        rig.client.positions(accountId: 'acct'),
        throwsA(
          isA<PantaException>().having(
            (e) => e.code,
            'code',
            PantaErrorCode.unavailable,
          ),
        ),
      );
    });
  });

  group('claims', () {
    test(
      'one durable intent, the selected signer, exact bytes to submit',
      () async {
        final rig =
            _Rig()
              ..pages.addAll([
                pageJson([
                  positionJson(
                    status: 'won_claimable',
                    current: '1',
                    value: '4000000',
                    pnl: '2000000',
                  ),
                ]),
                pageJson([
                  positionJson(
                    status: 'claiming',
                    current: '1',
                    value: '4000000',
                    pnl: '2000000',
                    claim: {
                      'claimId': _claimId,
                      'state': 'SUBMITTED',
                      'signature': null,
                      'payoutBaseUnits': null,
                    },
                  ),
                ]),
              ]);
        addTearDown(rig.dispose);
        await rig.controller.load();
        final position = rig.controller.page!.positions.single;
        await rig.controller.claim(position);
        expect(rig.inputs('claimPrepare').single, {
          'orderId': 'ord_synthetic',
          'idempotencyKey': '55555555-5555-4555-8555-555555555555',
        });
        expect(rig.wallet_.signs, 1);
        expect(rig.inputs('claimSubmit').single, {
          'claimId': _claimId,
          'signedTransaction': base64Encode(
            syntheticSigned(syntheticUnsigned()),
          ),
        });
        expect(
          rig.controller.page!.positions.single.status,
          PantaPositionStatus.claiming,
        );
        expect(
          rig.controller.claimProgress('ord_synthetic').phase,
          PantaClaimPhase.submitted,
        );
      },
    );

    test(
      'no signer for the wallet: nothing is signed, the person is told why',
      () async {
        final rig = _Rig()..signerAvailable = false;
        rig.pages.add(
          pageJson([
            positionJson(
              status: 'won_claimable',
              current: '1',
              value: '4000000',
              pnl: '2000000',
            ),
          ]),
        );
        addTearDown(rig.dispose);
        await rig.controller.load();
        await rig.controller.claim(rig.controller.page!.positions.single);
        expect(rig.wallet_.signs, 0);
        expect(rig.inputs('claimSubmit'), isEmpty);
        expect(
          rig.controller.claimProgress('ord_synthetic').message,
          contains('claim on Panta'),
        );
      },
    );

    test(
      'a claim already in flight on the server is never signed again',
      () async {
        final rig = _Rig();
        rig.replies['pantaTrading.claimPrepare'] =
            (_) => syntheticWire(claimPreparedJson(inFlight: true));
        rig.pages.add(
          pageJson([
            positionJson(
              status: 'won_claimable',
              current: '1',
              value: '4000000',
              pnl: '2000000',
            ),
          ]),
        );
        addTearDown(rig.dispose);
        await rig.controller.load();
        await rig.controller.claim(rig.controller.page!.positions.single);
        expect(rig.wallet_.signs, 0);
        expect(rig.inputs('claimSubmit'), isEmpty);
      },
    );

    test(
      'a lost submit reply retries the identical signed bytes without re-signing',
      () async {
        final rig = _Rig();
        var fail = true;
        rig.replies['pantaTrading.claimSubmit'] = (_) {
          if (fail) throw http.ClientException('synthetic drop');
          return syntheticWire(claimViewJson(state: 'SUBMITTED'));
        };
        rig.pages.add(
          pageJson([
            positionJson(
              status: 'won_claimable',
              current: '1',
              value: '4000000',
              pnl: '2000000',
            ),
          ]),
        );
        addTearDown(rig.dispose);
        await rig.controller.load();
        final position = rig.controller.page!.positions.single;
        await rig.controller.claim(position);
        expect(
          rig.controller.claimProgress(position.orderId).canRetrySubmit,
          isTrue,
        );
        fail = false;
        await rig.controller.claim(position);
        final submits = rig.inputs('claimSubmit');
        expect(submits, hasLength(2));
        expect(submits.first, submits.last);
        expect(rig.wallet_.signs, 1);
        expect(rig.inputs('claimPrepare'), hasLength(1));
      },
    );

    test(
      'a refused or already-failed attempt never traps the next tap on a dead key',
      () async {
        final rig = _Rig();
        addTearDown(rig.dispose);
        var n = 0;
        final controller = PantaPositionsController(
          client: rig.client,
          signerFor: (wallet, intent) => rig.wallet_,
          now: () => DateTime.fromMillisecondsSinceEpoch(syntheticTime),
          newIdempotencyKey: () => '55555555-5555-4555-8555-55555555555${n++}',
        );
        addTearDown(controller.dispose);
        rig.pages.add(
          pageJson([
            positionJson(
              status: 'won_claimable',
              current: '1',
              value: '4000000',
              pnl: '2000000',
            ),
          ]),
        );
        await controller.load();
        final position = controller.page!.positions.single;
        // 1. The server answers and refuses: that key is spent.
        rig.replies['pantaTrading.claimPrepare'] =
            (_) => trpcError('BAD_REQUEST', 400);
        await controller.claim(position);
        expect(rig.wallet_.signs, 0);
        expect(
          controller.claimProgress(position.orderId).message,
          contains('did not offer a claim'),
        );
        // 2. The old key would only replay that failure; a FAILED replay is
        //    retired at once and a fresh key reviews a real claim.
        var calls = 0;
        rig.replies['pantaTrading.claimPrepare'] = (_) {
          calls++;
          return calls == 1
              ? syntheticWire({
                'claim': claimViewJson(state: 'FAILED'),
                'transaction': null,
                'review': null,
              })
              : syntheticWire(claimPreparedJson());
        };
        await controller.claim(position);
        final keys = [
          for (final input in rig.inputs('claimPrepare'))
            input['idempotencyKey'],
        ];
        expect(keys, hasLength(3));
        expect(keys.toSet(), hasLength(3), reason: 'never reuse a dead key');
        expect(rig.wallet_.signs, 1);
        expect(rig.inputs('claimSubmit'), hasLength(1));
      },
    );

    test(
      'a lost prepare reply keeps its key; the copy says nothing was signed',
      () async {
        final rig = _Rig();
        addTearDown(rig.dispose);
        rig.pages.add(
          pageJson([
            positionJson(
              status: 'won_claimable',
              current: '1',
              value: '4000000',
              pnl: '2000000',
            ),
          ]),
        );
        await rig.controller.load();
        final position = rig.controller.page!.positions.single;
        var drop = true;
        rig.replies['pantaTrading.claimPrepare'] = (_) {
          if (drop) throw http.ClientException('synthetic drop');
          return syntheticWire(claimPreparedJson());
        };
        await rig.controller.claim(position);
        expect(
          rig.controller.claimProgress(position.orderId).message,
          contains('Nothing was signed'),
        );
        drop = false;
        await rig.controller.claim(position);
        final keys = [
          for (final input in rig.inputs('claimPrepare'))
            input['idempotencyKey'],
        ];
        expect(keys, hasLength(2));
        expect(keys.first, keys.last, reason: 'same intent after a lost reply');
      },
    );

    test(
      'a signed claim the server can never send is dropped, not retried forever',
      () async {
        final rig = _Rig();
        addTearDown(rig.dispose);
        var first = true;
        rig.replies['pantaTrading.claimSubmit'] = (_) {
          if (first) {
            first = false;
            throw http.ClientException('synthetic drop');
          }
          return trpcError('BAD_REQUEST', 400);
        };
        // The approval was never stored and has expired on the server.
        rig.replies['pantaTrading.claim'] =
            (_) => syntheticWire({
              ...claimViewJson(state: 'BUILT'),
              'expiresAt': syntheticTime - 1,
            });
        rig.pages.add(
          pageJson([
            positionJson(
              status: 'won_claimable',
              current: '1',
              value: '4000000',
              pnl: '2000000',
            ),
          ]),
        );
        await rig.controller.load();
        final position = rig.controller.page!.positions.single;
        await rig.controller.claim(position);
        expect(
          rig.controller.claimProgress(position.orderId).canRetrySubmit,
          isTrue,
        );
        await rig.controller.retryClaimSubmit(position.orderId);
        final progress = rig.controller.claimProgress(position.orderId);
        expect(progress.canRetrySubmit, isFalse);
        expect(progress.message, contains('can no longer be sent'));
        // The next tap reviews a fresh claim instead of resending dead bytes.
        rig.replies.remove('pantaTrading.claimSubmit');
        await rig.controller.claim(position);
        expect(rig.inputs('claimPrepare'), hasLength(2));
        expect(rig.wallet_.signs, 2);
      },
    );

    test('a cancelled wallet approval submits nothing', () async {
      final rig = _Rig();
      rig.wallet_.throwOnSign = const PantaWalletCancelled();
      rig.pages.add(
        pageJson([
          positionJson(
            status: 'won_claimable',
            current: '1',
            value: '4000000',
            pnl: '2000000',
          ),
        ]),
      );
      addTearDown(rig.dispose);
      await rig.controller.load();
      await rig.controller.claim(rig.controller.page!.positions.single);
      expect(rig.inputs('claimSubmit'), isEmpty);
      expect(
        rig.controller.claimProgress('ord_synthetic').message,
        'Wallet approval was cancelled.',
      );
    });
  });

  group('positions view', () {
    testWidgets(
      'shows real figures, a claim action and Panta links; refreshes while pending',
      (tester) async {
        final rig =
            _Rig()
              ..pages.addAll([
                pageJson([
                  positionJson(),
                  positionJson(
                    orderId: 'ord_won',
                    status: 'won_claimable',
                    current: '1',
                    value: '4000000',
                    pnl: '2000000',
                  ),
                  positionJson(
                    orderId: 'ord_pending',
                    status: 'pending',
                    current: null,
                    value: null,
                    pnl: null,
                  ),
                ]),
                pageJson([positionJson()]),
              ]);
        addTearDown(rig.dispose);
        final opened = <Uri>[];
        await tester.pumpWidget(
          host(
            PantaPositionsView(
              controller: rig.controller,
              opener: (uri) async {
                opened.add(uri);
                return true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your Panta positions'), findsOneWidget);
        // Money as dollars (the total and each card), prices as odds.
        expect(find.text('\$3'), findsOneWidget);
        expect(find.text('+\$1'), findsWidgets);
        expect(find.text('50%'), findsWidgets);
        expect(find.textContaining('USDC'), findsNothing);
        expect(find.text('Won · ready to claim'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('panta-claim-ord_won')),
          findsOneWidget,
        );
        expect(find.text('Manage on Panta'), findsOneWidget);
        expect(find.textContaining('Sell on Panta'), findsNothing);
        expect(find.text('Order pending'), findsOneWidget);
        expect(find.textContaining('live-api'), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('panta-open-ord_synthetic')),
        );
        await tester.tap(
          find.byKey(const ValueKey('panta-open-ord_synthetic')),
        );
        await tester.pumpAndSettle();
        expect(
          opened.single.toString(),
          'https://panta.market/market/$syntheticVenueMarket',
        );
        // A pending order keeps the list refreshing on its own.
        final before = rig.inputs('positions').length;
        await tester.pump(const Duration(seconds: 16));
        await tester.pumpAndSettle();
        expect(rig.inputs('positions').length, before + 1);
        expect(find.text('Order pending'), findsNothing);
      },
    );

    testWidgets('fits a 320 dp phone at large text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rig =
          _Rig()
            ..pages.add(
              pageJson([
                positionJson(),
                positionJson(
                  orderId: 'ord_won',
                  status: 'won_claimable',
                  current: '1',
                  value: '4000000',
                  pnl: '2000000',
                ),
              ]),
            );
      addTearDown(rig.dispose);
      await tester.pumpWidget(
        host(PantaPositionsView(controller: rig.controller), scale: 1.8),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Claim winnings'), findsOneWidget);
    });

    testWidgets('an unconfigured server says so instead of showing zeros', (
      tester,
    ) async {
      final rig = _Rig();
      rig.replies['pantaTrading.positions'] =
          (_) => trpcError('FORBIDDEN', 403);
      addTearDown(rig.dispose);
      await tester.pumpWidget(
        host(PantaPositionsView(controller: rig.controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Positions are not available yet'), findsOneWidget);
      expect(find.textContaining('USDC'), findsNothing);
    });
  });

  group('order row on a call', () {
    Map<String, Object?> order(String state) => syntheticOrderJson(
      state: state,
      amount: '2000000',
      key: '11111111-1111-4111-8111-111111111111',
      updatedAt: syntheticTime + 1,
    );

    testWidgets('a submitted order refreshes itself until it is confirmed', (
      tester,
    ) async {
      final rig = _Rig()..orders.addAll([order('SUBMITTED'), order('FILLED')]);
      addTearDown(rig.dispose);
      await tester.pumpWidget(
        host(PantaOrderStatusRow(callId: syntheticCall, client: rig.client)),
      );
      // A pending row animates a spinner, so settle on short pumps only.
      await settle(tester);
      expect(
        find.textContaining('Order submitted · \$2 on YES'),
        findsOneWidget,
      );
      expect(find.textContaining('Funded'), findsNothing);
      await tester.pump(const Duration(seconds: 9));
      await settle(tester);
      expect(find.text('Funded · \$2 on YES'), findsOneWidget);
      expect(rig.inputs('callOrder'), hasLength(2));
      // Confirmed: no more polling.
      await tester.pump(const Duration(seconds: 60));
      expect(rig.inputs('callOrder'), hasLength(2));
    });

    testWidgets(
      'a failed order says nothing was funded; no order shows nothing',
      (tester) async {
        final rig = _Rig()..orders.add(order('FAILED'));
        addTearDown(rig.dispose);
        await tester.pumpWidget(
          host(PantaOrderStatusRow(callId: syntheticCall, client: rig.client)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Order didn’t go through'), findsOneWidget);
        final empty = _Rig();
        addTearDown(empty.dispose);
        await tester.pumpWidget(
          host(
            PantaOrderStatusRow(callId: syntheticCall, client: empty.client),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Container), findsNothing);
      },
    );

    testWidgets(
      'check now asks the server to verify, then re-reads the ledger',
      (tester) async {
        final rig =
            _Rig()..orders.addAll([order('SUBMITTED'), order('SUBMITTED')]);
        addTearDown(rig.dispose);
        await tester.pumpWidget(
          host(PantaOrderStatusRow(callId: syntheticCall, client: rig.client)),
        );
        await settle(tester);
        await tester.tap(find.text('Check now'));
        await settle(tester);
        expect(rig.inputs('order').single, {'orderId': 'synthetic-order'});
        expect(rig.inputs('callOrder'), hasLength(2));
      },
    );
  });
}
