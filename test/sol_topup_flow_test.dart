/// "SOL for fees" end to end on the phone, with a fake BFF transport: the
/// client's wire, the controller's journey (real transaction shapes, the
/// on-phone signer and its signature), the sheet at 320dp/2x, the inline
/// prompt, and the mainnet balance on Profile's wallet card and the on-phone
/// wallet sheet. Nothing leaves the test; every key is public test data.
library;

import 'dart:convert';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/deposits/data/deposit_order_memory.dart';
import 'package:chumbucket/features/deposits/presentation/deposits_dependencies.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:chumbucket/features/embedded_wallet/presentation/embedded_wallet_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/sol_topup/data/sol_topup_client.dart';
import 'package:chumbucket/features/sol_topup/data/sol_topup_models.dart';
import 'package:chumbucket/features/sol_topup/domain/gasless_swap_check.dart';
import 'package:chumbucket/features/sol_topup/domain/sol_topup_signer.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_dependencies.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_prompt.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_sheet.dart';
import 'package:chumbucket/features/sol_topup/sol_topup_controller.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:solana/solana.dart' show Ed25519HDPublicKey, verifySignature;

import 'deposits_fakes.dart';
import 'sol_topup_fakes.dart';
import 'fixtures/jupiter_gasless_fixtures.dart';
import 'identity_fakes.dart' show MemorySecretStore, kTestPhrase;

DateTime _atMetis() =>
    DateTime.fromMillisecondsSinceEpoch(kMetisBlockTime * 1000, isUtc: true);

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  List<SingleChildWidget> providers = const [],
  double width = 390,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [Provider<int>.value(value: 0), ...providers],
      child: ScreenUtilInit(
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
              home: Scaffold(body: child),
            ),
      ),
    ),
  );
}

