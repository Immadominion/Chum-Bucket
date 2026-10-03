/// When, and for whom, this device asks for and registers push notifications.
/// The one notification policy in the app (prod readiness M7, onboarding
/// spec §8); onboarding's "You're on record" card, the explain-first sheet
/// after a social action and Settings → Notifications all go through it.
///
/// * The OS prompt is never shown at startup. It is asked for in context —
///   right after a person's first call, Back/Fade/Dare or follow — behind an
///   explanation they can decline.
/// * Only when this server actually delivers pushes (`account.pushStatus`):
///   asking for something nobody sends would be a lie. Until then nothing is
///   asked and the app says the receipt shows up in Activity instead.
/// * Not again within two weeks of a "Not now" or a refusal, at most three
///   times in all, and never after the OS refused twice (Android then stops
///   showing its dialog; only Android Settings can turn them on, and the app
///   opens those only when the person taps).
/// * The device is registered for the signed-in Chumbucket ACCOUNT (wallet,
///   Google or X) through the BFF, so every sign-in kind gets pushes (M3), and
///   no client can register a token for someone else (B3).
library;

import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chumbucket/core/analytics/analytics.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';

/// The platform side, injectable so the flow is testable without Firebase.
abstract interface class PushPlatform {
  /// False when Firebase is not set up in this build: then nothing is asked.
  bool get available;
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> register(AccountApi api, {required String accountKey});
}

class FcmPushPlatform implements PushPlatform {
  const FcmPushPlatform();
  @override
  bool get available => Firebase.apps.isNotEmpty;
  @override
  Future<bool> hasPermission() => FcmTokenService.hasPermission();
  @override
  Future<bool> requestPermission() => FcmTokenService.requestPermission();
  @override
  Future<void> register(AccountApi api, {required String accountKey}) =>
      FcmTokenService.registerForAccount(api, accountKey: accountKey);
}

/// What a pre-prompt led to. [wire] is the analytics token.
enum PushAskResult {
  granted('granted'),
  denied('denied'),
  notNow('not_now'),
  permanentlyDenied('permanently_denied');

  const PushAskResult(this.wire);
  final String wire;
}

/// What an in-context ask may do right now.
enum PushAskState {
  /// No Firebase in this build, nobody signed in, or this server sends no
  /// pushes: ask nothing and promise nothing.
  unavailable,

  /// The OS already lets Chumbucket notify (always so on Android 12 and
  /// older); this device has been registered quietly.
  allowed,

  /// A pre-prompt may be shown.
  mayAsk,

  /// Pushes are live but the policy says not now (asked recently, asked three
  /// times, or refused for good).
  notNow,
}

/// Where Settings → Notifications stands.
enum PushSettingsState {
  /// This server sends no pushes (or nobody is signed in).
  unavailable,

  /// Allowed by the OS.
  on,

  /// Not allowed yet; a tap asks the OS.
  off,

  /// Refused for good: only Android Settings can turn them on now.
  blocked,
}

/// `chumbucket_notif_prompt_v1`: how often this phone has asked, and how it
/// went. Install-scoped, like the OS permission it tracks.
@immutable
class PushAskRecord {
  const PushAskRecord({
    this.asks = 0,
    this.denials = 0,
    this.lastAskAt,
    this.lastResult,
  });

  /// Pre-prompts shown (the sheet or the card).
  final int asks;

  /// OS refusals seen. Two means refused for good on Android.
  final int denials;
  final int? lastAskAt;
  final String? lastResult;

  bool get permanentlyDenied =>
      lastResult == PushAskResult.permanentlyDenied.wire ||
      denials >= PushRegistration.deniedForGood;

  PushAskRecord next(PushAskResult result, DateTime at) => PushAskRecord(
    asks: asks + 1,
    denials:
        result == PushAskResult.denied ||
                result == PushAskResult.permanentlyDenied
            ? denials + 1
            : denials,
    lastAskAt: at.toUtc().millisecondsSinceEpoch,
    lastResult: result.wire,
  );

