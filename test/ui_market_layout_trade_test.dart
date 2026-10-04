import 'dart:async';
import 'dart:typed_data';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'panta_trading_controller_test.dart'
    show SyntheticPantaRig, syntheticSigned, syntheticOrderJson;

const question =
    'Will the named asset close strictly above the exact market threshold at the official observation time?';

Finder get verticalScroll =>
    find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: verticalScroll,
    maxScrolls: 100,
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String label) async {
  await reveal(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  late SyntheticPantaRig rig;
  setUp(() => rig = SyntheticPantaRig());
  tearDown(() => rig.close());

  Future<void> open(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
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
                        onPressed:
                            () => showPantaTradeSheet(
                              context: context,
                              controller: rig.controller,
                              marketQuestion: question,
                            ),
                        child: const Text('Open review'),
                      ),
                ),
              ),
            ),
      ),
    );
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
  }

  Future<void> prepare(WidgetTester tester) async {
    await reveal(tester, find.byKey(const ValueKey('panta-amount')));
    await tester.enterText(find.byKey(const ValueKey('panta-amount')), '10');
    await tester.pump();
    await tap(tester, 'Review order');
    expect(rig.controller.phase, PantaTradePhase.review);
  }

  for (final width in [320.0, 390.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('deliberate trade review fits $width dp / $scale text', (
        tester,
      ) async {
        await open(tester, width: width, scale: scale);
        expect(find.byType(ChumbucketWavySheet), findsOneWidget);
        final renderedQuestion = tester.widget<Text>(find.text(question));
        expect(renderedQuestion.maxLines, isNull);
        expect(renderedQuestion.overflow, isNull);
        await prepare(tester);
        expect(rig.wallet.signCount, 0);
        // Money in dollars; never a per-share price (an average above a
        // whole share has no odds row at all).
        await reveal(tester, find.text('Venue fee'));
        expect(find.textContaining('USDC/share'), findsNothing);
        expect(find.text('Average odds'), findsNothing);
        await reveal(tester, find.text('Quote expires'));
        expect(
          find.textContaining('Not supplied in this quote'),
          findsOneWidget,
        );
        expect(find.textContaining('Estimate not supplied'), findsOneWidget);
        await reveal(tester, find.text('Approve in wallet'));
        // The rendered target, not a style hint: at least 48dp tall.
        expect(
          tester
              .getSize(
                find.widgetWithText(
                  ChumbucketPrimaryButton,
                  'Approve in wallet',
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
        expect(find.textContaining('chance'), findsNothing);
        expect(find.textContaining('probability'), findsNothing);
        expect(rig.wallet.signCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('over ceiling and malformed amounts never prepare', (
    tester,
  ) async {
    await open(tester);
    for (final value in ['100.000001', '1e1', '0.0000001', '0']) {
      // Scroll back to the beginning after inspecting the action.
      final scrollable = tester.state<ScrollableState>(verticalScroll);
      scrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('panta-amount')));
      await tester.enterText(find.byKey(const ValueKey('panta-amount')), value);
      await tester.pump();
      await reveal(tester, find.text('Review order'));
      final action = tester.widget<ChumbucketPrimaryButton>(
        find.widgetWithText(ChumbucketPrimaryButton, 'Review order'),
      );
      expect(action.onPressed, isNull);
      expect(rig.procedure('prepare'), isEmpty);
      expect(rig.wallet.signCount, 0);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('explicit approval remains submitted until authoritative fill', (
    tester,
  ) async {
    await open(tester);
    await prepare(tester);
    await tap(tester, 'Approve in wallet');
    expect(rig.wallet.signCount, 1);
    expect(
      find.text('Submitted · awaiting fill confirmation.'),
      findsOneWidget,
    );
    expect(rig.controller.isFunded, isFalse);
    rig.serverState = 'PARTIAL';
    await tap(tester, 'Check order status');
    expect(rig.controller.isFunded, isFalse);
    rig.serverState = 'FILLED';
    await tap(tester, 'Check order status');
    expect(rig.controller.isFunded, isTrue);
    expect(rig.wallet.signCount, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired quote cancels without signing', (tester) async {
    await open(tester);
    await prepare(tester);
    rig.now = rig.now.add(const Duration(minutes: 2));
    await rig.controller.loadStatus();
    await tester.pumpAndSettle();
    await tap(tester, 'Cancel expired quote');
    expect(rig.wallet.signCount, 0);
    expect(rig.controller.phase, PantaTradePhase.cancelled);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancel during wallet approval prevents late submission', (
    tester,
  ) async {
    await open(tester);
    await prepare(tester);
    final signing = Completer<Uint8List>();
    Uint8List? unsigned;
    rig.wallet.reply = (bytes) {
      unsigned = bytes;
      return signing.future;
    };
    await tap(tester, 'Approve in wallet');
    expect(rig.wallet.signCount, 1);
    await tap(tester, 'Cancel');
    signing.complete(syntheticSigned(unsigned!));
    await tester.pumpAndSettle();
    expect(rig.procedure('submit'), isEmpty);
    expect(rig.controller.phase, PantaTradePhase.cancelled);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unknown submission retains same transaction through reopen', (
    tester,
  ) async {
    var drop = true;
    rig.intercept = (request) {
      if (request.url.path.endsWith('.submit') && drop) {
        drop = false;
        throw http.ClientException('synthetic connection loss');
      }
      return null;
    };
    await open(tester);
    await prepare(tester);
    await tap(tester, 'Approve in wallet');
    expect(rig.controller.phase, PantaTradePhase.signed);
    await tap(tester, 'Close');
    await tester.tap(find.text('Open review'));
    await tester.pumpAndSettle();
    await tap(tester, 'Resend same transaction');
    expect(rig.inputs('submit')[0], rig.inputs('submit')[1]);
    expect(rig.wallet.signCount, 1);
    expect(rig.procedure('prepare'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled venue uses safe error copy and cannot prepare', (
    tester,
  ) async {
    rig.enabled = false;
    rig.statusReason = 'provider text must stay hidden';
    await open(tester);
    await reveal(tester, find.text('Panta funding is unavailable right now.'));
    expect(find.textContaining('provider text'), findsNothing);
    final scrollable = tester.state<ScrollableState>(verticalScroll);
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('panta-amount')));
    await tester.enterText(find.byKey(const ValueKey('panta-amount')), '10');
    await tester.pump();
    await tap(tester, 'Review order');
    expect(rig.procedure('prepare'), isEmpty);
    expect(rig.wallet.signCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('recovered pending order never opens another approval', (
    tester,
  ) async {
    rig.recoveredOrder = syntheticOrderJson();
    await open(tester, width: 320, scale: 2);
    expect(find.byKey(const ValueKey('panta-amount')), findsNothing);
    expect(find.text('Approve in wallet'), findsNothing);
    await reveal(tester, find.text('Check order status'));
    expect(rig.procedure('prepare'), isEmpty);
    expect(rig.wallet.signCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
