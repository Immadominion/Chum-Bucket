/// When the app may ask for notification permission (onboarding spec §8).
///
/// 1. Never at launch.
/// 2. Only after something worth hearing about: a locked call.
/// 3. Only when push is actually live — device tokens kept per account and a
///    sender that delivers on inbox insert. Asking for something nobody sends
///    would be a lie, so until the server says so, nothing is asked and the
///    copy points at Activity instead.
/// 4. Not when permission is already there, not after it was refused for good
///    (two denials on Android), at most three times, and not within 14 days
///    of a "Not now" or a denial.
///
/// On Android 12 and older permission is implicit: [canAsk] is false because
/// it is already granted.
library;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';

import 'package:chumbucket/core/services/notification_service.dart';

/// Whether the server delivers pushes for the calls inbox.
abstract interface class PushCapability {
  Future<bool> isPushLive();
}

/// Push is not live: nothing on the server sends one yet (onboarding spec §14
/// item 2). The honest default until the BFF reports a sender.
class PushNotLive implements PushCapability {
  const PushNotLive();
  @override
  Future<bool> isPushLive() async => false;
}

/// The OS side, injectable so tests never touch a plugin.
abstract interface class NotificationPermissionPlatform {
  /// Already allowed (always true on Android 12 and older).
  Future<bool> isGranted();

  /// Shows the OS dialog (Android 13+). True when allowed.
  Future<bool> request();

  /// Opens this app's notification settings. Never called on its own — only
  /// from a button the person pressed.
  Future<bool> openSettings();
}

class DeviceNotificationPermission implements NotificationPermissionPlatform {
  const DeviceNotificationPermission();

  static const _channel = MethodChannel('dev.cleva.chumbucket/notifications');

  @override
  Future<bool> isGranted() async {
    try {
      return await NotificationService.isAllowed();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> request() async {
    try {
      return await NotificationService.requestPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// `chumbucket_notif_prompt_v1`.
class NotificationPromptRecord {
  const NotificationPromptRecord({
    this.asks = 0,
    this.denials = 0,
    this.lastAskAt,
    this.lastResult,
  });

  /// Pre-prompts shown.
  final int asks;

  /// OS denials seen. Two means refused for good on Android.
  final int denials;
  final int? lastAskAt;

  /// `granted`, `denied`, `not_now` or `permanently_denied`.
  final String? lastResult;

  bool get permanentlyDenied => lastResult == 'permanently_denied';

  Map<String, Object?> toJson() => {
    'asks': asks,
    'denials': denials,
    'lastAskAt': lastAskAt,
    'lastResult': lastResult,
  };

  static NotificationPromptRecord fromJson(Map<String, dynamic> json) {
    int? i(Object? v) => v is int ? v : null;
    return NotificationPromptRecord(
      asks: i(json['asks']) ?? 0,
      denials: i(json['denials']) ?? 0,
      lastAskAt: i(json['lastAskAt']),
      lastResult:
          json['lastResult'] is String ? json['lastResult'] as String : null,
    );
  }
}

abstract interface class NotificationPromptStore {
  Future<NotificationPromptRecord> read();
  Future<void> write(NotificationPromptRecord record);
}

class PreferencesNotificationPromptStore implements NotificationPromptStore {
  const PreferencesNotificationPromptStore();

  static const key = 'chumbucket_notif_prompt_v1';

  @override
  Future<NotificationPromptRecord> read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      if (raw == null) return const NotificationPromptRecord();
      final json = jsonDecode(raw);
      return json is Map<String, dynamic>
          ? NotificationPromptRecord.fromJson(json)
          : const NotificationPromptRecord();
    } catch (_) {
      return const NotificationPromptRecord();
    }
  }

  @override
  Future<void> write(NotificationPromptRecord record) async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode(record.toJson()),
      );
    } catch (_) {}
  }
}

class MemoryNotificationPromptStore implements NotificationPromptStore {
  MemoryNotificationPromptStore([this.record = const NotificationPromptRecord()]);
  NotificationPromptRecord record;

  @override
  Future<NotificationPromptRecord> read() async => record;

  @override
  Future<void> write(NotificationPromptRecord value) async => record = value;
}

/// What a pre-prompt led to.
enum NotificationAskResult {
  granted('granted'),
  denied('denied'),
  notNow('not_now'),
  permanentlyDenied('permanently_denied');

  const NotificationAskResult(this.wire);
  final String wire;
}

/// Where Settings → Notifications stands.
enum NotificationSettingsState {
  /// Allowed by the OS.
  on,

  /// Not allowed yet, and the app may still ask in context.
  off,

  /// Refused for good: only Android Settings can turn them on now.
  blocked,
}

class NotificationPermissionCoordinator {
  NotificationPermissionCoordinator({
    this.push = const PushNotLive(),
    this.platform = const DeviceNotificationPermission(),
    NotificationPromptStore? store,
    DateTime Function()? clock,
  }) : _store = store ?? const PreferencesNotificationPromptStore(),
       _clock = clock ?? DateTime.now;

  final PushCapability push;
  final NotificationPermissionPlatform platform;
  final NotificationPromptStore _store;
  final DateTime Function() _clock;

  static const int maxAsks = 3;
  static const Duration askAgainAfter = Duration(days: 14);

  /// The policy alone, for tests: may a pre-prompt be shown given [record]?
  static bool policyAllows(NotificationPromptRecord record, DateTime now) {
    if (record.permanentlyDenied) return false;
    if (record.asks >= maxAsks) return false;
    final last = record.lastAskAt;
    if (last != null &&
        (record.lastResult == 'not_now' || record.lastResult == 'denied') &&
        now.toUtc().millisecondsSinceEpoch - last <
            askAgainAfter.inMilliseconds) {
      return false;
    }
    return true;
  }

  Future<bool> isPushLive() async {
    try {
      return await push.isPushLive();
    } catch (_) {
      return false;
    }
  }

  /// True when a pre-prompt may be shown now (§8.3).
  Future<bool> canAsk() async {
    if (!await isPushLive()) return false;
    if (await platform.isGranted()) return false;
    return policyAllows(await _store.read(), _clock());
  }

  /// The person said "Not now" on the pre-prompt.
  Future<void> recordNotNow() async {
    final record = await _store.read();
    await _store.write(
      NotificationPromptRecord(
        asks: record.asks + 1,
        denials: record.denials,
        lastAskAt: _clock().toUtc().millisecondsSinceEpoch,
        lastResult: NotificationAskResult.notNow.wire,
      ),
    );
  }

  /// The person said "Notify me": exactly one OS dialog.
  Future<NotificationAskResult> requestFromPrePrompt() async {
    final record = await _store.read();
    final granted = await platform.request();
    final denials = granted ? record.denials : record.denials + 1;
    final result =
        granted
            ? NotificationAskResult.granted
            : denials >= 2
            ? NotificationAskResult.permanentlyDenied
            : NotificationAskResult.denied;
    await _store.write(
      NotificationPromptRecord(
        asks: record.asks + 1,
        denials: denials,
        lastAskAt: _clock().toUtc().millisecondsSinceEpoch,
        lastResult: result.wire,
      ),
    );
    return result;
  }

  Future<NotificationSettingsState> settingsState() async {
    if (await platform.isGranted()) return NotificationSettingsState.on;
    final record = await _store.read();
    return record.permanentlyDenied
        ? NotificationSettingsState.blocked
        : NotificationSettingsState.off;
  }

  Future<bool> openSystemSettings() => platform.openSettings();
}
