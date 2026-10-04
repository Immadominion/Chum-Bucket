/// The shared state screen and the Activity states, on a 320dp phone at 2x
/// text: one line, at most one 48dp action, the brand art, nothing clipped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/notifications/data/mock_notifications_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';
import 'package:chumbucket/features/notifications/presentation/screens/activity_screen.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double scale = 2,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, _) => MaterialApp(
            builder:
                (context, inner) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: inner!,
                ),
            home: child,
          ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A short first page that says there is more, then a next page that fails
/// until [nextPageWorks] — counting every ask for it.
class _PagedInbox implements NotificationsRepository {
  int nextPageAsks = 0;
  int servedAt = 1000;
  bool nextPageWorks = false;

  CallNotification _row(String id) => CallNotification(
    id: id,
    recipientUserId: MockCallsRepository.demoViewerUserId,
    kind: CallNotificationKind.backed,
    title: 'Row $id',
    body: 'They went on record on the same side as you.',
    createdAt: DateTime.now().millisecondsSinceEpoch,
    target: const NotificationCallTarget('call_you_fed'),
    isUnread: false,
  );

  @override
  Future<NotificationPage> fetchNotifications({
    required String? viewerUserId,
    NotificationFilter filter = NotificationFilter.all,
    String? cursor,
    int limit = 20,
  }) async {
    if (cursor == null) {
      return NotificationPage(
        notifications: [_row('a'), _row('b')],
        nextCursor: 'page-2',
        servedAt: servedAt++,
        unreadCount: 0,
      );
    }
    nextPageAsks++;
    if (!nextPageWorks) throw const NotificationsOfflineException();
    return NotificationPage(
      notifications: [_row('c')],
      servedAt: servedAt,
      unreadCount: 0,
    );
  }

  @override
  Future<int> unreadCount({required String? viewerUserId}) async => 0;

  @override
  Future<void> markAllRead({required String? viewerUserId}) async {}

