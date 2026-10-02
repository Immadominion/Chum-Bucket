/// Opt-in crash reporting (Firebase Crashlytics).
///
/// Nothing is sent until the person turns "Share crash reports" on in
/// Settings. The manifest sets `firebase_crashlytics_collection_enabled` to
/// false, so the native SDK uploads nothing from the very first launch, and
/// this class only ever flips it on after reading a stored, explicit yes. A
/// crash the SDK cached on the device before that yes is deleted, not sent
/// ([CrashReporting.setOptedIn]).
///
/// What a report carries: the error, its stack trace and Crashlytics' device
/// metadata. What it never carries: a user id, a wallet address, a handle or a
/// session. Nothing here calls `setUserIdentifier` or `setCustomKey`, and a
/// test pins that.
///
/// Debug builds never report, whatever the setting says: a developer's crash
/// is not a production signal.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where reports go. [FirebaseCrashSink] in the app; a recorder in tests.
abstract class CrashSink {
  /// False when the backend cannot be used at all (for example Firebase failed
  /// to initialise). Every other method is then a no-op.
  bool get isAvailable;

  Future<void> setCollectionEnabled(bool enabled);
  Future<void> deleteUnsentReports();
  Future<void> recordFlutterError(FlutterErrorDetails details);
  Future<void> recordError(Object error, StackTrace? stack, {bool fatal});
}

/// Firebase Crashlytics, guarded so a missing Firebase app is never a crash.
class FirebaseCrashSink implements CrashSink {
  const FirebaseCrashSink();

  @override
  bool get isAvailable => Firebase.apps.isNotEmpty;

  FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    if (!isAvailable) return;
    await _c.setCrashlyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> deleteUnsentReports() async {
    if (!isAvailable) return;
    await _c.deleteUnsentReports();
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    if (!isAvailable) return;
    await _c.recordFlutterFatalError(details);
  }

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    if (!isAvailable) return;
    await _c.recordError(error, stack, fatal: fatal);
  }
}

/// Where the person's answer is kept.
abstract class CrashConsentStore {
  /// Null when the person has never answered.
  Future<bool?> read();
  Future<void> write(bool value);
}

class PrefsCrashConsentStore implements CrashConsentStore {
  const PrefsCrashConsentStore();

  static const String key = 'crash_reports_opt_in_v1';

  @override
  Future<bool?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }

  @override
  Future<void> write(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

/// The app's crash-reporting switch and error hooks.
class CrashReporting extends ChangeNotifier {
  CrashReporting({
    CrashSink sink = const FirebaseCrashSink(),
    CrashConsentStore store = const PrefsCrashConsentStore(),
    bool reportingBuild = !kDebugMode,
  }) : _sink = sink,
       _store = store,
       _reportingBuild = reportingBuild;

  /// The app-wide instance, initialised from `main()`.
  static final CrashReporting instance = CrashReporting();

  final CrashSink _sink;
  final CrashConsentStore _store;
  final bool _reportingBuild;

  bool _optedIn = false;
  bool _initialized = false;
  bool _hooksInstalled = false;

  /// What the person chose. Off until they say yes.
  bool get optedIn => _optedIn;

  /// Whether reports are actually being sent right now.
  bool get collecting => _optedIn && _reportingBuild && _sink.isAvailable;

  /// Whether this build can send reports at all (false in debug builds and
  /// when Firebase did not start). The setting still saves either way.
  bool get canReport => _reportingBuild && _sink.isAvailable;

  /// Reads the stored answer, applies it, and installs the error hooks.
  /// Safe to call more than once. Never throws: crash reporting must not be
  /// the thing that stops the app from starting.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _optedIn = (await _store.read()) ?? false;
      await _apply();
    } catch (_) {
      _optedIn = false;
    }
    _installHooks();
    notifyListeners();
  }

  /// Records the person's answer and applies it immediately.
  ///
  /// While collection is off, the native SDK still writes a crash to disk
  /// (unsent), and enabling collection would upload that backlog. So both
  /// directions drop unsent reports: turning it on first, so only crashes
  /// after the person said yes are ever sent; turning it off after, so
  /// nothing captured under the old answer leaves the device.
  Future<void> setOptedIn(bool value) async {
    _optedIn = value;
    notifyListeners();
    await _store.write(value);
    if (value && _sink.isAvailable) {
      await _sink.deleteUnsentReports();
    }
    await _apply();
    if (!value && _sink.isAvailable) {
      await _sink.deleteUnsentReports();
    }
  }

  Future<void> _apply() => _sink.setCollectionEnabled(collecting);

  void _installHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;

    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previousFlutter != null) {
        previousFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
      if (collecting) unawaited(_sink.recordFlutterError(details));
    };

    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (collecting) {
        unawaited(_sink.recordError(error, stack, fatal: true));
      }
      // Observe only: whatever handled this before still decides.
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  /// Report a caught error that should still be investigated. A no-op unless
  /// the person opted in.
  Future<void> recordCaught(Object error, StackTrace? stack) async {
    if (!collecting) return;
    await _sink.recordError(error, stack, fatal: false);
  }
}
