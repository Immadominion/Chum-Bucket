/// The money.* wire: strict shapes, the server's own copy for refusals, the
/// session only in a header, and the app-wide money state (off is hidden,
/// the last amount used is remembered).
library;

import 'package:chumbucket/features/calls/data/call_models.dart' show Side;
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/money/data/money_client.dart';
import 'package:chumbucket/features/money/data/money_models.dart';
import 'package:chumbucket/features/money/money_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'money_fakes.dart';

void main() {
  group('models', () {
    test('a dollar amount is whole cents, never a float', () {
      expect(parseDollarAmount('5'), BigInt.from(5000000));
      expect(parseDollarAmount('7.5'), BigInt.from(7500000));
      expect(parseDollarAmount(r'$12.19'), BigInt.from(12190000));
      expect(parseDollarAmount('0'), isNull);
      expect(parseDollarAmount('1.005'), isNull);
      expect(parseDollarAmount('1e3'), isNull);
      expect(moneyDollars(BigInt.from(12190000)), r'$12.19');
      expect(moneyOnSide(BigInt.from(5000000), Side.yes), r'$5 on YES');
    });

    test('a funded money call carries its fill; nothing else does', () {
      expect(
        MoneyCallView.fromJson(moneyCallJson(state: 'FUNDED')).filledBaseUnits,
        BigInt.from(5000000),
      );
      expect(
        () => MoneyCallView.fromJson({
          ...moneyCallJson(),
          'filledBaseUnits': '5000000',
        }),
        throwsA(isA<MoneyException>()),
      );
      expect(
        () => MoneyCallView.fromJson({...moneyCallJson(), 'state': 'DONE'}),
        throwsA(isA<MoneyException>()),
      );
    });

    test('money.wallet with no wallet yet, and with gas unknown', () {
      final none = MoneyWalletInfo.fromJson({
        'wallet': null,
        'balance': null,
        'gas': null,
      });
      expect(none.wallet, isNull);
      expect(none.usdcBaseUnits, isNull);
      final info = MoneyWalletInfo.fromJson({...moneyWalletJson(), 'gas': null});
      expect(info.usdcBaseUnits, BigInt.from(12190000));
      expect(info.needsTopUp, isFalse);
    });

    test('the Send USDC QR must pay exactly the address shown, in USDC', () {
      Map<String, dynamic> options(String uri, {String? address}) => {
        'tradingWallet': {'address': signerWallet, 'walletType': 'chumbucket'},
        'sendUsdc': {
          'address': address ?? signerWallet,
          'mint': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
          'network': 'solana-mainnet',
          'uri': uri,
        },
        'card': {
          'available': false,
          'testMode': false,
          'reason': 'Not live',
          'presetsUsd': <String>[],
          'limits': null,
        },
        'fromWallet': {'wallets': <Object>[]},
      };
      const mint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
      final ok = DepositOptions.fromJson(
        options('solana:$signerWallet?amount=4&spl-token=$mint'),
      );
      expect(ok.sendUsdc!.address, signerWallet);
      for (final bad in [
        'solana:$otherWallet?spl-token=$mint',
        'solana:$signerWallet?spl-token=$otherWallet',
        'solana:$signerWallet?spl-token=$mint&memo=x',
      ]) {
        expect(
          () => DepositOptions.fromJson(options(bad)),
          throwsA(isA<MoneyException>()),
          reason: bad,
        );
      }
    });

    test('feed entries: "\$5 on YES" from the fill; pending stays pending', () {
      final funded = callFeedEntryFromJson(
        pantaEntryJson(
          funding: {
            'state': 'FILLED',
            'venue': 'panta',
            'fundedAt': kNow,
            'amountBaseUnits': '5000000',
            'side': 'YES',
          },
        ),
      );
      expect(funded.funding!.amountLabel, r'$5 on YES');
      // Below $1 a fill earns no amount stamp (as on the web and the BFF).
      final dust = callFeedEntryFromJson(
        pantaEntryJson(
          funding: {
            'state': 'FILLED',
            'venue': 'panta',
            'fundedAt': kNow,
            'amountBaseUnits': '990000',
            'side': 'YES',
          },
        ),
      );
      expect(dust.funding!.amountLabel, isNull);
      final legacy = callFeedEntryFromJson(
        pantaEntryJson(
          funding: {'state': 'FILLED', 'venue': 'panta', 'fundedAt': kNow},
        ),
      );
      expect(legacy.isFunded, isTrue);
      expect(legacy.funding!.amountLabel, isNull);
      final pending = callFeedEntryFromJson(
        pantaEntryJson(
          money: {
            'state': 'PENDING',
            'amountBaseUnits': '5000000',
            'side': 'YES',
            'expiresAt': kNow,
          },
        ),
      );
      expect(pending.isFunded, isFalse);
      expect(pending.money!.pending, isTrue);
    });
  });

  group('client', () {
    test('every procedure is a POST with the session in a header only', () async {
      final server = FakeMoneyServer()..on('money.wallet', [moneyWalletJson()]);
      final info = await server.moneyClient().wallet();
      expect(info.wallet!.address, signerWallet);
      final request = server.requests.single;
      expect(request.procedure, 'money.wallet');
      expect(request.auth, 'Bearer test-token');
      expect(request.input, isEmpty);
    });

    test('refusals carry the server\'s own short copy', () async {
      final server = FakeMoneyServer()
        ..on('money.retry', [
          moneyError('CONFLICT', r'Your $5 is still going through.'),
        ]);
      await expectLater(
        server.moneyClient().retry(moneyCallId),
        throwsA(
          isA<MoneyException>()
              .having((e) => e.kind, 'kind', MoneyErrorKind.conflict)
              .having((e) => e.message, 'message', r'Your $5 is still going through.'),
        ),
      );
    });

    test('a validator dump is never shown', () async {
      final server = FakeMoneyServer()
        ..on('money.prepareCall', [
          moneyError('BAD_REQUEST', '[{"code":"invalid_type"}]'),
        ]);
      await expectLater(
        server.moneyClient().prepareCall(
          kind: MoneyCallKind.own,
          marketId: pantaMarketId,
          side: 'YES',
          amountBaseUnits: BigInt.from(5000000),
          idempotencyKey: 'tap-key-000000000001',
        ),
        throwsA(
          isA<MoneyException>().having(
            (e) => e.serverMessage,
            'serverMessage',
            isNull,
          ),
        ),
      );
    });

    test('a non-HTTPS base is refused', () {
      expect(
        () => MoneyClient(baseUri: Uri.parse('http://bff.test'), token: () => 't'),
        throwsArgumentError,
      );
    });
  });

  group('money state', () {
    test('off on the server means hidden', () async {
      final server = FakeMoneyServer()
        ..on('money.status', [moneyStatusJson(enabled: false)]);
      final money = await boundMoney(server);
      addTearDown(money.dispose);
      expect(money.enabled, isFalse);
      expect(server.count('money.wallet'), 0);
    });

    test('on: balance and winnings are read; \$5 is the default', () async {
      final server = FakeMoneyServer()
        ..on('money.status', [moneyStatusJson(defaultAmount: null)])
        ..on('money.wallet', [moneyWalletJson()])
        ..on('money.winnings', [winningsJson()]);
      final money = await boundMoney(server);
      addTearDown(money.dispose);
      expect(money.enabled, isTrue);
      expect(money.balance, BigInt.from(12190000));
      expect(money.winnings.items.single.amountBaseUnits, BigInt.from(9200000));
      expect(money.defaultAmount, MoneyAmount(BigInt.from(5000000)));
      expect(money.presets, [
        BigInt.from(5000000),
        BigInt.from(10000000),
        BigInt.from(25000000),
      ]);
    });

    test('the last amount used on this phone wins, Free included', () async {
      final memory = MemoryAmountMemory();
      final server = FakeMoneyServer()
        ..on('money.status', [moneyStatusJson(defaultAmount: '10000000')])
        ..on('money.wallet', [moneyWalletJson()])
        ..on('money.winnings', [winningsJson(items: [], total: '0')]);
      final money = await boundMoney(server, memory: memory);
      addTearDown(money.dispose);
      expect(money.defaultAmount, MoneyAmount(BigInt.from(10000000)));
      await money.remember(const MoneyAmount.free());
      expect(money.defaultAmount, const MoneyAmount.free());
      expect(memory.values[viewerId], 'free');

      final again = await boundMoney(server, memory: memory);
      addTearDown(again.dispose);
      expect(again.defaultAmount, const MoneyAmount.free());
    });

    test('signing out clears everything money-shaped', () async {
      final server = FakeMoneyServer()
        ..on('money.status', [moneyStatusJson()])
        ..on('money.wallet', [moneyWalletJson()])
        ..on('money.winnings', [winningsJson()]);
      final money = await boundMoney(server);
      addTearDown(money.dispose);
      await money.bind(null);
      expect(money.enabled, isFalse);
      expect(money.wallet, isNull);
      expect(money.winnings.items, isEmpty);
    });
  });
}

const kNow = moneyNow;
