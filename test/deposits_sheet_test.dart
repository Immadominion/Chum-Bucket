import 'dart:async';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/deposits/add_funds_controller.dart';
import 'package:chumbucket/features/deposits/data/deposit_order_memory.dart';
import 'package:chumbucket/features/deposits/domain/deposit_wallet_source.dart';
import 'package:chumbucket/features/deposits/presentation/add_funds_sheet.dart';
import 'package:chumbucket/features/deposits/presentation/deposits_dependencies.dart';
import 'package:chumbucket/features/deposits/presentation/trade_funds_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'deposits_fakes.dart';
import 'panta_trading_controller_test.dart'
    show SyntheticPantaRig, syntheticWalletAddress;

/// Opens Add funds from a button, the way Profile and the trade review do.
class SheetRig {
  SheetRig({DepositWalletSource? walletSource}) {
    deps = DepositsDependencies(
      createClient: bff.newClient,
      accountId: 'user-1',
      memory: memory,
      walletSource: walletSource,
      openCheckout: (context, controller) async {
        opened.add(controller);
        await (checkoutClosed = Completer<void>()).future;
      },
    );
  }

  final bff = FakeDepositsBff();
  final memory = InMemoryDepositOrderMemory();
  late final DepositsDependencies deps;
  final opened = <AddFundsController>[];
  Completer<void> checkoutClosed = Completer<void>();
  bool? result;

