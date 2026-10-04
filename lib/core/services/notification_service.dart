import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:chumbucket/core/services/app_lifecycle_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Notification channels for different notification types
class NotificationChannels {
  /// Calls, responses, follows and receipts. Also the FCM default channel
  /// (`default_notification_channel_id` in AndroidManifest.xml) — keep equal.
  static const String activity = 'activity_channel';

  /// The high-priority channel under its older name; same id as [activity].
  static const String challenges = activity;

  static const String general = 'general_channel';

  /// The pre-calls id. Deleted on start so a stale "Challenges" entry stops
  /// showing in system settings. A push still naming it falls back to the
  /// manifest default, which is [activity].
  static const String legacyChallenges = 'challenge_channel';

  /// User-visible name and description of [activity].
  static const String activityName = 'Calls and activity';
  static const String activityDescription =
      'Backs, fades, challenges, follows and resolved receipts';
}

/// Service for managing local and push notifications for Chumbucket
class NotificationService {
  NotificationService._();

  static bool _initialized = false;
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static const _signedOutKey = 'chumbucket_notifications_signed_out';
  static bool _deliveryPaused = false;
  static int _deliveryEpoch = 0;
  static Future<void> _deliveries = Future.value();

  static Future<void> _enqueue(Future<void> Function() operation) {
    final pending = _deliveries.then((_) => operation());
    _deliveries = pending.catchError((Object _) {});
    return pending;
  }

  /// Reload the persisted marker: background messaging runs in another isolate.
  /// OS-rendered push payloads still require token invalidation/server controls.
  static Future<bool> canHandleNotification() async {
    final epoch = _deliveryEpoch;
    if (_deliveryPaused) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return !_deliveryPaused &&
          epoch == _deliveryEpoch &&
          prefs.getBool(_signedOutKey) != true;
    } catch (_) {
      return false;
    }
  }

  /// Wait behind an in-flight show, then remove it and suppress late deliveries.
  static Future<void> pauseForSignOut() {
    _deliveryPaused = true;
    _deliveryEpoch++;
    return _enqueue(() async {
      await Future.wait([
        () async {
          final prefs = await SharedPreferences.getInstance();
          if (!await prefs.setBool(_signedOutKey, true)) {
            throw StateError('Notification session removal failed');
          }
        }(),
        _notifications.cancelAll(),
      ]);
    });
  }

  /// Only a successfully registered, still-current wallet can resume delivery.
  static Future<void> resumeForAccount({required bool Function() isCurrent}) =>
      _enqueue(() async {
        if (!isCurrent()) return;
        final prefs = await SharedPreferences.getInstance();
        if (!isCurrent()) return;
        if (!await prefs.setBool(_signedOutKey, false)) {
          throw StateError('Notification session storage failed');
        }
        if (isCurrent()) {
          _deliveryEpoch++;
          _deliveryPaused = false;
        }
      });

  static Future<void> _show(
    int id,
    String title,
    String body,
    NotificationDetails details, {
    String? payload,
  }) {
    final epoch = _deliveryEpoch;
    return _enqueue(() async {
      if (!await canHandleNotification() || epoch != _deliveryEpoch) return;
      await _notifications.show(id, title, body, details, payload: payload);
    });
  }

  /// Initialize the notification service
  static Future<void> initialize() async {
    if (_initialized) return;

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
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
      try {
        await androidPlugin.deleteNotificationChannel(
          NotificationChannels.legacyChallenges,
        );
      } catch (_) {
        // Absent on a fresh install; nothing to clean up.
      }

      // Calls and activity channel (the FCM default)
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          NotificationChannels.activity,
          NotificationChannels.activityName,
          description: NotificationChannels.activityDescription,
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
    if (!context.mounted) return false;

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

  /// Notify when user is challenged by someone. Says nothing about money:
  /// the push carries no amount, and no new challenge stakes anything.
  static Future<void> notifyChallengeReceived({
    required String challengerName,
    required String challengeTitle,
    String? challengeId,
  }) async {
    await _show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      '$challengerName challenged you! 🎯',
      '"$challengeTitle" · tap to see it',
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.activity,
          NotificationChannels.activityName,
          channelDescription: NotificationChannels.activityDescription,
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
    await _show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Challenge Won! 🎉',
      'Congratulations! You won ${winnerAmountSol.toStringAsFixed(2)} SOL!',
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.activity,
          NotificationChannels.activityName,
          channelDescription: NotificationChannels.activityDescription,
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
    await _show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Challenge Lost 😔',
      'Better luck next time. The witness judged against you.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannels.activity,
          NotificationChannels.activityName,
          channelDescription: NotificationChannels.activityDescription,
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
    // The activity channel for high priority (FCM notifications)
    final channel =
        highPriority
            ? NotificationChannels.activity
            : NotificationChannels.general;
    final importance =
        highPriority ? Importance.high : Importance.defaultImportance;
    final priority = highPriority ? Priority.high : Priority.defaultPriority;

    await _show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel,
          highPriority ? NotificationChannels.activityName : 'General',
          channelDescription:
              highPriority
                  ? NotificationChannels.activityDescription
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

  static Future<void> _onNotificationTapped(
    NotificationResponse response,
  ) async {
    if (!await canHandleNotification()) return;

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
