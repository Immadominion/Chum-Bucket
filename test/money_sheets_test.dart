/// The balance pill, the wallet sheet (activity, cash out through the
/// transfer check), the deposit sheet (Send USDC, a wallet app top-up, the
/// card only when offered and labelled test on staging) and Collect.
library;

import 'dart:convert';

import 'package:chumbucket/features/money/domain/usdc_transfer_check.dart';
import 'package:chumbucket/features/money/presentation/money_balance_pill.dart';
import 'package:chumbucket/features/money/presentation/money_deposit_sheet.dart';
import 'package:chumbucket/features/money/presentation/money_winnings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'money_fakes.dart';
import 'money_widgets_test.dart' show Opener, harness, moneyServer, usePhone;

Map<String, dynamic> transferViewJson({
  required String from,
  required String to,
  String state = 'BUILT',
  String kind = 'cash_out',
  String amount = '5000000',
}) => {
  'transferId': transferId,
  'kind': kind,
  'from': from,
  'to': to,
  'amountBaseUnits': amount,
  'state': state,
  'signature':
      state == 'SUBMITTED' || state == 'CONFIRMED' ? fillSignature : null,
  'createdAt': moneyNow,
  'updatedAt': moneyNow,
  'expiresAt': farFuture,
};

Map<String, dynamic> transferReadyJson({
  required String from,
  required String to,
  required String payload,
  String kind = 'cash_out',
  String amount = '5000000',
}) => {
  'status': 'READY',
  'transfer': transferViewJson(from: from, to: to, kind: kind, amount: amount),
  'transaction': {
    'encoding': 'solana-tx-base64',
    'payload': payload,
    'expiresAt': farFuture,
  },
  'review': {
    'from': from,
    'to': to,
    'amountBaseUnits': amount,
    'createsAccount': false,
    'networkFeeLamports': '5000',
    'rentLamports': '0',
  },
};

Map<String, dynamic> activityJson() => {
  'items': [
    {
      'id': 'trade:1',
      'kind': 'trade',
      'direction': 'out',
      'amountBaseUnits': '5000000',
      'state': 'done',
      'at': moneyNow,
      'signature': null,
      'callId': moneyCallId,
      'marketId': pantaMarketId,
      'side': 'YES',
      'question': 'Will BTC trade above 150k?',
      'counterparty': null,
    },
    {
      'id': 'deposit:abc',
      'kind': 'deposit',
      'direction': 'in',
      'amountBaseUnits': '20000000',
      'state': 'pending',
      'at': moneyNow - 1000,
      'signature': null,
      'callId': null,
      'marketId': null,
      'side': null,
      'question': null,
      'counterparty': null,
    },
  ],
};

