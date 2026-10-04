import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_badges.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

/// The slice is laid out against a 390x844 design. The default 800x600 test
/// window makes ScreenUtil scale everything ~2x and overflow, which is a
/// harness artefact rather than a layout bug — so every test runs on a phone.
void usePhoneSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget harness(
  CallsProvider provider, {
  VoidCallback? onSignIn,
  VoidCallback? onOpenDares,
  double textScale = 1,
}) {
  return ScreenUtilInit(
    designSize: const Size(390, 844),
    builder:
        (context, _) => MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
          home: ChangeNotifierProvider<CallsProvider>.value(
            value: provider,
            child: CallFeedScreen(
              showHeader: false,
              onSignInRequested: onSignIn,
              onOpenDares: onOpenDares,
            ),
          ),
        ),
  );
}

CallsProvider providerFor(
  MockCallsRepository repo, {
  String? viewerUserId = viewer,
}) {
  final provider = CallsProvider(repository: repo);
  if (viewerUserId != null) provider.setViewer(viewerUserId);
  return provider;
}

void main() {
  testWidgets('loading state shows skeletons, never a bare blank screen', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final repo = MockCallsRepository(latency: const Duration(seconds: 1));
    await tester.pumpWidget(harness(providerFor(repo)));
    await tester.pump(); // post-frame callback fires loadFeed
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CallsLoadingView), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('ready state renders call cards and both feed tabs', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockCallsRepository());
    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();

    expect(find.byType(CallCard), findsWidgets);
    expect(find.text('Global'), findsOneWidget);
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
  });

  testWidgets('every visible call is labelled "Free call", never "Funded"', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockCallsRepository());
    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();

    expect(find.text(FundingState.none.label), findsWidgets);
    expect(find.text(FundingState.filled.label), findsNothing);
    expect(find.byType(FundingStateBadge), findsWidgets);
  });

  testWidgets('no stake, PnL or copy-trade affordance is rendered anywhere', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockCallsRepository());
    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? '').toLowerCase())
        .join(' | ');

    for (final forbidden in [
      'stake',
      'usdc',
      'lamports',
      'pnl',
      'profit',
      'copy trade',
      'copy this',
      'auto-follow',
    ]) {
      expect(
        rendered.contains(forbidden),
        isFalse,
        reason: 'feed rendered "$forbidden"',
      );
    }
  });

  testWidgets('the open-dares notice opens your dares, or is not shown', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockCallsRepository());
    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();
    expect(provider.invitations, isNotEmpty);
    // No destination, no notice: nothing on Home that cannot be acted on.
    expect(find.textContaining('open dare'), findsNothing);

    var opened = 0;
    await tester.pumpWidget(harness(provider, onOpenDares: () => opened++));
    await tester.pumpAndSettle();
    final notice = find.byKey(const ValueKey('home-open-dares'));
    expect(notice, findsOneWidget);
    expect(tester.getSize(notice).height, greaterThanOrEqualTo(48));
    expect(
      find.bySemanticsLabel(RegExp(r'open dares? waiting\. Open your dares')),
      findsOneWidget,
    );
    await tester.tap(notice);
    expect(opened, 1);
  });

  for (final (width, scale) in [(390.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
    testWidgets('at ${width}dp and ${scale}x the Call action covers no tab', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = Size(width * 2, 844 * 2);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = providerFor(MockCallsRepository());
      await tester.pumpWidget(harness(provider, textScale: scale));
      await tester.pumpAndSettle();
      Rect call() =>
          tester.getRect(find.bySemanticsLabel('Make a call').first);
      expect(call().width, greaterThanOrEqualTo(48));
      expect(call().height, greaterThanOrEqualTo(48));
      expect(call().right, lessThanOrEqualTo(width));
      for (final label in ['Following', 'Global']) {
        expect(
          tester.getRect(find.text(label)).overlaps(call()),
          isFalse,
          reason: '$label under Call',
        );
        // The test font draws every glyph a full em wide, so at 2x the
        // labels can outgrow the phone and the strip scrolls; scrolled into
        // view, a label is whole and still clear of the button.
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        final tab = tester.getRect(find.text(label));
        expect(tab.overlaps(call()), isFalse, reason: '$label under Call');
        expect(tab.left, greaterThanOrEqualTo(0), reason: label);
        expect(tab.right, lessThanOrEqualTo(width), reason: label);
      }
      // Both destinations still work by a plain tap.
      for (final (label, mode) in [
        ('Following', CallFeedMode.following),
        ('Global', CallFeedMode.global),
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(provider.feedMode, mode);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching to Following narrows the feed', (tester) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockCallsRepository());
    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();
    final globalCount = provider.feed.length;

    // The tab strip scrolls horizontally when the labels do not fit, so bring
    // the destination fully into view before tapping it.
    await tester.ensureVisible(find.text('Following'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();

    expect(provider.feedMode, CallFeedMode.following);
    expect(provider.feed.length, lessThan(globalCount));
  });

  testWidgets('empty state offers a way out, not a dead end', (tester) async {
    usePhoneSurface(tester);
    final repo = MockCallsRepository()..debugClearCalls();
    await tester.pumpWidget(harness(providerFor(repo)));
    await tester.pumpAndSettle();

    expect(find.byType(CallsEmptyView), findsOneWidget);
    expect(find.text('Make a call'), findsOneWidget);
  });

  testWidgets('error state is distinct from offline and offers retry', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final repo = MockCallsRepository()..simulateFailure = true;
    await tester.pumpWidget(harness(providerFor(repo)));
    await tester.pumpAndSettle();

    expect(find.byType(CallsErrorView), findsOneWidget);
    expect(find.byType(CallsOfflineView), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('offline state is its own thing', (tester) async {
    usePhoneSurface(tester);
    final repo = MockCallsRepository()..simulateOffline = true;
    await tester.pumpWidget(harness(providerFor(repo)));
    await tester.pumpAndSettle();

    expect(find.byType(CallsOfflineView), findsOneWidget);
    expect(find.byType(CallsErrorView), findsNothing);
    expect(find.textContaining('offline'), findsWidgets);
  });

  testWidgets('offline WITH cached rows keeps them and says they are cached', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final repo = MockCallsRepository();
    final provider = providerFor(repo);
    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();
    expect(find.byType(CallCard), findsWidgets);

    repo.simulateOffline = true;
    await provider.loadFeed(force: true);
    await tester.pumpAndSettle();

    expect(find.byType(CallCard), findsWidgets);
    // A small pill, not a banner, and no retry button.
    expect(find.byType(ChumbucketOfflinePill), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a stale feed stays as it is: no age, no refresh button', (
    tester,
  ) async {
    usePhoneSurface(tester);
    var now = DateTime.utc(2026, 9, 13, 12);
    final provider = CallsProvider(
      repository: MockCallsRepository(clock: () => now),
      clock: () => now,
      staleAfter: const Duration(minutes: 2),
    )..setViewer(viewer);

    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();
    expect(find.text('Refresh'), findsNothing);

    // Move the clock past the staleness window and let an unrelated load
    // trigger the rebuild — the feed itself is deliberately NOT refetched.
    now = now.add(const Duration(minutes: 10));
    await provider.loadMarketDetail('market_btc_150k');
    await tester.pumpAndSettle();

    // The app refreshes on its own (open, resume, pull); it never narrates
    // how old the feed is or asks the person to refresh it.
    expect(find.text('Refresh'), findsNothing);
    expect(find.textContaining('Last updated'), findsNothing);
    expect(find.textContaining('ago'), findsNothing);
    expect(find.byType(CallCard), findsWidgets);
  });

  testWidgets('signed out can still read the feed', (tester) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockCallsRepository(), viewerUserId: null);
    await tester.pumpWidget(harness(provider));
    await tester.pumpAndSettle();

    expect(provider.isSignedIn, isFalse);
    expect(find.byType(CallCard), findsWidgets);
  });

  testWidgets('signed out tapping "Call it" asks the shell to sign in', (
    tester,
  ) async {
    usePhoneSurface(tester);
    var asked = 0;
    final provider = providerFor(MockCallsRepository(), viewerUserId: null);
    await tester.pumpWidget(harness(provider, onSignIn: () => asked++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Call'));
    await tester.pumpAndSettle();

    expect(asked, 1);
  });

  testWidgets('signed out with an empty feed shows the signed-out view', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final repo = MockCallsRepository()..debugClearCalls();
    final provider = providerFor(repo, viewerUserId: null);
    await tester.pumpWidget(harness(provider, onSignIn: () {}));
    await tester.pumpAndSettle();

    expect(find.byType(CallsSignedOutView), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('an open dare invitation is surfaced without money words', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockCallsRepository());
    await tester.pumpWidget(harness(provider, onOpenDares: () {}));
    await tester.pumpAndSettle();

    expect(find.textContaining('open dare'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\b(bet|stake|win money)\b')), findsNothing);
  });
}