void main() {
  late EmbeddedWalletKey owner;
  setUpAll(() async {
    owner = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
    dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet');
  });
  setUp(SolTopUpAvailability.reset);

  SolTopUpSigner? onPhone(String wallet) =>
      wallet == kSwapOwner
          ? EmbeddedSolTopUpSigner(signer: () => owner, address: wallet)
          : null;

  group('SolTopUpClient', () {
    test('posts with the session token and parses each answer', () async {
      final bff = FakeTopUpBff();
      final client = bff.newClient();
      expect((await client.status()).available, isTrue);
      final plan = await client.plan(wallet: kSwapOwner);
      expect(plan.needsSol, isTrue);
      expect(plan.suggestion!.tradesCovered, 4);
      final order = await client.order(
        wallet: kSwapOwner,
        amountBaseUnits: BigInt.from(kMetisInAmount),
      );
      expect(order.review.paidByJupiter, isTrue);
      expect(order.review.router, SwapRouter.metis);
      final result = await client.execute(
        requestId: 'req-metis-0001',
        signedTransaction: 'c2lnbmVk',
      );
      expect(result.outcome, TopUpOutcome.success);
      expect(result.explorerUri!.host, 'explorer.solana.com');
      expect(
        bff.calls.map((c) => c.$3).skip(1),
        everyElement('Bearer synthetic-session-token'),
      );
      expect(bff.inputs('order').single, {
        'wallet': kSwapOwner,
        'amountBaseUnits': '$kMetisInAmount',
      });
    });

    test('an expected "no" becomes a kind the sheet acts on', () async {
      final bff = FakeTopUpBff();
      for (final (reason, kind) in [
        ('BELOW_GASLESS_MINIMUM', TopUpErrorKind.belowGaslessMinimum),
        ('NEEDS_USDC', TopUpErrorKind.needsUsdc),
        ('ENOUGH_SOL', TopUpErrorKind.enoughSol),
        ('NOT_GASLESS', TopUpErrorKind.notGasless),
      ]) {
        bff.order = {'status': 'REFUSED', 'reason': reason, 'message': 'x'};
        await expectLater(
          bff.newClient().order(
            wallet: kSwapOwner,
            amountBaseUnits: BigInt.one,
          ),
          throwsA(isA<TopUpException>().having((e) => e.kind, 'kind', kind)),
        );
      }
      bff.handlers['solTopUp.plan'] =
          (_) => trpcError(
            'UNAUTHORIZED',
            'Sign in to swap for SOL.',
            status: 401,
          );
      await expectLater(
        bff.newClient().plan(),
        throwsA(
          isA<TopUpException>().having(
            (e) => e.kind,
            'kind',
            TopUpErrorKind.signedOut,
          ),
        ),
      );
    });

    test(
      'refuses a devnet answer, a muddled review and a non-HTTPS base',
      () async {
        final bff = FakeTopUpBff();
        bff.plan = {...topUpPlanJson(), 'network': 'solana-devnet'};
        await expectLater(
          bff.newClient().plan(),
          throwsA(isA<TopUpException>()),
        );
        bff.order = {
          ...metisOrderJson(),
          'review': {
            ...(metisOrderJson()['review'] as Map<String, Object?>),
            'networkFeePaidBy': 'market_maker',
          },
        };
        await expectLater(
          bff.newClient().order(
            wallet: kSwapOwner,
            amountBaseUnits: BigInt.one,
          ),
          throwsA(isA<TopUpException>()),
        );
        expect(
          () => SolTopUpClient(
            baseUri: Uri.parse('http://bff.invalid'),
            token: () => 't',
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('SolTopUpController', () {
    test(
      'plan -> review (checked here) -> signed on this phone -> SOL landed',
      () async {
        final bff = FakeTopUpBff();
        final c = SolTopUpController(
          client: bff.newClient(),
          signerFor: onPhone,
          wallet: kSwapOwner,
          now: _atMetis,
        );
        addTearDown(c.dispose);
        await c.load();
        expect(c.stage, SolTopUpStage.choose);
        expect(c.amount, BigInt.from(kMetisInAmount));
        await c.prepare();
        expect(c.stage, SolTopUpStage.review);
        expect(c.checked!.minOutLamports, BigInt.from(105660949));
        expect(bff.inputs('execute'), isEmpty);
        await c.approve();
        expect(c.stage, SolTopUpStage.done);
        // What reached the server: the reviewed message, signed by the person.
        final sent = base64Decode(
          bff.inputs('execute').single['signedTransaction'] as String,
        );
        final unsigned = base64Decode(kMetisSwapBase64);
        expect(sent.sublist(129), unsigned.sublist(129));
        expect(sent.sublist(1, 65), unsigned.sublist(1, 65));
        expect(
          await verifySignature(
            message: c.checked!.messageBytes,
            signature: sent.sublist(65, 129),
            publicKey: Ed25519HDPublicKey.fromBase58(kSwapOwner),
          ),
          isTrue,
        );
        expect(c.result!.solReceivedLamports, BigInt.from(106119149));
      },
    );

    test(
      'a review that disagrees with its own transaction is never signed',
      () async {
        final bff = FakeTopUpBff()..order = metisOrderJson(feePayer: kRfqMaker);
        final c = SolTopUpController(
          client: bff.newClient(),
          signerFor: onPhone,
          now: _atMetis,
        );
        addTearDown(c.dispose);
        await c.load();
        await c.prepare();
        expect(c.stage, SolTopUpStage.choose);
        expect(c.message, contains('didn’t pass this phone’s checks'));
        expect(bff.inputs('execute'), isEmpty);
      },
    );

    test('a tampered transaction is caught on the phone', () async {
      final bff = FakeTopUpBff();
      final tampered = base64Decode(kMetisSwapBase64)..[300] ^= 0xff;
      bff.order = {...metisOrderJson(), 'transaction': base64Encode(tampered)};
      final c = SolTopUpController(
        client: bff.newClient(),
        signerFor: onPhone,
        now: _atMetis,
      );
      addTearDown(c.dispose);
      await c.load();
      await c.prepare();
      expect(c.stage, SolTopUpStage.choose);
      expect(c.order, isNull);
    });

    test(
      'below Jupiter\'s minimum: offers the next amount, never swaps more on its own',
      () async {
        final bff =
            FakeTopUpBff()
              ..plan = topUpPlanJson()
              ..order = {
                'status': 'REFUSED',
                'reason': 'BELOW_GASLESS_MINIMUM',
                'message':
                    'Jupiter only pays the network fee on bigger swaps right now.',
              };
        final c = SolTopUpController(
          client: bff.newClient(),
          signerFor: onPhone,
        );
        addTearDown(c.dispose);
        await c.load();
        expect(c.amountOptions, [
          BigInt.from(1000000),
          BigInt.from(2000000),
          BigInt.from(5000000),
        ]);
        await c.prepare();
        expect(c.stage, SolTopUpStage.choose);
        expect(c.belowMinimum, isTrue);
        expect(c.amount, BigInt.from(2000000));
        expect(c.message, contains('Try 2.00 USDC'));
        expect(c.amountOptions, [BigInt.from(2000000), BigInt.from(5000000)]);
        expect(bff.inputs('order').single['amountBaseUnits'], '1000000');
      },
    );

    test(
      'honest stops: unconfigured, not needed, no USDC, key not here',
      () async {
        final off =
            FakeTopUpBff()
              ..status = topUpStatusJson(
                available: false,
                reason: 'Swapping USDC for SOL isn\'t set up yet.',
              );
        final a = SolTopUpController(
          client: off.newClient(),
          signerFor: onPhone,
        );
        await a.load();
        expect(a.stage, SolTopUpStage.unavailable);
        expect(a.message, 'Swapping USDC for SOL isn\'t set up yet.');
        expect(off.inputs('plan'), isEmpty);

        final enough =
            FakeTopUpBff()
              ..plan = topUpPlanJson(blocker: 'ENOUGH_SOL', coveredNow: 5);
        final b = SolTopUpController(
          client: enough.newClient(),
          signerFor: onPhone,
        );
        await b.load();
        expect(b.stage, SolTopUpStage.notNeeded);

        final poor =
            FakeTopUpBff()..plan = topUpPlanJson(blocker: 'NEEDS_USDC');
        final d = SolTopUpController(
          client: poor.newClient(),
          signerFor: onPhone,
        );
        await d.load();
        expect(d.stage, SolTopUpStage.needsUsdc);

        final elsewhere = FakeTopUpBff();
        final e = SolTopUpController(
          client: elsewhere.newClient(),
          signerFor: (_) => null,
        );
        await e.load();
        expect(e.stage, SolTopUpStage.noSigner);
        for (final x in [a, b, d, e]) {
          x.dispose();
        }
      },
    );

    test('an expired quote is not signed; a lost reply is "unknown"', () async {
      final bff = FakeTopUpBff();
      var now = _atMetis();
      final c = SolTopUpController(
        client: bff.newClient(),
        signerFor: onPhone,
        now: () => now,
      );
      addTearDown(c.dispose);
      await c.load();
      await c.prepare();
      now = now.add(const Duration(minutes: 2));
      await c.approve();
      expect(c.stage, SolTopUpStage.choose);
      expect(c.message, contains('expired'));
      expect(bff.inputs('execute'), isEmpty);

      now = _atMetis();
      await c.prepare();
      bff.handlers['solTopUp.execute'] =
          (_) => throw http.ClientException('lost');
      await c.approve();
      expect(c.stage, SolTopUpStage.failed);
      expect(c.unknown, isTrue);
      expect(c.message, contains('Check your balance'));
    });

    test(
      'anything the phone can\'t decode is refused, never left spinning',
      () async {
        final bff = FakeTopUpBff();
        final c = SolTopUpController(
          client: bff.newClient(),
          signerFor: onPhone,
          now: _atMetis,
        );
        addTearDown(c.dispose);
        await c.load();
        // Valid base64 that isn't a transaction: the phone's own check.
        bff.order = {
          ...metisOrderJson(),
          'transaction': base64Encode(List<int>.filled(40, 7)),
        };
        await c.prepare();
        expect(c.stage, SolTopUpStage.choose);
        expect(c.busy, isFalse);
        expect(c.order, isNull);
        expect(c.message, contains('Nothing was signed'));
        // Not base64 at all: refused as a malformed answer.
        bff.order = {...metisOrderJson(), 'transaction': 'not*base64*at*all'};
        await c.prepare();
        expect(c.stage, SolTopUpStage.choose);
        expect(c.busy, isFalse);
        expect(c.order, isNull);
        expect(bff.inputs('execute'), isEmpty);
      },
    );

    test(
      'after signing, an unreadable reply is "unknown" — never "nothing was signed"',
      () async {
        final bff = FakeTopUpBff();
        final c = SolTopUpController(
          client: bff.newClient(),
          signerFor: onPhone,
          now: _atMetis,
        );
        addTearDown(c.dispose);
        await c.load();
        await c.prepare();
        bff.handlers['solTopUp.execute'] =
            (_) => http.Response('<html>502 Bad Gateway</html>', 502);
        await c.approve();
        expect(c.stage, SolTopUpStage.failed);
        expect(c.unknown, isTrue);
        expect(c.message, contains('Check your balance'));
        expect(c.message, isNot(contains('Nothing was signed')));
      },
    );
  });

  group('the sheet', () {
    Future<FakeTopUpBff> openSheet(
      WidgetTester tester, {
      double width = 390,
      double scale = 1,
      FakeTopUpBff? fake,
    }) async {
      final bff = fake ?? FakeTopUpBff();
      final controller = SolTopUpController(
        client: bff.newClient(),
        signerFor: onPhone,
        wallet: kSwapOwner,
        now: _atMetis,
      );
      addTearDown(controller.dispose);
      await _mount(
        tester,
        Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed:
                      () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => SolTopUpSheet(controller: controller),
                      ),
                  child: const Text('open'),
                ),
              ),
        ),
        width: width,
        scale: scale,
      );
      await controller.load();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return bff;
    }

    testWidgets(
      'review says who pays, signs on the button, then shows what landed',
      (tester) async {
        final bff = await openSheet(tester);
        expect(find.byKey(const ValueKey('sol-topup-balance')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sol-topup-estimate')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('sol-topup-get-quote')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sol-topup-get-quote')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Paid by Jupiter, not you'), findsOneWidget);
        expect(
          find.textContaining('there is no second screen'),
          findsOneWidget,
        );
        expect(find.text('Sign and swap'), findsOneWidget);
        expect(bff.inputs('execute'), isEmpty);
        await tester.ensureVisible(
          find.byKey(const ValueKey('sol-topup-approve')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sol-topup-approve')));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('sol-topup-done')), findsOneWidget);
        expect(find.text('0.1061 SOL landed in your wallet.'), findsOneWidget);
        expect(bff.inputs('execute'), hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'when Jupiter reports no amount, "landed" says only the signed minimum',
      (tester) async {
        final bff = await openSheet(tester);
        bff.execute = {'status': 'SUCCESS', 'signature': '5' * 88};
        for (final key in ['sol-topup-get-quote', 'sol-topup-approve']) {
          await tester.ensureVisible(find.byKey(ValueKey(key)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey(key)));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.text('At least 0.1056 SOL landed in your wallet.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'swaps off: "send SOL yourself" still shows the wallet\'s address',
      (tester) async {
        await openSheet(
          tester,
          fake:
              FakeTopUpBff()
                ..status = topUpStatusJson(
                  available: false,
                  reason: 'Swapping USDC for SOL isn\'t set up yet.',
                ),
        );
        expect(
          find.byKey(const ValueKey('sol-topup-unavailable')),
          findsOneWidget,
        );
        expect(find.text('Or send SOL yourself'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('fits 320dp at 2x text', (tester) async {
      await openSheet(tester, width: 320, scale: 2);
      await tester.ensureVisible(
        find.byKey(const ValueKey('sol-topup-get-quote')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sol-topup-get-quote')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sol-topup-review')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the prompt', () {
    Future<void> mountPrompt(
      WidgetTester tester,
      FakeTopUpBff bff, {
      bool alwaysShow = false,
    }) async {
      await _mount(
        tester,
        SolTopUpPrompt(
          wallet: kSwapOwner,
          alwaysShow: alwaysShow,
          fallback: const Text('send SOL yourself', key: ValueKey('fallback')),
        ),
        providers: [
          Provider<SolTopUpDependencies?>.value(
            value: SolTopUpDependencies(
              createClient: bff.newClient,
              signerFor: onPhone,
            ),
          ),
        ],
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('appears when the wallet can\'t pay for a trade', (
      tester,
    ) async {
      final bff = FakeTopUpBff()..plan = topUpPlanJson();
      await mountPrompt(tester, bff);
      expect(find.text('Not enough SOL to trade yet'), findsOneWidget);
      expect(find.text('Get SOL for fees'), findsOneWidget);
      expect(find.byKey(const ValueKey('fallback')), findsNothing);
    });

    testWidgets('stays out of the way when SOL is fine, unless asked', (
      tester,
    ) async {
      final bff =
          FakeTopUpBff()
            ..plan = topUpPlanJson(
              blocker: 'ENOUGH_SOL',
              coveredNow: 5,
              lamports: '10000000',
            );
      await mountPrompt(tester, bff);
      expect(find.byKey(const ValueKey('sol-topup-prompt')), findsNothing);
      SolTopUpAvailability.reset();
      await mountPrompt(tester, bff, alwaysShow: true);
      expect(find.text('SOL for about 5 more new trades'), findsOneWidget);
      expect(find.text('Get SOL for fees'), findsNothing);
    });

    testWidgets('swaps switched off: the "send SOL" path instead', (
      tester,
    ) async {
      final bff = FakeTopUpBff()..status = topUpStatusJson(available: false);
      await mountPrompt(tester, bff);
      expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
      expect(bff.inputs('plan'), isEmpty);
    });
  });

  group('mainnet balance on the wallet surfaces', () {
    testWidgets(
      'Profile\'s card shows the server\'s mainnet USDC and SOL, never devnet',
      (tester) async {
        final deposits =
            FakeDepositsBff()
              ..balance = balanceJson(lamports: '8470153', usdc: '12400000');
        final wallet = _ConnectedWallet();
        await _mount(
          tester,
          const ProfileWalletCard(),
          providers: [
            Provider<DepositsDependencies?>.value(
              value: DepositsDependencies(
                createClient: deposits.newClient,
                accountId: 'user-1',
                memory: InMemoryDepositOrderMemory(),
              ),
            ),
            ChangeNotifierProvider<MwaWalletProvider?>.value(value: wallet),
          ],
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Connected · only you see this\n12.40 USDC · 0.0084 SOL'),
          findsOneWidget,
        );
        expect(deposits.inputs('balance').single, {'wallet': walletA});
        // The legacy provider's devnet balance is never read for display.
        expect(find.textContaining('2.50'), findsNothing);
      },
    );

    testWidgets(
      'the wallet on this phone: balance, Add funds and SOL for fees',
      (tester) async {
        final deposits =
            FakeDepositsBff()
              ..balance = balanceJson(
                wallet: kSwapOwner,
                lamports: '0',
                usdc: '12400000',
              );
        final topUp = FakeTopUpBff()..plan = topUpPlanJson();
        final vault = EmbeddedWalletVault(store: MemorySecretStore());
        await vault.save(
          'user-1',
          EmbeddedWalletRecord(
            address: kSwapOwner,
            recoveryPhrase: kTestPhrase,
            linked: true,
            createdAt: DateTime.utc(2026, 10, 2),
          ),
        );
        final controller = EmbeddedWalletController(
          vault: vault,
          bff: SessionBffClient(
            baseUrl: 'https://bff.invalid',
            httpClient: MockClient(
              (_) async => throw StateError('no link call'),
            ),
          ),
          authToken: () async => 'synthetic-session-token',
        );
        addTearDown(controller.dispose);
        await tester.runAsync(() => controller.bind('user-1'));
        expect(controller.signer?.address, kSwapOwner);
        await _mount(
          tester,
          const EmbeddedWalletSheet(),
          providers: [
            ChangeNotifierProvider<EmbeddedWalletController>.value(
              value: controller,
            ),
            Provider<DepositsDependencies?>.value(
              value: DepositsDependencies(
                createClient: deposits.newClient,
                accountId: 'user-1',
                memory: InMemoryDepositOrderMemory(),
              ),
            ),
            Provider<SolTopUpDependencies?>.value(
              value: SolTopUpDependencies(
                createClient: topUp.newClient,
                signerFor: onPhone,
              ),
            ),
          ],
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('deposit-balance-usdc')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('embedded-add-funds')),
          findsOneWidget,
        );
        expect(find.text('Get SOL for fees'), findsOneWidget);
        expect(deposits.inputs('balance').single, {'wallet': kSwapOwner});
        expect(topUp.inputs('plan').single, {'wallet': kSwapOwner});
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _ConnectedWallet extends MwaWalletProvider {
  @override
  String? get walletAddress => walletA;
  @override
  bool get isInitialized => true;
  @override
  double get balance => 2.5;
}
