import 'dart:async';

import 'package:chumbucket/core/services/notification_service.dart';
import 'package:chumbucket/features/challenges/presentation/screens/widgets/receipt_action_buttons.dart';
import 'package:chumbucket/features/challenges/presentation/screens/widgets/receipt_modal.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/screens/splash/mwa_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screenshot/screenshot.dart';

class _HeldScreenshot extends ScreenshotController {
  final result = Completer<Uint8List?>();

  @override
  Future<Uint8List?> capture({
    double? pixelRatio,
    Duration delay = const Duration(milliseconds: 20),
  }) => result.future;
}

Widget _host(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, __) => MaterialApp(home: child),
);

void main() {
  for (var stage = 0; stage < 3; stage++) {
    testWidgets('splash disposal during delay $stage stops the sequence', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          MwaSplashScreen(
            peopleFirst: false,
            minimumDuration: const Duration(seconds: 30),
            deepLinkPending: () async => false,
          ),
        ),
      );
      if (stage >= 1) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1500));
      }
      if (stage >= 2) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));

      // No setState, animation start, provider lookup, or navigation after
      // removal. No authentication/network providers are needed in this test.
      expect(tester.takeException(), isNull);
    });
  }

  for (final pdf in [false, true]) {
    testWidgets(
      'receipt ${pdf ? 'PDF' : 'image'} failure after close is safe',
      (tester) async {
        final screenshot = _HeldScreenshot();
        await tester.pumpWidget(
          _host(
            Scaffold(
              body: ReceiptModal(
                challenge: null,
                status: ChallengeStatus.pending,
                screenshotController: screenshot,
              ),
            ),
          ),
        );
        final actions = tester.widget<ReceiptActionButtons>(
          find.byType(ReceiptActionButtons),
        );
        (pdf ? actions.onSharePDF : actions.onShareImage)();
        await tester.pumpWidget(const SizedBox.shrink());
        screenshot.result.completeError(
          StateError('Synthetic capture failure'),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );
  }

  group('notification rationale', () {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late Completer<bool> enabled;
    late List<String> methods;

    setUp(() {
      methods = [];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        if (call.method == 'areNotificationsEnabled') return enabled.future;
        throw StateError('Unexpected platform request: ${call.method}');
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    testWidgets('does not open a dialog after its screen is removed', (
      tester,
    ) async {
      enabled = Completer<bool>();
      late BuildContext screenContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              screenContext = context;
              return const Scaffold();
            },
          ),
        ),
      );

      final result = NotificationService.requestPermissionWithRationale(
        screenContext,
      );
      bool? completed;
      unawaited(result.then((value) => completed = value));
      await tester.pumpWidget(const SizedBox.shrink());
      enabled.complete(false);
      await tester.pump();

      expect(completed, isFalse);
      expect(methods, ['areNotificationsEnabled']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('still shows rationale and respects Not Now while mounted', (
      tester,
    ) async {
      enabled = Completer<bool>();
      late BuildContext screenContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              screenContext = context;
              return const Scaffold();
            },
          ),
        ),
      );

      final result = NotificationService.requestPermissionWithRationale(
        screenContext,
      );
      bool? completed;
      unawaited(result.then((value) => completed = value));
      enabled.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Enable Notifications'), findsOneWidget);
      await tester.tap(find.text('Not Now'));
      await tester.pumpAndSettle();

      expect(completed, isFalse);
      expect(methods, ['areNotificationsEnabled']);
      expect(tester.takeException(), isNull);
    });
  });
}
