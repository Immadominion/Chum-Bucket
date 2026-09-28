import 'dart:async';

import 'package:chumbucket/core/services/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <String>[];
  Completer<void>? heldShow;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    heldShow = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'show') await heldShow?.future;
          return true;
        });
    await NotificationService.initialize();
    await NotificationService.resumeForAccount(isCurrent: () => true);
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'logout cancels an in-flight show, then rejects late deliveries',
    () async {
      heldShow = Completer<void>();
      final showing = NotificationService.showGenericNotification(
        title: 'Synthetic notification',
        body: 'Test only',
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['show']);
      final exiting = NotificationService.pauseForSignOut();
      final late = NotificationService.notifyChallengeLost();
      heldShow!.complete();
      await Future.wait([showing, exiting, late]);
      expect(calls, ['show', 'cancelAll']);
      expect(await NotificationService.canHandleNotification(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('chumbucket_notifications_signed_out'), isTrue);
    },
  );

  test(
    'old registration cannot reopen delivery; a current account can',
    () async {
      await NotificationService.pauseForSignOut();
      await NotificationService.resumeForAccount(isCurrent: () => false);
      expect(await NotificationService.canHandleNotification(), isFalse);
      await NotificationService.resumeForAccount(isCurrent: () => true);
      expect(await NotificationService.canHandleNotification(), isTrue);
      await NotificationService.notifyChallengeReceived(
        challengerName: 'Fixture',
        challengeTitle: 'Fixture',
      );
      expect(calls, ['cancelAll', 'show']);
    },
  );

  test(
    'persisted logout marker also suppresses another isolate delivery',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('chumbucket_notifications_signed_out', true);
      // The in-memory gate is still open, as it would be in a fresh isolate.
      await NotificationService.notifyChallengeWon(winnerAmountSol: 1);
      expect(await NotificationService.canHandleNotification(), isFalse);
      expect(calls, isEmpty);
    },
  );
}
