import 'dart:async';

import 'package:chumbucket/core/navigation/deep_link_host.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The delivery edge of the shared-link loop.
///
/// Parsing and routing are covered by calls_deep_link_test.dart without any
/// package. What is untested there — and what this file covers — is the part
/// that hands a live Uri to the router: cold start, warm resume, and the rule
/// that a link the call slice does not own is left alone for its existing
/// handler rather than swallowed.
void main() {
  late CallsProvider provider;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    provider = CallsProvider(
      repository: MockCallsRepository(latency: Duration.zero),
    );
    navigatorKey = GlobalKey<NavigatorState>();
  });

  /// Mirrors main.dart exactly: MultiProvider -> ScreenUtilInit -> MaterialApp
  /// with DeepLinkHost as the app builder. The nesting matters — the routed
  /// screens size themselves with flutter_screenutil, so a harness without
  /// ScreenUtilInit fails on a LateInitializationError that production never
  /// hits.
  Widget harness({Stream<Uri>? stream, Future<Uri?> Function()? initial}) {
    return ChangeNotifierProvider<CallsProvider>.value(
      value: provider,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder:
            (context, _) => MaterialApp(
              navigatorKey: navigatorKey,
              builder:
                  (context, child) => DeepLinkHost(
                    navigatorKey: navigatorKey,
                    linkStream: stream ?? const Stream<Uri>.empty(),
                    initialLink: initial ?? () async => null,
                    child: child ?? const SizedBox.shrink(),
                  ),
              home: const Scaffold(body: Text('home')),
            ),
      ),
    );
  }

  testWidgets('the app builds and shows home when no link arrives', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a link the call slice does not own is left alone', (
    tester,
  ) async {
    // The Supabase OAuth callback. It must keep reaching its existing handler,
    // so DeepLinkHost must not navigate and must not throw.
    final controller = StreamController<Uri>();
    addTearDown(controller.close);

    await tester.pumpWidget(harness(stream: controller.stream));
    await tester.pumpAndSettle();

    controller.add(Uri.parse('dev.cleva.chumbucket://login-callback'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrelated https link is left alone', (tester) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);

    await tester.pumpWidget(harness(stream: controller.stream));
    await tester.pumpAndSettle();

    controller.add(Uri.parse('https://example.com/c/whatever'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cold-start link is delivered after the first frame', (
    tester,
  ) async {
    final calls = await provider.repository.fetchFeed(mode: CallFeedMode.global);
    final callId = calls.entries.first.call.id;

    await tester.pumpWidget(
      harness(initial: () async => Uri.parse('chumbucket://call/$callId')),
    );
    await tester.pumpAndSettle();

    // It left home, which is the observable proof the link was routed.
    expect(find.text('home'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a warm-resume link is delivered from the stream', (
    tester,
  ) async {
    final feed = await provider.repository.fetchFeed(mode: CallFeedMode.global);
    final callId = feed.entries.first.call.id;

    final controller = StreamController<Uri>();
    addTearDown(controller.close);

    await tester.pumpWidget(harness(stream: controller.stream));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    controller.add(Uri.parse('chumbucket://call/$callId'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a malformed link does not crash the app', (tester) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);

    await tester.pumpWidget(harness(stream: controller.stream));
    await tester.pumpAndSettle();

    controller.add(Uri.parse('chumbucket://call/'));
    controller.add(Uri.parse('chumbucket://'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stream error does not take the app down', (tester) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);

    await tester.pumpWidget(harness(stream: controller.stream));
    await tester.pumpAndSettle();

    controller.addError(StateError('platform channel went away'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no CallsProvider in the tree drops the link instead of throwing', (
    tester,
  ) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (context, _) => MaterialApp(
              navigatorKey: navigatorKey,
              builder:
                  (context, child) => DeepLinkHost(
                    navigatorKey: navigatorKey,
                    linkStream: controller.stream,
                    initialLink: () async => null,
                    child: child ?? const SizedBox.shrink(),
                  ),
              home: const Scaffold(body: Text('home')),
            ),
      ),
    );
    await tester.pumpAndSettle();

    controller.add(Uri.parse('chumbucket://call/anything'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