  Future<void> mount(
    WidgetTester tester, {
    double width = 390,
    double height = 844,
    double scale = 1,
    BigInt? required,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('deposits-capture'),
        child: Provider<DepositsDependencies?>.value(
          value: deps,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, _) => MaterialApp(
                  theme: AppTheme.lightTheme,
                  builder:
                      (context, child) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!,
                      ),
                  home: Scaffold(
                    body: Builder(
                      builder:
                          (context) => TextButton(
                            onPressed: () async {
                              result = await showAddFundsSheet(
                                context,
                                requiredUsdcBaseUnits: required,
                              );
                            },
                            child: const Text('open'),
                          ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // Status, balance and the first quote are each one round trip.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

String richText(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).textSpan!.toPlainText();

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable:
        find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
    maxScrolls: 60,
  );
  await tester.pump();
}

void main() {
  testWidgets('shows the real balance, presets and Crossmint\'s quote', (
    tester,
  ) async {
    final rig = SheetRig();
    await rig.mount(tester);
    expect(find.text('Add funds'), findsWidgets);
    expect(
      richText(tester, const ValueKey('deposit-balance-usdc')),
      '12.50 USDC',
    );
    expect(richText(tester, const ValueKey('deposit-balance-sol')), '0.25 SOL');
    for (final preset in ['10', '25', '50', '100', 'other']) {
      expect(find.byKey(ValueKey('deposit-preset-$preset')), findsOneWidget);
    }
    await reveal(tester, find.byKey(const ValueKey('deposit-quote')));
    expect(find.text(r'$25'), findsWidgets);
    expect(find.text('≈ 24.10–24.40 USDC'), findsOneWidget);
    expect(find.textContaining('Your wallet 9WzD…AWWM'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pays through the checkout and lands with a receipt', (
    tester,
  ) async {
    final rig = SheetRig();
    rig.bff.orderStates = [orderJson()];
    await rig.mount(tester);
    await reveal(tester, find.byKey(const ValueKey('deposit-continue')));
    await tester.tap(find.byKey(const ValueKey('deposit-continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(rig.opened, hasLength(1));
    expect(rig.bff.inputs('create').single['amountUsd'], '25');
    expect(await rig.memory.pending('user-1'), orderOne);

    // Crossmint delivers while the person is still in the checkout.
    rig.bff.orderStates = [
      orderJson(
        state: 'delivered',
        txId: syntheticTx,
        receive: const {'min': '24.21', 'max': '24.21'},
      ),
    ];
    rig.checkoutClosed.complete();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Funds added'), findsWidgets);
    expect(find.text('24.21 USDC landed in your wallet.'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('deposit-explorer')));
    expect(find.byKey(const ValueKey('deposit-explorer')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('deposit-done')));
    await tester.tap(find.byKey(const ValueKey('deposit-done')));
    // The post-delivery balance re-read waits 4s; let it finish.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(rig.result, isTrue);
    expect(await rig.memory.pending('user-1'), isNull);
  });

  testWidgets('paused deposits say so and still offer a crypto transfer', (
    tester,
  ) async {
    final rig = SheetRig();
    rig.bff.status = statusJson(
      available: false,
      reason: {
        'code': 'NOT_CONFIGURED',
        'message': 'Adding funds isn\'t set up yet.',
      },
    );
    await rig.mount(tester);
    expect(
      find.text('Card payments aren\'t available right now'),
      findsOneWidget,
    );
    expect(find.text('Adding funds isn\'t set up yet.'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('deposit-receive-address')));
    expect(find.text(walletA), findsOneWidget);
    expect(find.byKey(const ValueKey('deposit-continue')), findsNothing);
    expect(rig.bff.inputs('quote'), isEmpty);
  });

  testWidgets('signed out asks to sign in, nothing else', (tester) async {
    final rig = SheetRig();
    rig.bff.status = statusJson(accountIssue: 'SIGNED_OUT');
    await rig.mount(tester);
    expect(find.text('Sign in to add funds'), findsOneWidget);
    expect(find.byKey(const ValueKey('deposit-balance-card')), findsNothing);
    expect(rig.bff.inputs('balance'), isEmpty);
  });

  testWidgets('staging is labelled as test mode with test cards', (
    tester,
  ) async {
    final rig = SheetRig();
    rig.bff.status = statusJson(
      environment: 'staging',
      presets: ['1', '5', '10'],
    );
    await rig.mount(tester);
    await reveal(tester, find.textContaining('Test mode.'));
    expect(find.textContaining('4242 4242 4242 4242'), findsOneWidget);
    expect(
      find.textContaining('won\'t show up in your trading balance'),
      findsOneWidget,
    );
  });

  testWidgets('opened for a trade, it states the gap in real numbers', (
    tester,
  ) async {
    final rig = SheetRig();
    rig.bff.balance = balanceJson(usdc: '5000000');
    await rig.mount(tester, required: BigInt.from(30000000));
    expect(find.text('Top up for this trade'), findsOneWidget);
    expect(
      find.text(
        'This trade needs 30.00 USDC. You have 5.00, so add at least 25.00 USDC.',
      ),
      findsOneWidget,
    );
    expect(find.text(r'$50'), findsWidgets);
  });

  for (final (width, scale) in [(320.0, 2.0), (390.0, 1.3)]) {
    testWidgets('lays out at $width wide, ${scale}x text', (tester) async {
      final rig = SheetRig();
      rig.bff.status = statusJson(needsEmail: true);
      await rig.mount(tester, width: width, scale: scale);
      await reveal(tester, find.byKey(const ValueKey('deposit-email')));
      await reveal(tester, find.text('Already have crypto?'));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a wallet signature Crossmint asks for comes before the checkout',
    (tester) async {
      final source = FakeWalletSource(walletA);
      final rig = SheetRig(walletSource: source);
      final needsProof = orderJson(
        state: 'awaiting_wallet_proof',
        proof: 'Verify ownership',
      );
      rig.bff.handlers['deposits.create'] =
          (_) => trpcOk({'order': needsProof, 'checkoutUrl': checkoutUrl()});
      rig.bff.orderStates = [needsProof];
      await rig.mount(tester);
      await reveal(tester, find.byKey(const ValueKey('deposit-continue')));
      await tester.tap(find.byKey(const ValueKey('deposit-continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // No checkout yet: it can't take a payment until the wallet signs.
      expect(rig.opened, isEmpty);
      expect(find.text('Confirm this wallet is yours'), findsOneWidget);

      rig.bff.orderStates = [orderJson()];
      await reveal(tester, find.byKey(const ValueKey('deposit-sign-proof')));
      await tester.tap(find.byKey(const ValueKey('deposit-sign-proof')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(source.signed, hasLength(1));
      expect(rig.bff.inputs('verifyWallet'), hasLength(1));
      // Signed and accepted: straight on to paying, in the same order.
      expect(rig.opened, hasLength(1));
      expect(rig.bff.inputs('create'), hasLength(1));
    },
  );

  testWidgets(
    'a wallet with no SOL is told it can\'t trade yet, and how to fix it',
    (tester) async {
      final rig = SheetRig();
      rig.bff.balance = balanceJson(lamports: '0');
      await rig.mount(tester);
      expect(find.byKey(const ValueKey('deposit-needs-sol')), findsOneWidget);
      // The address to send SOL to is already open.
      await reveal(
        tester,
        find.byKey(const ValueKey('deposit-receive-address')),
      );
      expect(
        find.byKey(const ValueKey('deposit-receive-details')),
        findsOneWidget,
      );

      await reveal(tester, find.byKey(const ValueKey('deposit-continue')));
      await tester.tap(find.byKey(const ValueKey('deposit-continue')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      rig.bff.orderStates = [
        orderJson(
          state: 'delivered',
          txId: syntheticTx,
          receive: const {'min': '24.21', 'max': '24.21'},
        ),
      ];
      rig.checkoutClosed.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('24.21 USDC landed in your wallet.'), findsOneWidget);
      // Never "you're ready" while a trade couldn't pay its network fee.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('deposit-delivered-next')))
            .data,
        'One more step before you trade: add a little SOL for network fees.',
      );
      expect(find.text('Add SOL for network fees'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'a resumed payment that can no longer be paid offers a fresh one',
    (tester) async {
      final rig = SheetRig();
      await rig.memory.remember('user-1', orderOne);
      // Identity review finished while the sheet was closed.
      rig.bff.orderStates = [
        orderJson(state: 'identity_review'),
        orderJson(state: 'awaiting_payment'),
      ];
      await rig.mount(tester);
      expect(find.text('Crossmint is reviewing your details'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Start a new payment to finish'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('deposit-return-checkout')),
        findsNothing,
      );
      await reveal(tester, find.byKey(const ValueKey('deposit-start-new')));
      await tester.tap(find.byKey(const ValueKey('deposit-start-new')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('deposit-continue')), findsOneWidget);
      expect(await rig.memory.pending('user-1'), isNull);
    },
  );

  group('trade review funds check', () {
    late SyntheticPantaRig panta;
    setUp(() => panta = SyntheticPantaRig());
    tearDown(() => panta.close());

    Future<SheetRig> mountCheck(
      WidgetTester tester, {
      String usdc = '12500000',
      String lamports = '250000000',
    }) async {
      final rig = SheetRig();
      rig.bff.balance = balanceJson(
        wallet: syntheticWalletAddress,
        usdc: usdc,
        lamports: lamports,
      );
      rig.bff.status = statusJson(
        wallets: [walletJson(syntheticWalletAddress)],
      );
      await tester.pumpWidget(
        Provider<DepositsDependencies?>.value(
          value: rig.deps,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(body: TradeFundsCheck(controller: panta.controller)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      return rig;
    }

    testWidgets('reads the trading wallet and stays quiet when covered', (
      tester,
    ) async {
      final rig = await mountCheck(tester);
      panta.controller.editAmount('10');
      await tester.pump();
      expect(
        rig.bff.inputs('balance').single['wallet'],
        syntheticWalletAddress,
      );
      expect(
        find.text('In your wallet: 12.50 USDC · 0.25 SOL'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('trade-add-funds')), findsNothing);
    });

    testWidgets('a buy above the balance offers Add funds with the gap', (
      tester,
    ) async {
      await mountCheck(tester);
      panta.controller.editAmount('20');
      await tester.pump();
      expect(
        find.text('This buy is 20.00 USDC, 7.50 more than you have.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('trade-add-funds')), findsOneWidget);
      expect(find.text('Add funds'), findsOneWidget);
    });

    testWidgets('no SOL for fees is called out even when USDC covers it', (
      tester,
    ) async {
      await mountCheck(tester, lamports: '0');
      panta.controller.editAmount('5');
      await tester.pump();
      expect(find.byKey(const ValueKey('trade-funds-no-sol')), findsOneWidget);
      // A card can't buy SOL, so the action says what's actually missing.
      expect(find.text('Add SOL'), findsOneWidget);
      expect(find.text('Add funds'), findsNothing);
    });

    testWidgets('says nothing when the balance cannot be read', (tester) async {
      final rig = SheetRig();
      rig.bff.handlers['deposits.balance'] =
          (_) => trpcError('SERVICE_UNAVAILABLE', 'x', status: 503);
      await tester.pumpWidget(
        Provider<DepositsDependencies?>.value(
          value: rig.deps,
          child: MaterialApp(
            home: Scaffold(body: TradeFundsCheck(controller: panta.controller)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('trade-funds-check')), findsNothing);
    });
  });
}