  Map<String, Object?> toJson() => {
    'asks': asks,
    'denials': denials,
    'lastAskAt': lastAskAt,
    'lastResult': lastResult,
  };

  static PushAskRecord fromJson(Map<String, dynamic> json) {
    int? i(Object? v) => v is int ? v : null;
    final last = json['lastResult'];
    return PushAskRecord(
      asks: i(json['asks']) ?? 0,
      denials: i(json['denials']) ?? 0,
      lastAskAt: i(json['lastAskAt']),
      lastResult: last is String ? last : null,
    );
  }
}

/// Who to register for, read from the tree before any await.
typedef _Target = ({AccountApi api, String key});

class PushRegistration {
  PushRegistration._();

  /// Swapped by tests.
  static PushPlatform platform = const FcmPushPlatform();

  /// Opens this app's notification settings in Android. Only ever called from
  /// a tap. Swapped by tests.
  static Future<bool> Function() openSystemSettings = _openViaChannel;

  /// Swapped by tests.
  static DateTime Function() clock = DateTime.now;

  static const String recordKey = 'chumbucket_notif_prompt_v1';

  /// Written by the first in-context ask (before the record above existed);
  /// read as one earlier ask.
  static const String askedAtKey = 'push_permission_asked_at';
  static const Duration askAgainAfter = Duration(days: 14);
  static const int maxAsks = 3;
  static const int deniedForGood = 2;

  static bool _asking = false;

  static const _settingsChannel = MethodChannel(
    'dev.cleva.chumbucket/notifications',
  );

