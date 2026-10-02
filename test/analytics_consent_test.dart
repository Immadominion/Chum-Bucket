// Product analytics are off until the person turns them on, and the choice
// survives a restart. The Telegram pings are gone from the app entirely.
import 'dart:io';

import 'package:chumbucket/core/analytics/analytics_consent.dart';
import 'package:chumbucket/core/analytics/analytics_event.dart';
import 'package:chumbucket/core/analytics/analytics_events.dart';
import 'package:chumbucket/core/analytics/analytics_recorder.dart';
import 'package:chumbucket/core/analytics/analytics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  AnalyticsEvent anEvent() => AnalyticsEvents.callOpened(
    callId: 'call-1',
    surface: AnalyticsSurface.values.first,
  );

  test('consent is off by default and nothing is recorded', () async {
    final consent = AnalyticsConsent();
    await consent.ensureLoaded();
    expect(consent.granted, isFalse);
    final memory = InMemoryAnalyticsSink();
    final sink = ConsentGatedAnalyticsSink(
      memory,
      allowed: () => consent.granted,
    );
    sink.add(anEvent());
    expect(memory.length, 0);
  });

  test(
    'turning it on records, turning it off stops, and the choice persists',
    () async {
      final consent = AnalyticsConsent();
      await consent.ensureLoaded();
      final memory = InMemoryAnalyticsSink();
      final sink = ConsentGatedAnalyticsSink(
        memory,
        allowed: () => consent.granted,
      );

      await consent.setGranted(true);
      sink.add(anEvent());
      expect(memory.length, 1);

      final reopened = AnalyticsConsent();
      await reopened.ensureLoaded();
      expect(reopened.granted, isTrue);

      await consent.setGranted(false);
      sink.add(anEvent());
      expect(memory.length, 1);
    },
  );

  test('the ambient recorder is consent-gated and still inspectable', () {
    AnalyticsRecorder.debugSetInstance(null);
    final recorder = AnalyticsRecorder.instance;
    expect(recorder.sink, isA<ConsentGatedAnalyticsSink>());
    expect(recorder.memory, isNotNull);
    AnalyticsRecorder.debugSetInstance(null);
  });

  test('nothing in the app calls the Telegram analytics function', () {
    final hits =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) {
              final text = f.readAsStringSync();
              return text.contains("invoke(\n        'analytics-telegram'") ||
                  text.contains("invoke('analytics-telegram'") ||
                  text.contains('AnalyticsService.track');
            })
            .map((f) => f.path)
            .toList();
    expect(hits, isEmpty);
    expect(
      File('lib/core/services/analytics_service.dart').existsSync(),
      isFalse,
    );
  });
}
