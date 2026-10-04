/// Money on screen: the amount row and its call to action on the composer
/// and on Tail/Fade (hidden when money is off, on markets that can't be
/// traded, and on onboarding's free first call); the same tap opening the
/// deposit sheet and carrying on when the funds land; the compact review,
/// pending until the server says funded; and "$5 on YES" stamps.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_response_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/money/money_controller.dart';
import 'package:chumbucket/features/money/presentation/money_amount_row.dart';
import 'package:chumbucket/features/money/presentation/money_dependencies.dart';
import 'package:chumbucket/features/receipts/data/call_receipt.dart';
import 'package:chumbucket/features/receipts/presentation/widgets/call_receipt_card.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bff_calls_fixtures.dart' show marketJson;
import 'money_fakes.dart';

void usePhone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(390 * 3, 900 * 3);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

CallsProvider callsFor() =>
    CallsProvider(repository: MockCallsRepository())..setViewer(viewerId);

Widget harness({
  required Widget child,
  CallsProvider? calls,
  MoneyController? money,
  MoneyDependencies? deps,
}) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder:
      (_, _) => MultiProvider(
        providers: [
          ChangeNotifierProvider<CallsProvider>.value(value: calls ?? callsFor()),
          if (money != null)
            ChangeNotifierProvider<MoneyController>.value(value: money),
          if (deps != null) Provider<MoneyDependencies>.value(value: deps),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: child))),
      ),
);

/// A button that opens [open] and keeps what it returned.
class Opener extends StatefulWidget {
  const Opener({super.key, required this.open});
  final Future<Object?> Function(BuildContext context) open;
  static Object? last;

  @override
  State<Opener> createState() => _OpenerState();
}

class _OpenerState extends State<Opener> {
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () async => Opener.last = await widget.open(context),
    child: const Text('open'),
  );
}

VenueMarket get tradable => VenueMarket.fromJson(pantaMarketJson());
VenueMarket get demo => VenueMarket.fromJson(marketJson());

FakeMoneyServer moneyServer({String usdc = '12190000'}) =>
    FakeMoneyServer()
      ..on('money.status', [moneyStatusJson()])
      ..on('money.wallet', [moneyWalletJson(usdc: usdc)])
      ..on('money.winnings', [winningsJson(items: [], total: '0')]);

Finder chip(String key) => find.byKey(ValueKey(key));

