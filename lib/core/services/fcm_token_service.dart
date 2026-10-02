import 'dart:io';

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'notification_service.dart';
import 'app_lifecycle_service.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode) {
    debugPrint('Background message received: ${message.messageId}');
  }
  await FcmTokenService._handleRemoteMessage(message, fromBackground: true);
}

/// Service for managing FCM tokens and push notifications
class FcmTokenService {
  FcmTokenService._();

  static bool _initialized = false;
  static String? _currentToken;
  static int _accountEpoch = 0;

  /// Set up message handlers. Asks for NOTHING and fetches no token: the
  /// permission prompt belongs in context, after a person's first call or
  /// follow (`PushRegistration.afterSocialAction`), not on a splash screen
  /// before any UI (prod readiness M7). The token is fetched when a signed-in
  /// account registers this device.
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (Firebase.apps.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'Warning: Firebase not initialized before FCM - this should be done in main.dart',
          );
        }
        return;
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // App opened from terminated state via a notification.
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        unawaited(_handleMessageOpenedApp(initialMessage));
      }

      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);

      _initialized = true;
      if (kDebugMode) debugPrint('FCM initialized successfully');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Failed to initialize FCM: $e\n$stack');
    }
  }

  /// Whether the OS already lets this app post notifications. Never prompts.
  static Future<bool> hasPermission() async {
    if (Firebase.apps.isEmpty) return false;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  /// Show the OS prompt. Call only after the person has said yes in context.
  static Future<bool> requestPermission() async {
    if (Firebase.apps.isEmpty) return false;
    return _requestPermission();
  }

  /// Request notification permission
  static Future<bool> _requestPermission() async {
    final messaging = FirebaseMessaging.instance;

    // Request FCM permission (iOS + Android 13+)
    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (kDebugMode) {
      debugPrint('🔔 FCM Permission status: ${settings.authorizationStatus}');
    }

    // Also request local notification permission for displaying notifications
    // when app is in foreground
    final localNotifGranted = await NotificationService.requestPermission();
    if (kDebugMode) {
      debugPrint('🔔 Local notification permission: $localNotifGranted');
    }

    return granted;
  }

  /// Get current FCM token
  static Future<String?> getToken() async {
    final epoch = _accountEpoch;
    final token = _currentToken ?? await FirebaseMessaging.instance.getToken();
    if (epoch != _accountEpoch) return null;
    _currentToken = token;
    return _currentToken;
  }

  /// Invalidate this device's token, not every device belonging to a wallet.
  /// Throw on failure so logout can remain locked and offer a retry.
  ///
  /// `deleteToken` is the guarantee: FCM stops accepting the old token, so the
  /// server's next send to it answers UNREGISTERED and it is forgotten there.
  /// The BFF unregister is a courtesy and never blocks sign-out.
  static Future<void> clearForSignOut() async {
    _accountEpoch++;
    final token = _currentToken;
    final api = _registrar;
    _registrar = null;
    _registrarKey = null;
    _registeredFor = null;
    _currentToken = null;
    if (api != null && token != null) {
      try {
        await api
            .unregisterPushToken(token)
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        // Signed out already, or offline: deleteToken below still holds.
      }
    }
    await Future.wait([
      NotificationService.pauseForSignOut(),
      if (Firebase.apps.isNotEmpty) FirebaseMessaging.instance.deleteToken(),
    ]);
  }

  static AccountApi? _registrar;
  static String? _registrarKey;
  static String? _registeredFor;

  /// Register this device for the signed-in Chumbucket account (wallet, Google
  /// or X) through the BFF, keyed by the session — never by a wallet string,
  /// and never through the anon client (prod readiness B3/M3). Idempotent per
  /// (account, token). Best effort: a failure is retried next time.
  static Future<void> registerForAccount(
    AccountApi api, {
    required String accountKey,
  }) async {
    if (Firebase.apps.isEmpty) return;
    final epoch = _accountEpoch;
    final String? token;
    try {
      token = await getToken();
    } catch (_) {
      return;
    }
    if (epoch != _accountEpoch || token == null) return;
    _registrar = api;
    _registrarKey = accountKey;
    final key = '$accountKey|$token';
    if (_registeredFor == key) return;
    try {
      await api.registerPushToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      if (epoch != _accountEpoch) return;
      _registeredFor = key;
      await NotificationService.resumeForAccount(
        isCurrent: () => epoch == _accountEpoch,
      );
      if (kDebugMode) debugPrint('Push: this device is registered');
    } catch (e) {
      if (kDebugMode) debugPrint('Push: registration failed (${e.runtimeType})');
    }
  }

  /// Called when a call notification arrives in the foreground (the shell
  /// refreshes the unread badge).
  static VoidCallback? onCallNotification;

  /// Opens a call when a push is tapped. Set by the navigation shell
  /// (`DeepLinkHost`); a tap that arrives first is held until it is.
  static Future<void> Function(String callId)? _onOpenCall;
  static String? _pendingCallId;
  static set onOpenCall(Future<void> Function(String callId)? open) {
    _onOpenCall = open;
    final pending = _pendingCallId;
    if (open != null && pending != null) {
      _pendingCallId = null;
      unawaited(open(pending));
    }
  }

  /// A rotated token is registered again for the same account at once.
  static Future<void> _onTokenRefresh(String newToken) async {
    final epoch = _accountEpoch;
    if (!await NotificationService.canHandleNotification() ||
        epoch != _accountEpoch) {
      return;
    }
    _currentToken = newToken;
    final api = _registrar;
    final key = _registrarKey;
    if (api != null && key != null) {
      _registeredFor = null;
      await registerForAccount(api, accountKey: key);
    }
  }

  /// Handle foreground messages - show local notification
  /// When app is in foreground, Android doesn't automatically display notifications
  /// so we need to display them manually using flutter_local_notifications
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // A call notification arriving while the app is open moves the badge now.
    if (message.data['type'] == 'call_notification') onCallNotification?.call();
    // When in foreground with a notification payload, we need to show it manually
    // because Android doesn't auto-display notifications when app is in foreground
    final notification = message.notification;
    if (notification != null) {
      await NotificationService.showGenericNotification(
        title: notification.title ?? 'Chumbucket',
        body: notification.body ?? '',
      );
    } else {
      // Fall back to handling data-only messages
      await _handleRemoteMessage(message, fromBackground: false);
    }
  }

  /// Handle when user taps on a notification
  static Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    if (!await NotificationService.canHandleNotification()) return;

    // Trigger a data refresh since user opened app from notification
    AppLifecycleService.instance.forceRefresh();

    // A call notification (backed, faded, resolved, rematch) opens its call.
    final callId = message.data['call_id'];
    if (message.data['type'] == 'call_notification' &&
        callId is String &&
        callId.isNotEmpty) {
      final open = _onOpenCall;
      if (open != null) {
        await open(callId);
      } else {
        _pendingCallId = callId;
      }
      return;
    }

    // Navigate to challenge if ID is provided
    final challengeId = message.data['challenge_id'];
    if (challengeId != null && challengeId.isNotEmpty) {
      AppLifecycleService.navigateToChallenge(challengeId);
    }
  }

  /// Process remote message and show notification
  static Future<void> _handleRemoteMessage(
    RemoteMessage message, {
    required bool fromBackground,
  }) async {
    final data = message.data;

    // Data-only messages from our edge function
    final type = data['type'];
    final title = data['title'];
    final body = data['body'];

    // Skip if no actionable data
    if (title == null || body == null) {
      // Check for legacy notification payload
      if (message.notification != null) {
        await NotificationService.showGenericNotification(
          title: message.notification!.title ?? 'Chumbucket',
          body: message.notification!.body ?? '',
        );
      }
      return;
    }

    switch (type) {
      case 'challenge_created':
        final initiatorName = data['initiator_name'] ?? 'Someone';
        await NotificationService.notifyChallengeReceived(
          challengerName: initiatorName,
          challengeTitle: 'New Challenge',
          challengeId: data['challenge_id'],
        );
        break;

      case 'challenge_resolved':
        final result = data['result'];
        if (result == 'win') {
          await NotificationService.notifyChallengeWon(
            winnerAmountSol: double.tryParse(data['winner_amount'] ?? '0') ?? 0,
            challengeId: data['challenge_id'],
          );
        } else {
          await NotificationService.notifyChallengeLost(
            challengeId: data['challenge_id'],
          );
        }
        break;

      default:
        // Generic notification
        await NotificationService.showGenericNotification(
          title: title,
          body: body,
        );
    }
  }

  // There is deliberately no client-side "send a push to that wallet" any
  // more. `send-challenge-notification` was invoked from the app with an
  // arbitrary target wallet (prod readiness B3); pushes are now sent only by
  // the BFF, for notifications it derived itself.
}
