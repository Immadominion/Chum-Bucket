import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';
import 'app_lifecycle_service.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (kDebugMode)
    debugPrint('Background message received: ${message.messageId}');
  await FcmTokenService._handleRemoteMessage(message, fromBackground: true);
}

/// Service for managing FCM tokens and push notifications
class FcmTokenService {
  FcmTokenService._();

  static bool _initialized = false;
  static String? _currentToken;

  /// Initialize FCM and set up message handlers
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Firebase should already be initialized in main.dart
      // Only initialize if not already done
      if (Firebase.apps.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'Warning: Firebase not initialized before FCM - this should be done in main.dart',
          );
        }
        return;
      }

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Request notification permission on iOS
      await _requestPermission();

      // Set up foreground message handler
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Set up message open handler (when user taps notification)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Check for initial message (app opened from terminated state via notification)
      final initialMessage =
          await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // Get initial token
      _currentToken = await FirebaseMessaging.instance.getToken();
      if (kDebugMode) debugPrint('FCM Token: $_currentToken');

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen(_onTokenRefresh);

      _initialized = true;
      if (kDebugMode) debugPrint('FCM initialized successfully');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Failed to initialize FCM: $e\n$stack');
    }
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

    if (kDebugMode)
      debugPrint('🔔 FCM Permission status: ${settings.authorizationStatus}');

    // Also request local notification permission for displaying notifications
    // when app is in foreground
    final localNotifGranted = await NotificationService.requestPermission();
    if (kDebugMode)
      debugPrint('🔔 Local notification permission: $localNotifGranted');

    return granted;
  }

  /// Get current FCM token
  static Future<String?> getToken() async {
    _currentToken ??= await FirebaseMessaging.instance.getToken();
    return _currentToken;
  }

  /// Register FCM token with Supabase for a wallet
  static Future<void> registerToken({
    required String walletAddress,
    String? displayName,
  }) async {
    final token = await getToken();
    if (token == null) {
      if (kDebugMode) debugPrint('No FCM token available to register');
      return;
    }

    try {
      final supabase = Supabase.instance.client;
      final platform = Platform.isIOS ? 'ios' : 'android';

      // Upsert the token - update if exists, insert if new
      await supabase.from('fcm_tokens').upsert({
        'wallet_address': walletAddress,
        'fcm_token': token,
        'platform': platform,
        if (displayName != null) 'user_display_name': displayName,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'wallet_address');

      if (kDebugMode) {
        debugPrint(
          'FCM token registered for wallet: ${walletAddress.substring(0, 8)}...',
        );
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('Failed to register FCM token: $e\n$stack');
    }
  }

  /// Unregister FCM token when user logs out
  static Future<void> unregisterToken(String walletAddress) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase
          .from('fcm_tokens')
          .delete()
          .eq('wallet_address', walletAddress);

      if (kDebugMode) {
        debugPrint(
          'FCM token unregistered for wallet: ${walletAddress.substring(0, 8)}...',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to unregister FCM token: $e');
    }
  }

  /// Handle token refresh
  static Future<void> _onTokenRefresh(String newToken) async {
    if (kDebugMode) debugPrint('FCM Token refreshed');
    _currentToken = newToken;
    // Note: Re-register will happen next time a wallet action is performed
  }

  /// Handle foreground messages - show local notification
  /// When app is in foreground, Android doesn't automatically display notifications
  /// so we need to display them manually using flutter_local_notifications
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      debugPrint('🔔 Foreground message received: ${message.messageId}');
      debugPrint('   notification: ${message.notification?.title}');
      debugPrint('   data: ${message.data}');
    }

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
  static void _handleMessageOpenedApp(RemoteMessage message) {
    if (kDebugMode) debugPrint('🔔 Message opened app: ${message.data}');

    // Trigger a data refresh since user opened app from notification
    AppLifecycleService.instance.forceRefresh();

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

  /// Send notification when challenge is created (call edge function)
  static Future<void> notifyChallengeCreated({
    required String challengeId,
    required String witnessWallet,
    required String initiatorName,
    required String challengeTitle,
    required double amountSol,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.functions.invoke(
        'send-challenge-notification',
        body: {
          'type': 'challenge_created',
          'challenge_id': challengeId,
          'witness_wallet': witnessWallet,
          'initiator_name': initiatorName,
          'challenge_title': challengeTitle,
          'amount_sol': amountSol,
        },
      );

      if (kDebugMode)
        debugPrint('Challenge notification sent for: $challengeId');
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to send challenge notification: $e');
      // Don't throw - notifications are best-effort
    }
  }

  /// Send notification when challenge is resolved (call edge function)
  static Future<void> notifyChallengeResolved({
    required String challengeId,
    required String initiatorWallet,
    required bool initiatorWon,
    double? winnerAmountSol,
  }) async {
    try {
      final supabase = Supabase.instance.client;

      await supabase.functions.invoke(
        'send-challenge-notification',
        body: {
          'type': 'challenge_resolved',
          'challenge_id': challengeId,
          'initiator_wallet': initiatorWallet,
          'initiator_won': initiatorWon,
          if (winnerAmountSol != null) 'winner_amount_sol': winnerAmountSol,
        },
      );

      if (kDebugMode)
        debugPrint('Resolution notification sent for: $challengeId');
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to send resolution notification: $e');
      // Don't throw - notifications are best-effort
    }
  }
}