/// A few frames, for a screen with a spinner that never settles.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => Opener.last = null);

  testWidgets('the pill: nothing while money is off, the balance when on', (
    tester,
  ) async {
    usePhone(tester);
    await tester.pumpWidget(harness(child: const MoneyBalancePill()));
    expect(find.byKey(const ValueKey('money-balance-pill')), findsNothing);

    final off = await boundMoney(
      FakeMoneyServer()..on('money.status', [moneyStatusJson(enabled: false)]),
    );
    addTearDown(off.dispose);
    await tester.pumpWidget(harness(money: off, child: const MoneyBalancePill()));
    expect(find.byKey(const ValueKey('money-balance-pill')), findsNothing);

    final on = await boundMoney(moneyServer());
    addTearDown(on.dispose);
    await tester.pumpWidget(harness(money: on, child: const MoneyBalancePill()));
    expect(find.text(r'$12.19'), findsOneWidget);
    expect(find.textContaining('updated'), findsNothing);

    // A real balance carries six places; the pill shows cents, rounded down.
    final exact = await boundMoney(moneyServer(usdc: '12188621'));
    addTearDown(exact.dispose);
    await tester.pumpWidget(
      harness(money: exact, child: const MoneyBalancePill()),
    );
    expect(find.text(r'$12.18'), findsOneWidget);
  });

  testWidgets('the wallet sheet: balance, add, cash out, activity rows', (
    tester,
  ) async {
    usePhone(tester);
    final server = moneyServer()..on('money.activity', [activityJson()]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    await tester.pumpWidget(
      harness(
        money: money,
        deps: fakeMoneyDeps(server),
        child: const MoneyBalancePill(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('money-balance-pill')));
    await tester.pumpAndSettle();
    expect(find.text('Balance'), findsOneWidget);
    expect(find.text(r'$12.19'), findsWidgets);
    expect(find.byKey(const ValueKey('wallet-add-funds')), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-cash-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-trade:1')), findsOneWidget);
    expect(find.text('Will BTC trade above 150k?'), findsOneWidget);
    expect(find.text(r'-$5'), findsOneWidget);
    expect(find.text(r'+$20'), findsOneWidget);
    expect(find.text('Added'), findsOneWidget);
  });

  testWidgets('no activity yet: the brand art and a few words', (tester) async {
    usePhone(tester);
    final server = moneyServer()..on('money.activity', [{'items': <Object>[]}]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    await tester.pumpWidget(
      harness(money: money, deps: fakeMoneyDeps(server), child: const MoneyBalancePill()),
    );
    await tester.tap(find.byKey(const ValueKey('money-balance-pill')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wallet-activity-empty')), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('cash out: address, amount, review, the check, sign, sent', (
    tester,
  ) async {
    usePhone(tester);
    final payload = await tester.runAsync(
      () => transferPayload(from: signerWallet, to: otherWallet),
    );
    final server =
        moneyServer()
          ..on('money.activity', [{'items': <Object>[]}])
          ..on('money.cashOutPrepare', [
            transferReadyJson(from: signerWallet, to: otherWallet, payload: payload!),
          ])
          ..on('money.transferSubmit', [
            transferViewJson(from: signerWallet, to: otherWallet, state: 'SUBMITTED'),
          ])
          ..on('money.transferStatus', [
            transferViewJson(from: signerWallet, to: otherWallet, state: 'CONFIRMED'),
          ]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    var signed = 0;
    await tester.pumpWidget(
      harness(
        money: money,
        deps: fakeMoneyDeps(
          server,
          transferSign: (unsigned, message) async {
            signed++;
            return Uint8List.fromList(List.filled(64, 4));
          },
        ),
        child: const MoneyBalancePill(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('money-balance-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wallet-cash-out')));
    await tester.pumpAndSettle();
    expect(find.text('Cash out'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('cash-out-address')), 'nope');
    await tester.enterText(find.byKey(const ValueKey('cash-out-amount')), '5');
    await tester.tap(find.byKey(const ValueKey('cash-out-review-go')));
    await tester.pumpAndSettle();
    expect(find.text('Check the address.'), findsOneWidget);
    expect(server.count('money.cashOutPrepare'), 0);

    await tester.enterText(
      find.byKey(const ValueKey('cash-out-address')),
      otherWallet,
    );
    await tester.tap(find.byKey(const ValueKey('cash-out-review-go')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cash-out-review')), findsOneWidget);
    final prepare = server.inputs('money.cashOutPrepare').single;
    expect(prepare['destination'], otherWallet);
    expect(prepare['amountBaseUnits'], '5000000');

    await tester.tap(find.byKey(const ValueKey('cash-out-sign')));
    await settle(tester);
    expect(signed, 1);
    final submit = server.inputs('money.transferSubmit').single;
    final bytes = base64Decode(submit['signedTransaction'] as String);
    expect(bytes.sublist(1, 65), List.filled(64, 4));
    expect(bytes.sublist(65), base64Decode(payload).sublist(65));

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cash-out-sent')), findsOneWidget);
  });

  testWidgets('cash out refuses a transfer that does not match, unsigned', (
    tester,
  ) async {
    usePhone(tester);
    // The server's bytes pay someone else's account.
    final payload = await tester.runAsync(
      () => transferPayload(
        from: signerWallet,
        to: otherWallet,
        destinationOverride: venueMarket,
      ),
    );
    final server =
        moneyServer()
          ..on('money.activity', [{'items': <Object>[]}])
          ..on('money.cashOutPrepare', [
            transferReadyJson(from: signerWallet, to: otherWallet, payload: payload!),
          ]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    var signed = 0;
    await tester.pumpWidget(
      harness(
        money: money,
        deps: fakeMoneyDeps(
          server,
          checkTransfer:
              (_, _) async => throw const TransferCheckException('transfer'),
          transferSign: (_, _) async {
            signed++;
            return Uint8List(64);
          },
        ),
        child: const MoneyBalancePill(),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('money-balance-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wallet-cash-out')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('cash-out-address')), otherWallet);
    await tester.enterText(find.byKey(const ValueKey('cash-out-amount')), '5');
    await tester.tap(find.byKey(const ValueKey('cash-out-review-go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cash-out-sign')));
    await tester.pumpAndSettle();
    expect(signed, 0);
    expect(server.count('money.transferSubmit'), 0);
    expect(find.textContaining('didn’t match'), findsOneWidget);
  });

  group('deposit sheet', () {
    Future<FakeMoneyServer> open(
      WidgetTester tester, {
      required Map<String, dynamic> options,
      String? walletApp,
      Future<bool> Function()? openCard,
    }) async {
      final server =
          moneyServer()..on('money.depositOptions', [options]);
      final money = await boundMoney(server);
      addTearDown(money.dispose);
      await tester.pumpWidget(
        harness(
          money: money,
          deps: fakeMoneyDeps(server, walletApp: walletApp, openCard: openCard),
          child: Opener(open: (context) => showMoneyDepositSheet(context)),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return server;
    }

    testWidgets('Send USDC: the address, its QR, copy; then it watches', (
      tester,
    ) async {
      usePhone(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      final server = await open(tester, options: depositOptionsJson());
      await tester.tap(find.byKey(const ValueKey('deposit-send-usdc')));
      // The address stage watches with a small spinner: pump, never settle.
      await settle(tester);
      final qr = tester.widget<QrImageView>(find.byKey(const ValueKey('deposit-qr')));
      expect(qr, isNotNull);
      expect(find.text(signerWallet), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('deposit-copy')));
      await tester.pump();
      expect(copied, signerWallet);

      // USDC arrives: the sheet sees the balance rise and closes itself.
      server.on('money.wallet', [moneyWalletJson(usdc: '32190000')]);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(Opener.last, isTrue);
    });

    testWidgets('the card shows only when offered, and says Test on staging', (
      tester,
    ) async {
      usePhone(tester);
      await open(tester, options: depositOptionsJson());
      expect(find.byKey(const ValueKey('deposit-card')), findsNothing);
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      await open(tester, options: depositOptionsJson(card: true, testMode: true));
      expect(find.byKey(const ValueKey('deposit-card')), findsOneWidget);
      expect(find.textContaining('Test'), findsOneWidget);
    });

    testWidgets('from your wallet app: one approval, checked first', (
      tester,
    ) async {
      usePhone(tester);
      final payload = await tester.runAsync(
        () => transferPayload(
          from: otherWallet,
          to: signerWallet,
          amount: 10000000,
        ),
      );
      final server = await open(
        tester,
        options: depositOptionsJson(),
        walletApp: otherWallet,
      );
      server
        ..on('money.depositFromWalletPrepare', [
          transferReadyJson(
            from: otherWallet,
            to: signerWallet,
            payload: payload!,
            kind: 'deposit',
            amount: '10000000',
          ),
        ])
        ..on('money.transferSubmit', [
          transferViewJson(
            from: otherWallet,
            to: signerWallet,
            state: 'SUBMITTED',
            kind: 'deposit',
            amount: '10000000',
          ),
        ]);
      await tester.tap(find.byKey(const ValueKey('deposit-from-wallet')));
      await tester.pumpAndSettle();
      // $10 by default with no call waiting.
      expect(find.text(r'Add $10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('deposit-from-wallet-go')));
      await tester.pumpAndSettle();
      final prepare = server.inputs('money.depositFromWalletPrepare').single;
      expect(prepare['fromWallet'], otherWallet);
      expect(prepare['amountBaseUnits'], '10000000');
      expect(find.text(r'Approve in wallet · $10'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('deposit-from-wallet-go')));
      await settle(tester);
      expect(server.count('money.transferSubmit'), 1);
      // Arrived: the sheet closes on the balance it watches.
      server.on('money.wallet', [moneyWalletJson(usdc: '22190000')]);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(Opener.last, isTrue);
    });
  });

  testWidgets('no wallet yet: set one up, then the options', (tester) async {
    usePhone(tester);
    final server =
        moneyServer()
          ..on('money.depositOptions', [depositOptionsJson()])
          ..on('money.wallet', [
            moneyWalletJson(noWallet: true),
            moneyWalletJson(noWallet: true),
            moneyWalletJson(),
          ]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    var setUps = 0;
    await tester.pumpWidget(
      harness(
        money: money,
        deps: fakeMoneyDeps(
          server,
          setUpWallet: () async {
            setUps++;
            return true;
          },
        ),
        child: Opener(open: (context) => showMoneyDepositSheet(context)),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Set up your wallet first.'), findsOneWidget);
    expect(find.byKey(const ValueKey('deposit-send-usdc')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('deposit-set-up-wallet')));
    await tester.pumpAndSettle();
    expect(setUps, 1);
    expect(find.byKey(const ValueKey('deposit-send-usdc')), findsOneWidget);
  });

  testWidgets('an answer naming another wallet is refused, nothing shown', (
    tester,
  ) async {
    usePhone(tester);
    final server =
        moneyServer()
          ..on('money.depositOptions', [
            {
              ...depositOptionsJson(),
              'tradingWallet': {'address': otherWallet, 'walletType': 'mwa'},
            },
          ]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    await tester.pumpWidget(
      harness(
        money: money,
        deps: fakeMoneyDeps(server),
        child: Opener(open: (context) => showMoneyDepositSheet(context)),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deposit-send-usdc')), findsNothing);
    expect(find.textContaining('couldn’t confirm your wallet'), findsOneWidget);
  });

  testWidgets('a trading wallet this phone doesn\'t know: nothing payable', (
    tester,
  ) async {
    usePhone(tester);
    final server = moneyServer()..on('money.depositOptions', [depositOptionsJson()]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    var cards = 0;
    await tester.pumpWidget(
      harness(
        money: money,
        // The phone only knows another wallet: the server's answer, however
        // consistent, is not enough.
        deps: fakeMoneyDeps(
          server,
          phoneWallets: {otherWallet},
          openCard: () async {
            cards++;
            return false;
          },
        ),
        child: Opener(open: (context) => showMoneyDepositSheet(context)),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deposit-send-usdc')), findsNothing);
    expect(find.byKey(const ValueKey('deposit-card')), findsNothing);
    expect(find.byKey(const ValueKey('deposit-from-wallet')), findsNothing);
    expect(find.byKey(const ValueKey('deposit-qr')), findsNothing);
    expect(find.textContaining('couldn’t confirm your wallet'), findsOneWidget);
    expect(cards, 0);
  });

  testWidgets('Collect \$9.20: the claim path, then the balance again', (
    tester,
  ) async {
    usePhone(tester);
    final server =
        FakeMoneyServer()
          ..on('money.status', [moneyStatusJson()])
          ..on('money.wallet', [moneyWalletJson()])
          ..on('money.winnings', [winningsJson(), winningsJson(items: [], total: '0')])
          ..on('pantaTrading.claimPrepare', [claimPreparedJson()])
          ..on('pantaTrading.claimSubmit', [claimViewJson(state: 'CONFIRMED')]);
    final money = await boundMoney(server);
    addTearDown(money.dispose);
    final port = FakeBuyPort();
    await tester.pumpWidget(
      harness(
        money: money,
        deps: fakeMoneyDeps(server, claimPort: port),
        child: const MoneyWinningsCard(),
      ),
    );
    expect(find.text(r'Collect $9.20'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('money-collect')));
    await tester.pumpAndSettle();
    expect(port.signed, hasLength(1));
    expect(server.inputs('pantaTrading.claimPrepare').single['orderId'], orderId);
    expect(server.count('pantaTrading.claimSubmit'), 1);
    // Collected: winnings read again, and nothing left to collect.
    expect(find.byKey(const ValueKey('money-winnings-card')), findsNothing);
  });

  testWidgets('a call\'s own Collect shows only its own winnings', (tester) async {
    usePhone(tester);
    final money = await boundMoney(
      FakeMoneyServer()
        ..on('money.status', [moneyStatusJson()])
        ..on('money.wallet', [moneyWalletJson()])
        ..on('money.winnings', [winningsJson()]),
    );
    addTearDown(money.dispose);
    await tester.pumpWidget(
      harness(money: money, child: const MoneyWinningsCard(callId: 'other')),
    );
    expect(find.byKey(const ValueKey('money-winnings-card')), findsNothing);
    await tester.pumpWidget(
      harness(money: money, child: const MoneyWinningsCard(callId: moneyCallId)),
    );
    expect(find.text(r'Collect $9.20'), findsOneWidget);
  });
}