void main() {
  setUp(() => Opener.last = null);

  group('amount row', () {
    testWidgets('Free · \$5 · \$10 · \$25 · +, and a custom amount', (
      tester,
    ) async {
      usePhone(tester);
      MoneyAmount? picked;
      await tester.pumpWidget(
        harness(
          child: StatefulBuilder(
            builder:
                (context, setState) => MoneyAmountRow(
                  value: picked ?? MoneyAmount(BigInt.from(5000000)),
                  presets: [
                    BigInt.from(5000000),
                    BigInt.from(10000000),
                    BigInt.from(25000000),
                  ],
                  minBaseUnits: BigInt.from(1000000),
                  maxBaseUnits: BigInt.from(100000000),
                  onChanged: (value) => setState(() => picked = value),
                ),
          ),
        ),
      );
      for (final label in ['Free', r'$5', r'$10', r'$25']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(chip('money-amount-custom'), findsOneWidget);

      await tester.tap(chip('money-amount-10000000'));
      await tester.pump();
      expect(picked, MoneyAmount(BigInt.from(10000000)));

      await tester.tap(chip('money-amount-free'));
      await tester.pump();
      expect(picked, const MoneyAmount.free());

      await tester.tap(chip('money-amount-custom'));
      await tester.pumpAndSettle();
      await tester.enterText(chip('money-amount-custom-field'), '7.5');
      await tester.pump();
      expect(picked, MoneyAmount(BigInt.from(7500000)));
      expect(find.text(r'$7.50'), findsOneWidget);

      // Above the limit: said once, and nothing is picked.
      await tester.enterText(chip('money-amount-custom-field'), '500');
      await tester.pump();
      expect(picked, MoneyAmount(BigInt.from(7500000)));
      expect(find.text(r'$1–$100'), findsOneWidget);
    });

    testWidgets('the CTA: ink with Free, pink with an amount', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(
        harness(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MoneyCallButton(label: 'Call YES', amount: MoneyAmount.free()),
              MoneyCallButton(
                label: 'Call YES',
                amount: MoneyAmount(BigInt.from(5000000)),
              ),
            ],
          ),
        ),
      );
      final free = tester.widget<ChumbucketPrimaryButton>(
        find.widgetWithText(ChumbucketPrimaryButton, 'Call YES'),
      );
      expect(free.neutral, isTrue);
      expect(find.byKey(const ValueKey('free-marker')), findsOneWidget);
      final paid = tester.widget<ChumbucketPrimaryButton>(
        find.widgetWithText(ChumbucketPrimaryButton, r'Call YES · $5'),
      );
      expect(paid.neutral, isFalse);
    });
  });

  group('composer', () {
    Future<void> openComposer(
      WidgetTester tester, {
      required VenueMarket market,
      MoneyController? money,
      MoneyDependencies? deps,
      bool compact = false,
      bool allowMoney = true,
    }) async {
      await tester.pumpWidget(
        harness(
          money: money,
          deps: deps,
          child: Opener(
            open:
                (context) => showCallComposer(
                  context: context,
                  market: market,
                  initialSide: Side.yes,
                  compact: compact,
                  allowMoney: allowMoney,
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('money off: no amount row, the free ink call', (tester) async {
      usePhone(tester);
      await openComposer(tester, market: tradable);
      expect(chip('money-amount-free'), findsNothing);
      expect(
        tester
            .widget<ChumbucketPrimaryButton>(
              find.widgetWithText(ChumbucketPrimaryButton, 'Call YES'),
            )
            .neutral,
        isTrue,
      );
    });

    testWidgets('money on: \$5 by default, pink; Free turns it ink', (
      tester,
    ) async {
      usePhone(tester);
      final money = await boundMoney(moneyServer());
      addTearDown(money.dispose);
      await openComposer(tester, market: tradable, money: money);
      expect(chip('money-amount-free'), findsOneWidget);
      expect(find.text(r'Call YES · $5'), findsOneWidget);
      await tester.tap(chip('money-amount-free'));
      await tester.pumpAndSettle();
      expect(find.text(r'Call YES · $5'), findsNothing);
      expect(
        tester
            .widget<ChumbucketPrimaryButton>(
              find.widgetWithText(ChumbucketPrimaryButton, 'Call YES'),
            )
            .neutral,
        isTrue,
      );
    });

    testWidgets('hidden on a market that can\'t be traded', (tester) async {
      usePhone(tester);
      final money = await boundMoney(moneyServer());
      addTearDown(money.dispose);
      await openComposer(tester, market: demo, money: money);
      expect(chip('money-amount-free'), findsNothing);
    });

    testWidgets('onboarding\'s first call stays free', (tester) async {
      usePhone(tester);
      final money = await boundMoney(moneyServer());
      addTearDown(money.dispose);
      await openComposer(
        tester,
        market: tradable,
        money: money,
        compact: true,
        allowMoney: false,
      );
      expect(chip('money-amount-free'), findsNothing);
    });

    testWidgets(
      'short of funds: the same tap opens the deposit sheet, then carries on',
      (tester) async {
        usePhone(tester);
        final server = moneyServer(usdc: '1000000');
        final money = await boundMoney(server);
        addTearDown(money.dispose);
        final port = FakeBuyPort();
        server
          ..on('money.prepareCall', [needsFundsJson(), readyJson()])
          ..on('money.depositOptions', [depositOptionsJson()])
          ..on('money.wallet', [
            moneyWalletJson(usdc: '1000000'),
            moneyWalletJson(usdc: '6000000'),
          ])
          ..on('pantaTrading.submit', [venueOrderJson()])
          ..on('money.callStatus', [
            callStatusJson(state: 'FUNDED', trade: 'FILLED'),
          ]);
        await openComposer(
          tester,
          market: tradable,
          money: money,
          deps: fakeMoneyDeps(server, port: port),
        );

        await tester.tap(find.text(r'Call YES · $5'));
        await tester.pumpAndSettle();
        // Not enough balance: the deposit sheet, icon-led.
        expect(find.text('Add funds'), findsOneWidget);
        expect(chip('deposit-send-usdc'), findsOneWidget);
        expect(chip('deposit-from-wallet'), findsOneWidget);
        expect(chip('deposit-card'), findsNothing);
        expect(server.count('money.prepareCall'), 1);

        // The funds land: the sheet closes itself and the call continues.
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.text('Add funds'), findsNothing);
        final prepares = server.inputs('money.prepareCall');
        expect(prepares, hasLength(2));
        expect(prepares[1]['idempotencyKey'], prepares[0]['idempotencyKey']);

        // The compact review: pay, about what it pays if right, the fee.
        expect(find.byKey(const ValueKey('money-review')), findsOneWidget);
        expect(find.text(r'$5'), findsWidgets);
        expect(find.text(r'~$8.06'), findsOneWidget);
        expect(find.text(r'$0.05'), findsOneWidget);
        expect(find.textContaining('¢'), findsNothing);
        expect(find.textContaining('/share'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('money-sign')));
        await tester.pumpAndSettle();
        expect(port.signed, hasLength(1));
        // Signed is not funded: pending until the server says so.
        expect(find.byKey(const ValueKey('money-pending')), findsOneWidget);
        expect(find.byKey(const ValueKey('money-funded')), findsNothing);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('money-funded')), findsOneWidget);
        expect(find.text(r'$5 on YES'), findsOneWidget);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(Opener.last, isA<CallFeedEntry>());
        expect((Opener.last! as CallFeedEntry).call.id, moneyCallId);
        expect(money.defaultAmount, MoneyAmount(BigInt.from(5000000)));
      },
    );

    testWidgets('closing the review lets the call go; the composer stays', (
      tester,
    ) async {
      usePhone(tester);
      final server = moneyServer();
      final money = await boundMoney(server);
      addTearDown(money.dispose);
      server
        ..on('money.prepareCall', [readyJson()])
        ..on('money.discard', [
          {'moneyCall': moneyCallJson(state: 'EXPIRED', canDiscard: false)},
        ]);
      await openComposer(
        tester,
        market: tradable,
        money: money,
        deps: fakeMoneyDeps(server),
      );
      await tester.tap(find.text(r'Call YES · $5'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('money-review')), findsOneWidget);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(server.inputs('money.discard').single, {'callId': moneyCallId});
      expect(find.byKey(const ValueKey('money-review')), findsNothing);
      expect(find.text(r'Call YES · $5'), findsOneWidget);
      expect(Opener.last, isNull);
    });
  });

  group('Tail / Fade', () {
    Future<void> openResponse(
      WidgetTester tester, {
      MoneyController? money,
      bool allowMoney = true,
    }) async {
      final entry = callFeedEntryFromJson(
        pantaEntryJson(id: targetCallId, userId: 'user_ada'),
      );
      await tester.pumpWidget(
        harness(
          money: money,
          child: Opener(
            open:
                (context) => showCallResponseSheet(
                  context: context,
                  entry: entry,
                  initialKind: CallResponseKind.fade,
                  allowMoney: allowMoney,
                ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('Fade carries the row; the CTA trades the other side', (
      tester,
    ) async {
      usePhone(tester);
      final money = await boundMoney(moneyServer());
      addTearDown(money.dispose);
      await openResponse(tester, money: money);
      expect(chip('money-amount-free'), findsOneWidget);
      await tester.tap(chip('money-amount-10000000'));
      await tester.pumpAndSettle();
      expect(find.text(r'Call NO · $10'), findsOneWidget);

      // A dare is always free.
      await tester.tap(find.byKey(const ValueKey('response-challenge')));
      await tester.pumpAndSettle();
      expect(chip('money-amount-free'), findsNothing);
      expect(find.text('Send the dare'), findsOneWidget);
    });

    testWidgets('onboarding\'s answer stays free', (tester) async {
      usePhone(tester);
      final money = await boundMoney(moneyServer());
      addTearDown(money.dispose);
      await openResponse(tester, money: money, allowMoney: false);
      expect(chip('money-amount-free'), findsNothing);
    });
  });

  group('stamps', () {
    final fundedEntry = callFeedEntryFromJson(
      pantaEntryJson(
        funding: {
          'state': 'FILLED',
          'venue': 'panta',
          'fundedAt': moneyNow,
          'amountBaseUnits': '5000000',
          'side': 'YES',
        },
      ),
    );

    testWidgets('a filled call\'s card reads "\$5 on YES"', (tester) async {
      usePhone(tester);
      await tester.pumpWidget(harness(child: CallCard(entry: fundedEntry)));
      expect(find.text(r'$5 on YES'), findsOneWidget);
      expect(find.byKey(const ValueKey('funded-marker')), findsOneWidget);
    });

    testWidgets('the receipt is stamped "\$5 on YES"; its caption has no money', (
      tester,
    ) async {
      usePhone(tester);
      final receipt = CallReceipt.fromEntry(
        fundedEntry,
        shareUrl: 'https://chumbucket.test/c/1',
      );
      expect(receipt.fundedAmount, r'$5 on YES');
      // The question itself mentions $150,000; the stamp never travels.
      expect(receipt.shareCaption.contains(r'$5'), isFalse);
      expect(receipt.shareCaption.contains('on YES'), isFalse);
      await tester.pumpWidget(
        harness(child: SingleChildScrollView(child: CallReceiptCard(receipt: receipt))),
      );
      expect(find.text(r'$5 on YES'), findsOneWidget);
    });

    testWidgets('a pending money call reads pending, never funded', (
      tester,
    ) async {
      usePhone(tester);
      final pending = callFeedEntryFromJson(
        pantaEntryJson(
          money: {
            'state': 'PENDING',
            'amountBaseUnits': '5000000',
            'side': 'YES',
            'expiresAt': moneyNow,
          },
        ),
      );
      await tester.pumpWidget(harness(child: CallFundingMark(entry: pending)));
      expect(find.byKey(const ValueKey('money-pending-mark')), findsOneWidget);
      expect(find.text(r'$5 · Pending'), findsOneWidget);
      expect(find.byKey(const ValueKey('funded-marker')), findsNothing);
    });
  });
}
