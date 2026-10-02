import 'dart:async';
import 'dart:typed_data';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:chumbucket/shared/widgets/icons/basil_icon.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'panta_trading_controller_test.dart'
    show SyntheticPantaRig, syntheticSigned, syntheticOrderJson;

Finder get verticalScroll =>
    find
        .byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        )
        .last;

Future<void> reveal(WidgetTester tester, Finder target) async {
  tester.state<ScrollableState>(verticalScroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: verticalScroll,
    maxScrolls: 100,
  );
  await tester.pumpAndSettle();
}

Future<void> tapAction(WidgetTester tester, String label) async {
  await reveal(tester, find.text(label));
  await tester.tap(find.text(label));
}

Future<void> enterAmount(WidgetTester tester, String value) async {
  tester.state<ScrollableState>(verticalScroll).position.jumpTo(0);
  await tester.pumpAndSettle();
  await reveal(tester, find.byKey(const ValueKey('panta-amount')));
  await tester.enterText(find.byKey(const ValueKey('panta-amount')), value);
}

void main() {
  late SyntheticPantaRig r;
  setUp(() => r = SyntheticPantaRig());
  tearDown(() => r.close());

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
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
                              controller: r.controller,
                              marketQuestion: 'Existing call question?',
                            ),
                        child: const Text('Fund existing call'),
                      ),
                ),
              ),
            ),
      ),
    );
    await tester.tap(find.text('Fund existing call'));
    await tester.pumpAndSettle();
  }

  Future<void> review(WidgetTester tester) async {
    await enterAmount(tester, '10');
    await tester.pump();
    await tapAction(tester, 'Review order');
    await tester.pumpAndSettle();
    expect(r.controller.phase, PantaTradePhase.review);
  }

  testWidgets(
    'existing sheet/components show review before explicit wallet approval',
    (tester) async {
      await open(tester);
      expect(find.byType(ChumbucketWavySheet), findsOneWidget);
      expect(find.byType(BasilIcon), findsWidgets);
      await reveal(tester, find.text('Review order'));
      expect(
        find.widgetWithText(ChumbucketPrimaryButton, 'Review order'),
        findsOneWidget,
      );
      await reveal(tester, find.textContaining('Up to 100 USDC'));
      expect(find.textContaining('Up to 100 USDC'), findsOneWidget);
      expect(r.wallet.signCount, 0);
      await review(tester);
      await reveal(tester, find.text('USDC to spend'));
      expect(find.text('USDC to spend'), findsOneWidget);
      await reveal(tester, find.text('Venue fee'));
      expect(find.text('Venue fee'), findsOneWidget);
      expect(find.text('Estimated shares'), findsOneWidget);
      expect(find.text('1.250000000000000001 USDC/share'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Powered by Panta'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Powered by Panta'), findsOneWidget);
      expect(find.textContaining('probability'), findsNothing);
      expect(find.textContaining('chance'), findsNothing);
      expect(find.textContaining('PnL'), findsNothing);
      expect(find.text('Funded'), findsNothing);
      expect(r.wallet.signCount, 0);
      await tapAction(tester, 'Approve in wallet');
      await tester.pumpAndSettle();
      expect(r.wallet.signCount, 1);
      expect(
        find.text('Submitted · awaiting fill confirmation.'),
        findsOneWidget,
      );
      expect(find.textContaining('Funded'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final scale in [1.0, 1.8]) {
    testWidgets('review scrolls without overflow at text scale $scale', (
      tester,
    ) async {
      await open(tester, scale: scale);
      await review(tester);
      await tester.scrollUntilVisible(
        find.text('Powered by Panta'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('disabled status copy never renders provider reason or signs', (
    tester,
  ) async {
    r.enabled = false;
    r.statusReason = 'untrusted provider detail synthetic-bearer';
    await open(tester);
    await reveal(tester, find.text('Panta funding is unavailable right now.'));
    expect(
      find.text('Panta funding is unavailable right now.'),
      findsOneWidget,
    );
    expect(find.textContaining('untrusted'), findsNothing);
    await enterAmount(tester, '10');
    await tapAction(tester, 'Review order');
    await tester.pumpAndSettle();
    expect(r.procedure('prepare'), isEmpty);
    expect(r.wallet.signCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'cold restored order has status checks without new wallet action',
    (tester) async {
      r.recoveredOrder = syntheticOrderJson();
      await open(tester);
      expect(find.byKey(const ValueKey('panta-amount')), findsNothing);
      expect(find.text('Approve in wallet'), findsNothing);
      expect(
        find.text('Submitted · awaiting fill confirmation.'),
        findsOneWidget,
      );
      await reveal(tester, find.text('Check order status'));
      expect(find.text('Check order status'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(r.wallet.signCount, 0);
      expect(r.procedure('prepare'), isEmpty);
      r.serverState = 'FILLED';
      await tapAction(tester, 'Check order status');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Funded · fill confirmed by the server.'));
      expect(
        find.text('Funded · fill confirmed by the server.'),
        findsOneWidget,
      );
      expect(r.wallet.signCount, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('rejects over-cap or exponent entry without preparing', (
    tester,
  ) async {
    await open(tester);
    for (final input in ['100.000001', '1e1', '0.0000001']) {
      await enterAmount(tester, input);
      await tapAction(tester, 'Review order');
      await tester.pump();
      expect(r.procedure('prepare'), isEmpty);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dismissal during pending wallet approval prevents late submit', (
    tester,
  ) async {
    await open(tester);
    await review(tester);
    final signing = Completer<Uint8List>();
    Uint8List? unsigned;
    r.wallet.reply = (bytes) {
      unsigned = bytes;
      return signing.future;
    };
    await tapAction(tester, 'Approve in wallet');
    await tester.pump();
    expect(r.wallet.signCount, 1);
    await tapAction(tester, 'Cancel');
    await tester.pumpAndSettle();
    signing.complete(syntheticSigned(unsigned!));
    await tester.pumpAndSettle();
    expect(r.procedure('submit'), isEmpty);
    expect(r.controller.phase, PantaTradePhase.cancelled);
    expect(r.controller.isFunded, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expired review has explicit cancellation before another quote', (
    tester,
  ) async {
    await open(tester);
    await review(tester);
    r.now = r.now.add(const Duration(minutes: 2));
    await r.controller.loadStatus();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Cancel expired quote'));
    expect(find.text('Cancel expired quote'), findsOneWidget);
    await tapAction(tester, 'Cancel expired quote');
    await tester.pumpAndSettle();
    expect(r.wallet.signCount, 0);
    expect(r.controller.phase, PantaTradePhase.cancelled);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('uncertain submit survives close/reopen and manual retry', (
    tester,
  ) async {
    var drop = true;
    r.intercept = (request) {
      if (request.url.path.endsWith('.submit') && drop) {
        drop = false;
        throw http.ClientException('untrusted body');
      }
      return null;
    };
    await open(tester);
    await review(tester);
    await tapAction(tester, 'Approve in wallet');
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Retry same signed transaction'));
    expect(find.text('Retry same signed transaction'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    await tapAction(tester, 'Close');
    await tester.pumpAndSettle();
    expect(r.controller.phase, PantaTradePhase.signed);
    await tester.tap(find.text('Fund existing call'));
    await tester.pumpAndSettle();
    await tapAction(tester, 'Retry same signed transaction');
    await tester.pumpAndSettle();
    expect(r.inputs('submit')[0], r.inputs('submit')[1]);
    expect(r.wallet.signCount, 1);
    expect(r.procedure('prepare'), hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'only manual server FILLED displays Funded; no background polls',
    (tester) async {
      await open(tester);
      await review(tester);
      await tapAction(tester, 'Approve in wallet');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 2));
      expect(r.procedure('order'), isEmpty);
      r.serverState = 'PARTIAL';
      await tapAction(tester, 'Check order status');
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('Partially filled'));
      expect(find.textContaining('Partially filled'), findsOneWidget);
      expect(find.textContaining('Funded'), findsNothing);
      r.serverState = 'FILLED';
      await tapAction(tester, 'Check order status');
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Funded · fill confirmed by the server.'));
      expect(
        find.text('Funded · fill confirmed by the server.'),
        findsOneWidget,
      );
      expect(r.wallet.signCount, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
