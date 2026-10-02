/// Keeps a secret off screenshots, screen recordings and the recents
/// thumbnail while it is on screen (Android `FLAG_SECURE`, set in
/// `MainActivity.kt`). Used while the on-phone wallet's recovery phrase or
/// private key is shown: a screenshot of either is the wallet.
///
/// Best effort: on iOS and in tests there is no handler and this does
/// nothing; it never fails the screen that asked.
library;

import 'package:flutter/services.dart';

class SecureWindow {
  const SecureWindow._();

  static const channel = MethodChannel('dev.cleva.chumbucket/secure_window');

  static Future<void> set(bool secure) async {
    try {
      await channel.invokeMethod<void>('set', {'secure': secure});
    } catch (_) {
      // No handler (iOS, tests) or the platform refused: nothing to undo.
    }
  }
}
