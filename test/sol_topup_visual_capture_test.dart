// Opt-in captures of "SOL for fees" with the real fonts and synthetic data,
// for design review. Writes nothing unless asked:
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_SOL_TOPUP=/abs/output/dir test/sol_topup_visual_capture_test.dart
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/sol_topup/domain/gasless_swap_check.dart'
    show CheckedSwap;
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/sol_topup/domain/sol_topup_signer.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_dependencies.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_prompt.dart';
import 'package:chumbucket/features/sol_topup/presentation/sol_topup_sheet.dart';
import 'package:chumbucket/features/sol_topup/sol_topup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'fixtures/jupiter_gasless_fixtures.dart';
import 'identity_fakes.dart' show kTestPhrase;
import 'sol_topup_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outDir = String.fromEnvironment('CAPTURE_SOL_TOPUP');
  late EmbeddedWalletKey owner;
  setUpAll(() async {
    owner = await EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase);
    if (outDir.isEmpty) return;
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final (family, paths) in [
      (
        'PPNeueMachina',
        [
          'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
          'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
        ],
      ),
      (
        'Montserrat',
        [
          'assets/fonts/Montserrat/Montserrat-Regular.ttf',
          'assets/fonts/Montserrat/Montserrat-Medium.ttf',
        ],
      ),
      (
        'Montserrat_regular',
        ['assets/fonts/Montserrat/Montserrat-Regular.ttf'],
      ),
      ('Montserrat_medium', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
      ('Inter_regular', ['assets/fonts/Inter/Inter-Regular.ttf']),
      ('Inter_500', ['assets/fonts/Inter/Inter-Medium.ttf']),
      ('Inter_600', ['assets/fonts/Inter/Inter-SemiBold.ttf']),
      ('Inter_700', ['assets/fonts/Inter/Inter-Bold.ttf']),
      ('Inter_800', ['assets/fonts/Inter/Inter-ExtraBold.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  SolTopUpSigner? signerFor(String wallet) =>
      EmbeddedSolTopUpSigner(signer: () => owner, address: wallet);
  SolTopUpSigner? walletApp(String wallet) => _WalletAppSigner(wallet);
  SolTopUpSigner? noSigner(String wallet) => null;

  Future<void> mount(
    WidgetTester tester,
    Widget body, {
    double width = 390,
    double height = 1400,
    double scale = 1,
    FakeTopUpBff? bff,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = bff ?? FakeTopUpBff();
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('sol-topup-capture'),
        child: Provider<SolTopUpDependencies?>.value(
          value: SolTopUpDependencies(
            createClient: fake.newClient,
            signerFor: signerFor,
          ),
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme,
                  builder:
                      (context, inner) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: inner!,
                      ),
                  home: Scaffold(
                    backgroundColor: const Color(0xFFEDEFF2),
                    body: SafeArea(child: body),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  Widget sheet(SolTopUpController c) => Align(
    alignment: Alignment.bottomCenter,
    child: SolTopUpSheet(controller: c),
  );

  Future<SolTopUpController> controller(
    WidgetTester tester,
    FakeTopUpBff bff, {
    bool review = false,
    bool done = false,
    SolTopUpSigner? Function(String wallet)? signer,
  }) async {
    final c = SolTopUpController(
      client: bff.newClient(),
      signerFor: signer ?? signerFor,
      wallet: kSwapOwner,
      now:
          () => DateTime.fromMillisecondsSinceEpoch(
            kMetisBlockTime * 1000,
            isUtc: true,
          ),
    );
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await c.load();
      if (review || done) await c.prepare();
      if (done) await c.approve();
    });
    return c;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byKey(const ValueKey('sol-topup-capture')),
      matchesGoldenFile(Uri.file('$outDir/sol-topup-$name.png')),
    );
  }

  final scenes = <String, Future<void> Function(WidgetTester)>{
    'choose': (tester) async {
      final bff = FakeTopUpBff()..plan = topUpPlanJson();
      await mount(tester, sheet(await controller(tester, bff)), bff: bff);
    },
    'review': (tester) async {
      final bff = FakeTopUpBff();
      await mount(
        tester,
        sheet(await controller(tester, bff, review: true)),
        bff: bff,
      );
    },
    'review-320-2x': (tester) async {
      final bff = FakeTopUpBff();
      await mount(
        tester,
        sheet(await controller(tester, bff, review: true)),
        width: 320,
        height: 2600,
        scale: 2,
        bff: bff,
      );
    },
    'done': (tester) async {
      final bff = FakeTopUpBff();
      await mount(
        tester,
        sheet(await controller(tester, bff, done: true)),
        bff: bff,
      );
    },
    'unavailable': (tester) async {
      final bff =
          FakeTopUpBff()
            ..status = topUpStatusJson(
              available: false,
              reason: 'Swapping USDC for SOL isn\'t set up yet.',
            );
      await mount(tester, sheet(await controller(tester, bff)), bff: bff);
    },
    'review-wallet-app': (tester) async {
      final bff = FakeTopUpBff();
      await mount(
        tester,
        sheet(await controller(tester, bff, review: true, signer: walletApp)),
        bff: bff,
      );
    },
    'needs-usdc': (tester) async {
      final bff =
          FakeTopUpBff()
            ..plan = topUpPlanJson(usdc: '400000', blocker: 'NEEDS_USDC');
      await mount(tester, sheet(await controller(tester, bff)), bff: bff);
    },
    'no-signer': (tester) async {
      final bff = FakeTopUpBff();
      await mount(
        tester,
        sheet(await controller(tester, bff, signer: noSigner)),
        bff: bff,
      );
    },
    'failed-unknown': (tester) async {
      final bff =
          FakeTopUpBff()
            ..execute = {
              'status': 'UNKNOWN',
              'message':
                  'We couldn\'t hear back from Jupiter. Check your balance in '
                  'a moment before trying again.',
            };
      await mount(
        tester,
        sheet(await controller(tester, bff, done: true)),
        bff: bff,
      );
    },
    'prompt': (tester) async {
      SolTopUpAvailability.reset();
      final bff = FakeTopUpBff()..plan = topUpPlanJson();
      await mount(
        tester,
        const Padding(
          padding: EdgeInsets.all(20),
          child: SolTopUpPrompt(wallet: kSwapOwner),
        ),
        height: 400,
        bff: bff,
      );
    },
  };

  for (final scene in scenes.entries) {
    testWidgets('capture ${scene.key}', (tester) async {
      await scene.value(tester);
      await capture(tester, scene.key);
    }, skip: outDir.isEmpty);
  }
}

/// A wallet app's signer, for the copy only: captures never sign with it.
class _WalletAppSigner implements SolTopUpSigner {
  _WalletAppSigner(this.address);
  @override
  final String address;
  @override
  TopUpSignerKind get kind => TopUpSignerKind.walletApp;
  @override
  Future<Uint8List> sign(Uint8List unsigned, CheckedSwap checked) =>
      throw const TopUpSignCancelled();
}