  static Future<bool> _openViaChannel() async {
    try {
      return await _settingsChannel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The policy alone: may a pre-prompt be shown, given [record], at [now]?
  static bool policyAllows(PushAskRecord record, DateTime now) {
    if (record.permanentlyDenied) return false;
    if (record.asks >= maxAsks) return false;
    final last = record.lastAskAt;
    if (last != null &&
        now.toUtc().millisecondsSinceEpoch - last <
            askAgainAfter.inMilliseconds) {
      return false;
    }
    return true;
  }

  static Future<PushAskRecord> readRecord() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(recordKey);
      if (raw != null) {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) return PushAskRecord.fromJson(json);
      }
      final askedAt = prefs.getInt(askedAtKey);
      if (askedAt != null) {
        return PushAskRecord(
          asks: 1,
          lastAskAt: askedAt,
          lastResult: PushAskResult.notNow.wire,
        );
      }
    } catch (_) {
      // Unreadable: as if never asked. The OS keeps its own count.
    }
    return const PushAskRecord();
  }

  static Future<void> _write(PushAskRecord record) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(recordKey, jsonEncode(record.toJson()));
    } catch (_) {}
  }

  static Future<PushAskRecord> _remember(PushAskResult result) async {
    final next = (await readRecord()).next(result, clock());
    await _write(next);
    return next;
  }

  static String? _accountKey(BuildContext context) {
    final session = Provider.of<ChumbucketSession?>(context, listen: false);
    if (session != null) return session.isReady ? session.userId : null;
    return Provider.of<AccountApi?>(context, listen: false) == null
        ? null
        : 'local';
  }

  static _Target? _target(BuildContext context) {
    final api = accountApiOf(context);
    final key = _accountKey(context);
    if (api == null || key == null) return null;
    return (api: api, key: key);
  }

  /// Whether this server delivers pushes. Any failure is "no": the app then
  /// asks nothing and says where the receipt shows up instead.
  static Future<bool> serverSendsPushes(AccountApi api) async {
    try {
      return await api.pushStatus();
    } catch (_) {
      return false;
    }
  }

  /// Where an in-context ask stands. Registers this device quietly when the
  /// OS already allows notifications.
  static Future<PushAskState> stateFor(BuildContext context) async {
    if (!platform.available) return PushAskState.unavailable;
    final target = _target(context);
    if (target == null) return PushAskState.unavailable;
    if (!await serverSendsPushes(target.api)) return PushAskState.unavailable;
    if (await platform.hasPermission()) {
      unawaited(_registerQuietly(target));
      return PushAskState.allowed;
    }
    return policyAllows(await readRecord(), clock())
        ? PushAskState.mayAsk
        : PushAskState.notNow;
  }

  static Future<void> _registerQuietly(_Target target) async {
    try {
      await platform.register(target.api, accountKey: target.key);
    } catch (_) {
      // Registration is tried again on the next resume (syncIfPermitted).
    }
  }

  /// "Notify me" on an in-context card: exactly one OS dialog, then this
  /// device is registered when allowed. Records how it went.
  static Future<PushAskResult> askNow(BuildContext context) async {
    final target = _target(context);
    final granted = await platform.requestPermission();
    var result = granted ? PushAskResult.granted : PushAskResult.denied;
    if (!granted && (await readRecord()).denials + 1 >= deniedForGood) {
      result = PushAskResult.permanentlyDenied;
    }
    await _remember(result);
    if (granted && target != null) await _registerQuietly(target);
    return result;
  }

  /// "Not now" on an in-context card.
  static Future<void> declined() => _remember(PushAskResult.notNow);

  /// Already allowed? Then make sure this device is registered for the
  /// signed-in account. Never prompts. Cheap to call on every resume.
  static Future<void> syncIfPermitted(BuildContext context) async {
    if (!platform.available) return;
    final target = _target(context);
    if (target == null) return;
    if (!await platform.hasPermission()) return;
    await platform.register(target.api, accountKey: target.key);
  }

  /// After a social action: explain why, then (on yes) show the OS prompt and
  /// register. Pass a context that outlives the sheet the action came from
  /// (the root navigator's).
  static Future<void> afterSocialAction(BuildContext context) async {
    if (_asking) return;
    _asking = true;
    try {
      final state = await stateFor(context);
      if (state != PushAskState.mayAsk || !context.mounted) return;
      AnalyticsRecorder.instance.record(
        OnboardingAnalyticsEvents.notificationPromptShown(
          trigger: 'social_action',
        ),
      );
      final yes = await showChumbucketWavySheet<bool>(
        context: context,
        builder: (_) => const PushRationaleSheet(),
      );
      if (yes != true || !context.mounted) {
        await declined();
        AnalyticsRecorder.instance.record(
          OnboardingAnalyticsEvents.notificationPermissionResult(
            result: PushAskResult.notNow.wire,
            stage: 'pre_prompt',
          ),
        );
        return;
      }
      final result = await askNow(context);
      AnalyticsRecorder.instance.record(
        OnboardingAnalyticsEvents.notificationPermissionResult(
          result: result.wire,
          stage: 'system',
        ),
      );
    } finally {
      _asking = false;
    }
  }

  /// Settings → Notifications.
  static Future<PushSettingsState> settingsState(BuildContext context) async {
    if (!platform.available) return PushSettingsState.unavailable;
    final target = _target(context);
    if (target == null) return PushSettingsState.unavailable;
    if (await platform.hasPermission()) return PushSettingsState.on;
    if (!await serverSendsPushes(target.api)) {
      return PushSettingsState.unavailable;
    }
    return (await readRecord()).permanentlyDenied
        ? PushSettingsState.blocked
        : PushSettingsState.off;
  }
}

/// The one screen that explains what a notification will be about before the
/// OS asks. Copy names the four things the server can send, and nothing else.
class PushRationaleSheet extends StatelessWidget {
  const PushRationaleSheet({super.key});

  @override
  Widget build(BuildContext context) => ChumbucketWavySheet(
    title: 'Know when it lands',
    subtitle: 'Only about your calls and the people you’ve faced.',
    body: const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Text(
        'We’ll tell you when someone backs or fades your call, when the market '
        'resolves, when someone wants a rematch, and when someone you faded '
        'makes a new call.',
        style: TextStyle(fontSize: 16, height: 1.45),
      ),
    ),
    footer: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChumbucketPrimaryButton(
            label: 'Turn on notifications',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 4),
          ChumbucketTextAction(
            label: 'Not now',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    ),
  );
}
