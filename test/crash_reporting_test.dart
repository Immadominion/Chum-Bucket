import 'dart:io';
import 'dart:ui' show ErrorCallback;

import 'package:chumbucket/core/crash/crash_reporting.dart';
import 'package:chumbucket/core/crash/crash_reports_setting_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sink implements CrashSink {
  _Sink({this.isAvailable = true});

  @override
  bool isAvailable;
  final List<bool> collection = [];
  int deletes = 0;
  final List<Object> errors = [];
  final List<FlutterErrorDetails> flutterErrors = [];

  @override
  Future<void> setCollectionEnabled(bool enabled) async =>
      collection.add(enabled);

  @override
  Future<void> deleteUnsentReports() async => deletes++;

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details) async =>
      flutterErrors.add(details);

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async => errors.add(error);
}

class _Store implements CrashConsentStore {
  _Store([this.value]);
  bool? value;
  @override
  Future<bool?> read() async => value;
  @override
  Future<void> write(bool v) async => value = v;
}

void main() {
  late FlutterExceptionHandler? savedFlutter;
  late ErrorCallback? savedPlatform;

  setUp(() {
    savedFlutter = FlutterError.onError;
    savedPlatform = PlatformDispatcher.instance.onError;
  });
  tearDown(() {
    FlutterError.onError = savedFlutter;
    PlatformDispatcher.instance.onError = savedPlatform;
  });

  group('consent', () {
    test('off by default: a person who never answered sends nothing', () async {
      final sink = _Sink();
      final r = CrashReporting(sink: sink, store: _Store(), reportingBuild: true);
      await r.initialize();
      expect(r.optedIn, isFalse);
      expect(r.collecting, isFalse);
      expect(sink.collection, [false]);

      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('boom')),
      );
      expect(sink.flutterErrors, isEmpty);
    });

    test('a stored yes turns collection on at start', () async {
      final sink = _Sink();
      final r = CrashReporting(
        sink: sink,
        store: _Store(true),
        reportingBuild: true,
      );
      await r.initialize();
      expect(r.collecting, isTrue);
      expect(sink.collection, [true]);
    });

    test('opting in records errors; opting out stops and deletes', () async {
      final sink = _Sink();
      final store = _Store();
      final r = CrashReporting(sink: sink, store: store, reportingBuild: true);
      await r.initialize();

      await r.setOptedIn(true);
      expect(store.value, isTrue);
      expect(sink.collection.last, isTrue);
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('a')));
      await Future<void>.delayed(Duration.zero);
      expect(sink.flutterErrors, hasLength(1));
      await r.recordCaught(StateError('caught'), StackTrace.current);
      expect(sink.errors, hasLength(1));

      await r.setOptedIn(false);
      expect(store.value, isFalse);
      expect(sink.collection.last, isFalse);
      expect(sink.deletes, 1);
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('b')));
      await r.recordCaught(StateError('later'), null);
      expect(sink.flutterErrors, hasLength(1));
      expect(sink.errors, hasLength(1));
    });

    test('a debug build never collects, even after a yes', () async {
      final sink = _Sink();
      final r = CrashReporting(
        sink: sink,
        store: _Store(true),
        reportingBuild: false,
      );
      await r.initialize();
      expect(r.optedIn, isTrue);
      expect(r.collecting, isFalse);
      expect(r.canReport, isFalse);
      expect(sink.collection, [false]);
    });

    test('no Firebase is not a crash and not a report', () async {
      final sink = _Sink(isAvailable: false);
      final r = CrashReporting(
        sink: sink,
        store: _Store(true),
        reportingBuild: true,
      );
      await r.initialize();
      expect(r.collecting, isFalse);
    });
  });

  group('hooks', () {
    test('the previous Flutter error handler still runs', () async {
      var previousCalls = 0;
      FlutterError.onError = (_) => previousCalls++;
      final r = CrashReporting(
        sink: _Sink(),
        store: _Store(true),
        reportingBuild: true,
      );
      await r.initialize();
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
      expect(previousCalls, 1);
    });

    test('platform errors are observed, not swallowed', () async {
      final sink = _Sink();
      PlatformDispatcher.instance.onError = null;
      final r = CrashReporting(
        sink: sink,
        store: _Store(true),
        reportingBuild: true,
      );
      await r.initialize();
      final handled = PlatformDispatcher.instance.onError!(
        StateError('async'),
        StackTrace.current,
      );
      expect(handled, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(sink.errors, hasLength(1));
    });
  });

  test('no identity is ever attached to a report', () {
    final source = File('lib/core/crash/crash_reporting.dart').readAsStringSync();
    expect(source, isNot(contains('setUserIdentifier(')));
    expect(source, isNot(contains('setCustomKey(')));
  });

  testWidgets('the settings switch reflects and changes the choice', (
    tester,
  ) async {
    final sink = _Sink();
    final store = _Store();
    final r = CrashReporting(sink: sink, store: store, reportingBuild: true);
    await r.initialize();

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, _) => MaterialApp(
              home: Scaffold(body: CrashReportsSettingTile(reporting: r)),
            ),
      ),
    );
    expect(find.text('Share crash reports'), findsOneWidget);
    expect(
      find.text('Off. Nothing is sent unless you turn this on.'),
      findsOneWidget,
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.value, isTrue);
    expect(r.collecting, isTrue);
    expect(find.textContaining('No name or wallet is attached'), findsOneWidget);
  });
}
