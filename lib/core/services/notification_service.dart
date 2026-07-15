import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:chumbucket/core/services/app_lifecycle_service.dart';

/// Notification channels for different notification types
class NotificationChannels {
  static const String challenges = 'challenge_channel';
  static const String general = 'general_channel';
}

/// Service for managing local and push notifications for Chumbucket
class NotificationService {
  NotificationService._();

  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_initialized) return;

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels (Android only)
    await _createNotificationChannels();

    _initialized = true;
    if (kDebugMode) debugPrint('NotificationService initialized');
  }

  /// Create notification channels for Android
  static Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidPlugin != null) {
      // Challenge notifications channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationChannels.challenges,
          'Challenges',
          description: 'Notifications for challenge events',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );

      // General notifications channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationChannels.general,
          'General',
          description: 'General app notifications',
          importance: Importance.defaultImportance,
        ),
      );
    }
  }

  /// Check if notifications are allowed
  static Future<bool> isAllowed() async {
    final androidPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidPlugin != null) {
      final granted = await androidPlugin.areNotificationsEnabled();
      return granted ?? false;
    }

    // iOS: check permission status
    final iosPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

    if (iosPlugin != null) {
      // For iOS, we'll assume allowed if initialized
      return true;
    }

    return false;
  }

  /// Request notification permission
  static Future<bool> requestPermission() async {
    // Android 13+ requires explicit permission
    final androidPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? false;
    }

    // iOS
    final iosPlugin =
        _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return false;
  }

  /// Show permission request dialog with rationale
  static Future<bool> requestPermissionWithRationale(
    BuildContext context,
  ) async {
    final isAllowed = await NotificationService.isAllowed();
    if (isAllowed) return true;

    // Show a dialog explaining why we need notifications
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Enable Notifications',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Get notified when friends challenge you or when your challenges are resolved.',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'Not Now',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                ),
                child: const Text(
                  'Enable',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
    );

    if (shouldRequest == true) {
      return await requestPermission();
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // Challenge Notifications
  // ─────────────────────────────────────────────────────────────

  /// Notify when user is challenged by someone
  static Future<void> notifyChallengeReceived({
    required String challengerName,
    required String challengeTitle,
    double? amountSol,
    String? challengeId,
  }) async {
    final amountStr =
        amountSol != null ? '${amountSol.toStringAsFixed(2)} SOL' : 'SOL';

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      '$challengerName challenged you! 🎯',
      '"$challengeTitle" - $amountStr at stake',
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.challenges,
          'Challenges',
          channelDescription: 'Challenge notifications',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'New challenge',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'challenge_received:$challengeId',
    );
  }

  /// Notify when challenge is resolved (won)
  static Future<void> notifyChallengeWon({
    required double winnerAmountSol,
    String? challengeId,
  }) async {
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Challenge Won! 🎉',
      'Congratulations! You won ${winnerAmountSol.toStringAsFixed(2)} SOL!',
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.challenges,
          'Challenges',
          channelDescription: 'Challenge notifications',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'Challenge won',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'challenge_won:$challengeId',
    );
  }

  /// Notify when challenge is resolved (lost)
  static Future<void> notifyChallengeLost({String? challengeId}) async {
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Challenge Lost 😔',
      'Better luck next time. The witness judged against you.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.challenges,
          'Challenges',
          channelDescription: 'Challenge notifications',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'Challenge lost',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'challenge_lost:$challengeId',
    );
  }

  /// Show generic notification
  static Future<void> showGenericNotification({
    required String title,
    required String body,
    String? payload,
    bool highPriority = true,
  }) async {
    // Use challenge channel for high priority (FCM notifications)
    final channel =
        highPriority
            ? NotificationChannels.challenges
            : NotificationChannels.general;
    final importance =
        highPriority ? Importance.high : Importance.defaultImportance;
    final priority = highPriority ? Priority.high : Priority.defaultPriority;

    if (kDebugMode) debugPrint('📲 Showing local notification: $title');

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          highPriority ? 'Challenges' : 'General',
          channelDescription:
              highPriority
                  ? 'Challenge notifications'
                  : 'General notifications',
          importance: importance,
          priority: priority,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Notification Handlers (callbacks)
  // ─────────────────────────────────────────────────────────────

  static void _onNotificationTapped(NotificationResponse response) {
    if (kDebugMode) debugPrint('🔔 Notification tapped: ${response.payload}');

    // Trigger data refresh when notification is tapped
    AppLifecycleService.instance.forceRefresh();

    // Handle notification tap - can navigate to specific challenge
    final payload = response.payload;
    if (payload == null) return;

    final parts = payload.split(':');
    if (parts.length < 2) return;

    final type = parts[0];
    final challengeId = parts[1];

    switch (type) {
      case 'challenge_received':
      case 'challenge_won':
      case 'challenge_lost':
        // Navigate to challenge using lifecycle service
        if (challengeId.isNotEmpty) {
          AppLifecycleService.navigateToChallenge(challengeId);
        }
        break;
    }
  }
}
