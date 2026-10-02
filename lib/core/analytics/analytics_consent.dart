/// The person's choice about product analytics: OFF until they switch it on
/// in Settings → Privacy & data.
///
/// Analytics today never leave the device (see [InMemoryAnalyticsSink]); this
/// switch decides whether events are recorded at all. When a destination is
/// chosen, it must sit behind this same switch, and the Privacy Policy must
/// name it first.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chumbucket/core/analytics/analytics_event.dart';
import 'package:chumbucket/core/analytics/analytics_sink.dart';

class AnalyticsConsent extends ChangeNotifier {
  AnalyticsConsent({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  /// The app-wide choice. Read synchronously by [ConsentGatedAnalyticsSink].
  static final AnalyticsConsent instance = AnalyticsConsent();

  static const String storageKey = 'analytics_consent_v1';

  final Future<SharedPreferences> Function() _prefs;
  bool _granted = false;
  bool _loaded = false;

  /// False until the person opts in, and false until the stored choice has
  /// been read: nothing is recorded on a guess.
  bool get granted => _granted;
  bool get loaded => _loaded;

  Future<void>? _loading;

  /// Reads the stored choice once. Safe to call from anywhere, any number of times.
  Future<void> ensureLoaded() => _loading ??= load();

  Future<void> load() async {
    try {
      final prefs = await _prefs();
      _granted = prefs.getBool(storageKey) ?? false;
    } catch (_) {
      _granted = false;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setGranted(bool value) async {
    _granted = value;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await _prefs();
      await prefs.setBool(storageKey, value);
    } catch (_) {
      // The in-memory choice still holds for this session.
    }
  }
}

/// Drops every event unless analytics consent has been given.
class ConsentGatedAnalyticsSink implements AnalyticsSink {
  ConsentGatedAnalyticsSink(this.inner, {bool Function()? allowed})
    : _allowed = allowed ?? (() => AnalyticsConsent.instance.granted);

  final AnalyticsSink inner;
  final bool Function() _allowed;

  @override
  void add(AnalyticsEvent event) {
    if (_allowed()) inner.add(event);
  }
}
