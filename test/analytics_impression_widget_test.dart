/// `feed_call_impression` in a real widget tree: it must survive a rebuild and
/// a scroll away-and-back without counting twice.
///
/// These are the two ways a feed actually over-counts. A `Consumer` rebuild
/// happens on every provider notification — a page load, a refresh, a response
/// being submitted — and a `ListView` disposes and recreates the `State` of any
/// row it scrolls past, so scrolling back up genuinely runs `initState` again.
///
/// `ScreenUtilInit(designSize: Size(390, 844))` mirrors `main.dart:128-131`.
/// Without it `flutter_screenutil` throws a `LateInitializationError` that
/// production never hits.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chumbucket/core/analytics/analytics.dart';

/// A stand-in for `CallCard` — the reporter is content-agnostic, so the card's
/// own layout is irrelevant to what is being tested here.
class _Row extends StatelessWidget {
  final int index;
  final AnalyticsRecorder recorder;
  const _Row({required this.index, required this.recorder});

  @override
  Widget build(BuildContext context) {
    return CallImpressionReporter(
      callId: 'call_$index',
      marketId: 'market_btc_150k',
      authorId: 'user_ada',
      surface: AnalyticsSurface.feedGlobal,
      position: index,
      side: 'YES',
      outcome: 'PENDING',
      viewerIsSignedIn: true,
      recorder: recorder,
      child: SizedBox(
        height: 200.h,
        child: Center(child: Text('call_$index')),
      ),
    );
  }
}

/// A feed that can be forced to rebuild from the outside, the way a
/// `Consumer<CallsProvider>` is rebuilt by a `notifyListeners()`.
class _Feed extends StatefulWidget {
  final AnalyticsRecorder recorder;
  final ScrollController controller;
  final int itemCount = 30;
  const _Feed({
    required this.recorder,
    required this.controller,
  });

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  int _rebuilds = 0;

  void forceRebuild() => setState(() => _rebuilds++);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('rebuilds: $_rebuilds'),
        Expanded(
          child: ListView.builder(
            controller: widget.controller,
            itemCount: widget.itemCount,
            itemBuilder:
                (_, index) => _Row(index: index, recorder: widget.recorder),
          ),
        ),
      ],
    );
  }
}

Widget _host(Widget child) => ScreenUtilInit(
  designSize: const Size(390, 844),
  builder: (_, __) => MaterialApp(home: Scaffold(body: child)),
);

void main() {
  late InMemoryAnalyticsSink sink;
  late AnalyticsRecorder recorder;

  setUp(() {
    sink = InMemoryAnalyticsSink();
    recorder = AnalyticsRecorder(sink: sink);
    recorder.setUnit('user_you');
  });

  int impressions() => sink.countOf(AnalyticsEventName.feedCallImpression);

  List<String> seenCallIds() =>
      sink
          .named(AnalyticsEventName.feedCallImpression)
          .map((e) => e[AnalyticsProps.callId] as String)
          .toList(growable: false);

  testWidgets('a card on screen reports exactly one impression', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(_Feed(recorder: recorder, controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(impressions(), greaterThan(0));
    expect(seenCallIds().toSet().length, impressions());
    expect(seenCallIds(), contains('call_0'));
  });

  testWidgets('a rebuild does not re-fire an impression', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(_Feed(recorder: recorder, controller: controller)),
    );
    await tester.pumpAndSettle();
    final afterFirstFrame = impressions();
    expect(afterFirstFrame, greaterThan(0));

    // Five provider notifications' worth of rebuilds.
    final state = tester.state<_FeedState>(find.byType(_Feed));
    for (var i = 0; i < 5; i++) {
      state.forceRebuild();
      await tester.pumpAndSettle();
    }
    expect(find.text('rebuilds: 5'), findsOneWidget);
    expect(impressions(), afterFirstFrame);
  });

  testWidgets('scrolling back to a card does not re-fire its impression', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(_Feed(recorder: recorder, controller: controller)),
    );
    await tester.pumpAndSettle();

    final firstScreenful = seenCallIds().toSet();
    expect(firstScreenful, contains('call_0'));

    // Scroll well past the first screenful so those rows are disposed.
    await tester.fling(find.byType(ListView), const Offset(0, -2000), 1200);
    await tester.pumpAndSettle();
    final afterScrollDown = impressions();
    expect(
      afterScrollDown,
      greaterThan(firstScreenful.length),
      reason: 'new rows further down should have produced new impressions',
    );

    // Back to the top. Those rows' State objects are recreated and report
    // again — and the recorder swallows every one of them.
    await tester.fling(find.byType(ListView), const Offset(0, 3000), 1200);
    await tester.pumpAndSettle();
    expect(find.text('call_0'), findsOneWidget);
    expect(impressions(), afterScrollDown);

    // And every impression is still for a distinct card.
    expect(seenCallIds().toSet().length, impressions());
  });

  testWidgets('a recycled row showing a different card reports that card', (
    tester,
  ) async {
    // didUpdateWidget must re-arm when the element is reused for a new call,
    // or a refreshed feed would go silent.
    final controller = ScrollController();
    addTearDown(controller.dispose);

    Widget one(int index) => _host(
      SizedBox(
        height: 400,
        child: ListView(
          controller: controller,
          children: [_Row(index: index, recorder: recorder)],
        ),
      ),
    );

    await tester.pumpWidget(one(0));
    await tester.pumpAndSettle();
    expect(seenCallIds(), ['call_0']);

    await tester.pumpWidget(one(1));
    await tester.pumpAndSettle();
    expect(seenCallIds(), ['call_0', 'call_1']);

    // Back to the first card in the same element: still one impression.
    await tester.pumpWidget(one(0));
    await tester.pumpAndSettle();
    expect(seenCallIds(), ['call_0', 'call_1']);
  });

  testWidgets('no impression payload carries anything user-authored', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(_Feed(recorder: recorder, controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(recorder.rejectedCount, 0, reason: '${recorder.rejections}');
    for (final event in sink.events) {
      expect(AnalyticsPrivacyGuard.inspect(event.props), isEmpty);
      expect(event[AnalyticsProps.treatment], isNotNull);
    }
  });
}