  @override
  Future<void> markRead({
    required String? viewerUserId,
    required String notificationId,
  }) async {}
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'an error shows a short human reason, never the transport\'s internals',
    (tester) async {
      Future<void> show(String reason) => _mount(
        tester,
        Scaffold(body: CallsErrorView(message: reason, onRetry: () {})),
        width: 390,
        scale: 1,
      );

      // A reason written for people is the line.
      await show('This profile is private.');
      expect(find.text('This profile is private.'), findsOneWidget);

      // What the transport says about itself is never the headline, and a
      // screen reader is not read a procedure path or a status code either.
      for (final internal in const [
        'The server sent an empty envelope for calls.feed.',
        'calls.feed: The server returned 502.',
        'The server sent something we could not read (calls.feed, status 500).',
        'PANTA_UNAVAILABLE',
        'Invalid input: expected string, received undefined',
        'Unknown market: market_btc_150k',
      ]) {
        await show(internal);
        expect(
          find.text('Couldn\u2019t load this'),
          findsOneWidget,
          reason: internal,
        );
        expect(find.text(internal), findsNothing, reason: internal);
        expect(
          tester.getSemantics(find.text('Couldn\u2019t load this')).hint,
          isNot(contains(internal)),
          reason: internal,
        );
      }
    },
  );

  testWidgets('one line, one 48dp action, the hint only for screen readers', (
    tester,
  ) async {
    var tapped = 0;
    await _mount(
      tester,
      Scaffold(
        body: ChumbucketStateFill(
          child: ChumbucketStateView(
            artwork: ChumbucketStateArtwork.inbox,
            message: 'No activity yet',
            semanticsHint: 'Backs, fades and results land here.',
            actionLabel: 'Make a call',
            onAction: () => tapped++,
          ),
        ),
      ),
    );
    expect(find.byType(ChumbucketStateArt), findsOneWidget);
    expect(find.text('No activity yet'), findsOneWidget);
    // The hint is not drawn.
    expect(find.text('Backs, fades and results land here.'), findsNothing);
    expect(
      tester.getSemantics(find.text('No activity yet')).hint,
      'Backs, fades and results land here.',
    );
    expect(find.byType(ChumbucketPrimaryButton), findsOneWidget);
    expect(
      tester.getSize(find.byType(ChumbucketPrimaryButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('Make a call'));
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no action without both a label and a handler', (tester) async {
    await _mount(
      tester,
      const Scaffold(
        body: ChumbucketStateView(
          artwork: ChumbucketStateArtwork.record,
          message: 'No calls on record yet',
          actionLabel: 'Orphan label',
        ),
      ),
    );
    expect(find.byType(ChumbucketPrimaryButton), findsNothing);
    expect(find.text('Orphan label'), findsNothing);
  });

  testWidgets('offline over saved content is a small pill, read out in full', (
    tester,
  ) async {
    await _mount(
      tester,
      const Scaffold(body: Center(child: ChumbucketOfflinePill())),
    );
    expect(find.text('Offline'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Offline. Showing what was saved on this phone.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
  });

  group('Activity states', () {
    Widget activity(NotificationsProvider inbox) =>
        ChangeNotifierProvider<NotificationsProvider>.value(
          value: inbox,
          child: const ActivityScreen(),
        );

    testWidgets('a failure is the error scene with one Try again', (
      tester,
    ) async {
      final repo = MockNotificationsRepository()..simulateFailure = true;
      final inbox = NotificationsProvider(repository: repo)
        ..setViewer(MockCallsRepository.demoViewerUserId);
      addTearDown(inbox.dispose);
      await _mount(tester, activity(inbox));
      expect(
        tester
            .widget<ChumbucketStateArt>(find.byType(ChumbucketStateArt))
            .artwork,
        ChumbucketStateArtwork.error,
      );
      expect(find.text('Couldn’t load your activity'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      repo.simulateFailure = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('New'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed out is the inbox scene with one Sign in', (
      tester,
    ) async {
      final inbox = NotificationsProvider(
        repository: MockNotificationsRepository(),
      )..setViewer(null);
      addTearDown(inbox.dispose);
      await _mount(tester, activity(inbox));
      expect(find.text('Sign in to see who backs you'), findsOneWidget);
      expect(
        find.widgetWithText(ChumbucketPrimaryButton, 'Sign in'),
        findsOneWidget,
      );
      // No paragraph about wallets, Google or X.
      expect(find.textContaining('Google'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mark all read is an icon, and older rows have a short date', (
      tester,
    ) async {
      final inbox = NotificationsProvider(
        repository: MockNotificationsRepository(),
      )..setViewer(MockCallsRepository.demoViewerUserId);
      addTearDown(inbox.dispose);
      await _mount(tester, activity(inbox), width: 390, scale: 1);
      expect(find.byTooltip('Mark all read'), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);
      // A week-old row: "27 Sep", never "27 Sep, 01:23 UTC".
      expect(find.textContaining('UTC'), findsNothing);
      await tester.tap(find.byTooltip('Mark all read'));
      await tester.pumpAndSettle();
      expect(find.text('New'), findsNothing);
      expect(find.text('Earlier'), findsOneWidget);
      expect(find.byTooltip('Mark all read'), findsNothing);
    });
    testWidgets('older rows load by themselves, and a failed page is asked '
        'for once, not on every frame', (tester) async {
      final repo = _PagedInbox();
      final inbox = NotificationsProvider(repository: repo)
        ..setViewer(MockCallsRepository.demoViewerUserId);
      addTearDown(inbox.dispose);
      await _mount(tester, activity(inbox), width: 390, scale: 1);

      // Two rows do not fill the screen: the next page is asked for without
      // a scroll, fails offline, and is not asked for again while nothing
      // changes — however much the list is dragged.
      expect(repo.nextPageAsks, 1);
      for (var i = 0; i < 5; i++) {
        await tester.drag(find.text('Row b'), const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(repo.nextPageAsks, 1);
      expect(find.text('Row a'), findsOneWidget);

      // A refresh reads page one again; its next page is asked for once more
      // and this time it lands.
      repo.nextPageWorks = true;
      await inbox.load(force: true);
      await tester.pumpAndSettle();
      expect(repo.nextPageAsks, 2);
      expect(find.text('Row c'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
