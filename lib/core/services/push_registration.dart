/// When, and for whom, this device asks for and registers push notifications.
///
/// * The OS prompt is never shown at startup (prod readiness M7). It is asked
///   for in context — right after a person's first call, Back/Fade/Challenge
///   or follow — behind a one-screen explanation they can decline, and not
///   again for two weeks if they do.
/// * The device is registered for the signed-in Chumbucket ACCOUNT (wallet,
///   Google or X) through the BFF, so every sign-in kind gets pushes (M3), and
///   no client can register a token for someone else (B3).
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class PushRegistration {
  PushRegistration._();

  /// Swapped by tests.
  static PushPlatform platform = const FcmPushPlatform();

  static const String askedAtKey = 'push_permission_asked_at';
  static const Duration askAgainAfter = Duration(days: 14);

  static bool _asking = false;

  static String? _accountKey(BuildContext context) {
    final session = Provider.of<ChumbucketSession?>(context, listen: false);
    if (session != null) return session.isReady ? session.userId : null;
    return Provider.of<AccountApi?>(context, listen: false) == null
        ? null
        : 'local';
  }

  /// Already allowed? Then make sure this device is registered for the
  /// signed-in account. Never prompts. Cheap to call on every resume.
  static Future<void> syncIfPermitted(BuildContext context) async {
    if (!platform.available) return;
    final api = accountApiOf(context);
    final key = _accountKey(context);
    if (api == null || key == null) return;
    if (!await platform.hasPermission()) return;
    await platform.register(api, accountKey: key);
  }

  /// After a social action: explain why, then (on yes) show the OS prompt and
  /// register. Pass a context that outlives the sheet the action came from
  /// (the root navigator's).
  static Future<void> afterSocialAction(BuildContext context) async {
    if (_asking || !platform.available) return;
    final api = accountApiOf(context);
    final key = _accountKey(context);
    if (api == null || key == null) return;
    if (await platform.hasPermission()) {
      await platform.register(api, accountKey: key);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final askedAt = prefs.getInt(askedAtKey);
    final now = DateTime.now();
    if (askedAt != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(askedAt)) <
            askAgainAfter) {
      return;
    }
    if (!context.mounted) return;
    _asking = true;
    try {
      await prefs.setInt(askedAtKey, now.millisecondsSinceEpoch);
      if (!context.mounted) return;
      final yes = await showChumbucketWavySheet<bool>(
        context: context,
        builder: (_) => const PushRationaleSheet(),
      );
      if (yes != true) return;
      if (!await platform.requestPermission()) return;
      await platform.register(api, accountKey: key);
    } finally {
      _asking = false;
    }
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
