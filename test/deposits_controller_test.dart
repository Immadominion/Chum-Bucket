import 'dart:convert';

import 'package:chumbucket/features/deposits/add_funds_controller.dart';
import 'package:chumbucket/features/deposits/data/deposit_order_memory.dart';
import 'package:chumbucket/features/deposits/data/deposits_models.dart';
import 'package:chumbucket/features/deposits/domain/deposit_wallet_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'deposits_fakes.dart';

void main() {
  late FakeDepositsBff bff;
  late InMemoryDepositOrderMemory memory;
  final controllers = <AddFundsController>[];
  var keys = 0;

  setUp(() {
    bff = FakeDepositsBff();
    memory = InMemoryDepositOrderMemory();
    keys = 0;
  });
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  AddFundsController make({
    BigInt? required,
    String? preferredWallet,
    DepositWalletSource? walletSource,
    String? accountId = 'user-1',
  }) {
    final c = AddFundsController(
      client: bff.newClient(),
      memory: memory,
      accountId: accountId,
      requiredUsdcBaseUnits: required,
      preferredWallet: preferredWallet,
      walletSource: walletSource,
      pollInterval: const Duration(milliseconds: 5),
      slowPollInterval: const Duration(milliseconds: 10),
      quoteDebounce: Duration.zero,
      newIdempotencyKey: () => 'synthetic-key-${++keys}-0000000000',
    );
    controllers.add(c);
    return c;
  }

  test(
    'loads the account, its real balance, and a quote for the default',
    () async {
      final c = make();
      await c.load();
      await until(() => c.quote != null && c.balance != null);
      expect(c.stage, AddFundsStage.choose);
      expect(c.amount!.wire, '25');
      expect(c.destination, walletA);
      expect(c.balance!.usdcLabel, '12.50');
      expect(bff.inputs('quote').single['amountUsd'], '25');
      expect(c.canStart, isTrue);
    },
  );

  test('signed out stops before any account call', () async {
    bff.status = statusJson(accountIssue: 'SIGNED_OUT');
    final c = make();
    await c.load();
    expect(c.stage, AddFundsStage.signedOut);
    expect(bff.inputs('balance'), isEmpty);
  });

  test(
    'paused deposits still show the balance and say why, in words',
    () async {
      bff.status = statusJson(
        available: false,
        reason: {
          'code': 'PAUSED',
          'message': 'Adding funds is paused right now.',
        },
      );
      final c = make();
      await c.load();
      await until(() => c.balance != null);
      expect(c.stage, AddFundsStage.unavailable);
      expect(c.unavailableMessage, 'Adding funds is paused right now.');
      expect(bff.inputs('quote'), isEmpty);
    },
  );

  test('an account without a proven wallet is told to connect one', () async {
    bff.status = statusJson(wallets: []);
    final c = make();
    await c.load();
    expect(c.stage, AddFundsStage.unavailable);
    expect(c.unavailableMessage, startsWith('Connect a wallet'));
    expect(bff.inputs('balance'), isEmpty);
  });

  test(
    'a trade shortfall picks an amount that covers it, card fees included',
    () async {
      // Needs 30 USDC, holds 5: short 25 → $26.50 with headroom → $27 → $50 preset.
      bff.balance = balanceJson(usdc: '5000000');
      final c = make(required: BigInt.from(30000000));
      await c.load();
      await until(
        () => c.balance != null && !c.quoteLoading && c.quote != null,
      );
      expect(c.shortfallBaseUnits, BigInt.from(25000000));
      expect(c.amount!.wire, '50');
      expect(c.isCustomAmount, isFalse);
    },
  );

  test('a shortfall above every preset becomes a custom amount', () async {
    bff.balance = balanceJson(usdc: '0');
    final c = make(required: BigInt.from(150000000));
    await c.load();
    await until(() => c.balance != null && c.amount?.wire == '159');
    expect(c.isCustomAmount, isTrue);
    expect(c.customText, '159');
  });

  test('funds the trade wallet only when the account has proven it', () async {
    bff.status = statusJson(
      wallets: [
        walletJson(walletA),
        walletJson(walletB, type: 'embedded', primary: false, session: false),
      ],
    );
    final c = make(preferredWallet: walletB);
    await c.load();
    await until(() => c.quote != null);
    expect(c.destination, walletB);
    expect(bff.inputs('quote').last['wallet'], walletB);
    expect(c.localWalletNotLinked, isFalse);
  });

  test('an unproven trade wallet is never sent; the sheet is told', () async {
    final c = make(preferredWallet: walletB);
    await c.load();
    await until(() => c.quote != null);
    expect(bff.inputs('quote').last.containsKey('wallet'), isFalse);
    expect(c.destination, walletA);
    expect(c.localWalletNotLinked, isTrue);
  });

  test(
    'pays, tracks and lands: memory set, then cleared; balance re-read',
    () async {
      bff.orderStates = [
        orderJson(state: 'payment_processing'),
        orderJson(state: 'delivering'),
        orderJson(state: 'delivered', txId: syntheticTx),
      ];
      final c = make();
      await c.load();
      await until(() => c.quote != null);
      expect(await c.startCheckout(), isTrue);
      expect(c.stage, AddFundsStage.checkout);
      expect(c.checkoutUri!.host, 'www.crossmint.com');
      expect(await memory.pending('user-1'), orderOne);
      final created = bff.inputs('create').single;
      expect(created['idempotencyKey'], 'synthetic-key-1-0000000000');
      expect(created.containsKey('recipient'), isFalse);

      c.checkoutOpened();
      await until(() => c.stage == AddFundsStage.delivered);
      expect(c.order!.txId, syntheticTx);
      await until(() => bff.inputs('balance').length >= 2);
      expect(await memory.pending('user-1'), isNull);
    },
  );

  test('a retried tap after a dropped create reuses the same key', () async {
    var attempt = 0;
    bff.handlers['deposits.create'] = (input) {
      attempt++;
      if (attempt == 1) {
        return trpcError(
          'BAD_GATEWAY',
          'We couldn\'t reach our payment partner.',
          status: 502,
        );
      }
      return trpcOk({'order': orderJson(), 'checkoutUrl': checkoutUrl()});
    };
    final c = make();
    await c.load();
    await until(() => c.quote != null);
    expect(await c.startCheckout(), isFalse);
    expect(c.stage, AddFundsStage.choose);
    expect(c.error!.kind, DepositsErrorKind.provider);
    expect(await c.startCheckout(), isTrue);
    final keysSent =
        bff.inputs('create').map((i) => i['idempotencyKey']).toList();
    expect(keysSent, hasLength(2));
    expect(keysSent.toSet(), hasLength(1));
  });

  test('changing the amount after a failure starts a fresh key', () async {
    bff.handlers['deposits.create'] =
        (_) => trpcError('BAD_GATEWAY', 'Try again.', status: 502);
    final c = make();
    await c.load();
    await until(() => c.quote != null);
    await c.startCheckout();
    c.selectPreset(UsdAmount.tryParse('50')!);
    await c.startCheckout();
    final keysSent =
        bff.inputs('create').map((i) => i['idempotencyKey']).toSet();
    expect(keysSent, hasLength(2));
  });

  test('a payment in flight is picked up on the next visit', () async {
    await memory.remember('user-1', orderOne);
    bff.orderStates = [
      orderJson(state: 'delivering'),
      orderJson(state: 'delivered'),
    ];
    final c = make();
    await c.load();
    expect(c.stage, AddFundsStage.tracking);
    expect(bff.inputs('quote'), isEmpty);
    await until(() => c.stage == AddFundsStage.delivered);
  });

  test('an abandoned unpaid checkout is dropped, not a dead end', () async {
    await memory.remember('user-1', orderOne);
    bff.orderStates = [orderJson(state: 'awaiting_payment')];
    final c = make();
    await c.load();
    expect(c.stage, AddFundsStage.choose);
    expect(await memory.pending('user-1'), isNull);
  });

  test(
    'an old order waiting for a signature is dropped, not resumed',
    () async {
      await memory.remember('user-1', orderOne);
      bff.orderStates = [
        orderJson(state: 'awaiting_wallet_proof', proof: 'sign me'),
      ];
      final c = make(walletSource: FakeWalletSource(walletA));
      await c.load();
      expect(c.stage, AddFundsStage.choose);
      expect(c.order, isNull);
      expect(await memory.pending('user-1'), isNull);
    },
  );

  test('a wallet with no SOL is flagged; one with SOL is not', () async {
    bff.balance = balanceJson(lamports: '0');
    final c = make();
    await c.load();
    await until(() => c.balance != null);
    expect(c.needsSol, isTrue);
    bff.balance = balanceJson(lamports: '1');
    await c.refreshBalance();
    expect(c.needsSol, isFalse);
  });

  test('a delivery that finished while away is still news', () async {
    await memory.remember('user-1', orderOne);
    bff.orderStates = [orderJson(state: 'delivered', txId: syntheticTx)];
    final c = make();
    await c.load();
    expect(c.stage, AddFundsStage.delivered);
    expect(await memory.pending('user-1'), isNull);
  });

  test(
    'a failed delivery ends the payment and says refunds are automatic',
    () async {
      bff.orderStates = [
        orderJson(state: 'delivery_failed', refundedUsd: '25'),
      ];
      final c = make();
      await c.load();
      await until(() => c.quote != null);
      await c.startCheckout();
      await until(() => c.stage == AddFundsStage.failed);
      expect(c.order!.refundedUsd, '25');
      expect(await memory.pending('user-1'), isNull);
    },
  );

  test(
    'a declined card stays open for another try in the same order',
    () async {
      bff.orderStates = [
        orderJson(
          state: 'payment_failed',
          failure: {
            'code': 'card_declined',
            'message': 'Your card was declined.',
          },
        ),
      ];
      final c = make();
      await c.load();
      await until(() => c.quote != null);
      await c.startCheckout();
      await c.checkoutClosed();
      expect(c.stage, AddFundsStage.tracking);
      expect(c.order!.state, DepositOrderState.paymentFailed);
      expect(c.canReturnToCheckout, isTrue);
    },
  );

  test(
    'ownership proof: the receiving wallet signs the exact message',
    () async {
      const message =
          'chumbucket.app wants you to verify ownership of this wallet.';
      final source = FakeWalletSource(walletA);
      bff.orderStates = [
        orderJson(state: 'awaiting_wallet_proof', proof: message),
      ];
      final c = make(walletSource: source);
      await c.load();
      await until(() => c.quote != null);
      await c.startCheckout();
      await until(() => c.stage == AddFundsStage.walletProof);
      expect(c.canSignProof, isTrue);
      bff.orderStates = [orderJson()];
      await c.signOwnershipProof();
      expect(utf8.decode(source.signed.single), message);
      final sent = bff.inputs('verifyWallet').single;
      expect(sent['orderId'], orderOne);
      expect(base64Decode(sent['signature'] as String), hasLength(64));
    },
  );

  test('ownership proof: a declined signature sends nothing', () async {
    final source = FakeWalletSource(walletA)
      ..failWith = const DepositWalletDeclined();
    bff.orderStates = [
      orderJson(state: 'awaiting_wallet_proof', proof: 'sign me'),
    ];
    final c = make(walletSource: source);
    await c.load();
    await until(() => c.quote != null);
    await c.startCheckout();
    await until(() => c.stage == AddFundsStage.walletProof);
    await c.signOwnershipProof();
    expect(bff.inputs('verifyWallet'), isEmpty);
    expect(c.error!.message, contains('No signature was made'));
  });

  test(
    'ownership proof: a different wallet on this phone cannot sign',
    () async {
      final source = FakeWalletSource(walletB);
      bff.orderStates = [
        orderJson(state: 'awaiting_wallet_proof', proof: 'sign me'),
      ];
      final c = make(walletSource: source);
      await c.load();
      await until(() => c.quote != null);
      await c.startCheckout();
      await until(() => c.stage == AddFundsStage.walletProof);
      expect(c.canSignProof, isFalse);
      await c.signOwnershipProof();
      expect(source.signed, isEmpty);
      expect(bff.inputs('verifyWallet'), isEmpty);
    },
  );

  test('an email is asked for only when the account has none', () async {
    bff.status = statusJson(needsEmail: true);
    final c = make();
    await c.load();
    expect(c.needsEmail, isTrue);
    expect(c.canStart, isFalse);
    expect(bff.inputs('quote'), isEmpty);
    c.editEmail('person@example.com');
    await until(() => c.quote != null);
    expect(c.canStart, isTrue);
    await c.startCheckout();
    expect(bff.inputs('create').single['receiptEmail'], 'person@example.com');
  });

  test('an amount outside the limits never reaches the server', () async {
    final c = make();
    await c.load();
    await until(() => c.quote != null);
    final quotes = bff.inputs('quote').length;
    c.editCustomAmount('2');
    expect(c.amountInRange, isFalse);
    expect(c.canStart, isFalse);
    expect(await c.startCheckout(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bff.inputs('quote'), hasLength(quotes));
    expect(bff.inputs('create'), isEmpty);
  });
}
