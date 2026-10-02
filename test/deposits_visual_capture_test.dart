// Opt-in captures of the Add funds sheet with the real fonts and synthetic
// data, for design review. Writes nothing unless asked:
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_DEPOSITS=/abs/output/dir test/deposits_visual_capture_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'deposits_fakes.dart';
import 'deposits_sheet_test.dart' show SheetRig, reveal;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outDir = String.fromEnvironment('CAPTURE_DEPOSITS');
  setUpAll(() async {
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

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byKey(const ValueKey('deposits-capture')),
      matchesGoldenFile(Uri.file('$outDir/deposits-$name.png')),
    );
  }

  Future<SheetRig> started(
    WidgetTester tester,
    List<Map<String, Object?>> states, {
    String lamports = '250000000',
  }) async {
    final rig =
        SheetRig()
          ..bff.orderStates = [orderJson()]
          ..bff.balance = balanceJson(lamports: lamports);
    await rig.mount(tester, height: 1500);
    await reveal(tester, find.byKey(const ValueKey('deposit-continue')));
    await tester.tap(find.byKey(const ValueKey('deposit-continue')));
    await tester.pump(const Duration(milliseconds: 200));
    rig.bff.orderStates = states;
    rig.checkoutClosed.complete();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 3000));
    return rig;
  }

  final scenes = <String, Future<void> Function(WidgetTester)>{
    'choose': (tester) async {
      await SheetRig().mount(tester, height: 1500);
    },
    'choose-320-2x': (tester) async {
      await SheetRig().mount(tester, width: 320, height: 2400, scale: 2);
    },
    'trade-gap': (tester) async {
      final rig = SheetRig()..bff.balance = balanceJson(usdc: '5000000');
      await rig.mount(tester, height: 1500, required: BigInt.from(30000000));
    },
    'test-mode-email': (tester) async {
      final rig =
          SheetRig()
            ..bff.status = statusJson(
              environment: 'staging',
              needsEmail: true,
              presets: ['1', '5', '10'],
            );
      await rig.mount(tester, height: 1700);
    },
    'unavailable': (tester) async {
      final rig =
          SheetRig()
            ..bff.status = statusJson(
              available: false,
              reason: {
                'code': 'NOT_CONFIGURED',
                'message': 'Adding funds isn\'t set up yet.',
              },
            );
      await rig.mount(tester, height: 1500);
    },
    'delivering': (tester) async {
      await started(tester, [orderJson(state: 'delivering')]);
    },
    'wallet-proof': (tester) async {
      await started(tester, [
        orderJson(state: 'awaiting_wallet_proof', proof: 'Verify ownership'),
      ]);
    },
    'delivered': (tester) async {
      await started(tester, [
        orderJson(
          state: 'delivered',
          txId: syntheticTx,
          receive: const {'min': '24.21', 'max': '24.21'},
        ),
      ]);
    },
    'choose-no-sol': (tester) async {
      final rig = SheetRig()..bff.balance = balanceJson(lamports: '0');
      await rig.mount(tester, height: 2000);
    },
    'delivered-no-sol': (tester) async {
      await started(tester, [
        orderJson(
          state: 'delivered',
          txId: syntheticTx,
          receive: const {'min': '24.21', 'max': '24.21'},
        ),
      ], lamports: '0');
    },
    'delivery-failed': (tester) async {
      await started(tester, [
        orderJson(state: 'delivery_failed', refundedUsd: '25'),
      ]);
    },
  };

  for (final scene in scenes.entries) {
    testWidgets('capture ${scene.key}', (tester) async {
      await scene.value(tester);
      await capture(tester, scene.key);
      // Let post-delivery balance re-reads finish before teardown.
      await tester.pump(const Duration(seconds: 5));
    }, skip: outDir.isEmpty);
  }
}
