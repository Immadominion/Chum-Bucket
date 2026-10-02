/// The inbox screen: every reachable state, and the promise that tapping a row
/// opens the exact call, receipt or person it refers to.
library;

import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_state_views.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/notifications/data/mock_notifications_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/presentation/notification_target_router.dart';
import 'package:chumbucket/features/notifications/presentation/screens/notifications_inbox_screen.dart';
import 'package:chumbucket/features/notifications/presentation/widgets/notification_row.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/features/receipts/presentation/call_receipt_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'packet_g_fixtures.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

NotificationsProvider providerFor(
  MockNotificationsRepository repo, {
  String? viewerUserId = viewer,
}) {
  final provider = NotificationsProvider(repository: repo);
  provider.setViewer(viewerUserId);
  return provider;
}

/// Inbox alone. The opener is injected so routing can be observed without a
/// second feature's providers.
Widget inboxHarness(
  NotificationsProvider provider, {
  NotificationTargetOpener? openTarget,
  VoidCallback? onSignIn,
}) => ChangeNotifierProvider<NotificationsProvider>.value(
  value: provider,
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder:
        (context, _) => MaterialApp(
          home: NotificationsInboxScreen(
            openTarget: openTarget,
            onSignInRequested: onSignIn,
          ),
        ),
  ),
);

/// Inbox plus the call slice, so the real router can be exercised end to end.
///
/// Providers sit ABOVE `MaterialApp`, mirroring `main.dart`: a pushed route is
/// not a descendant of anything placed under `home:`, so a router that opens a
/// new screen would not find them otherwise.
Widget wiredHarness(
  NotificationsProvider notifications,
  CallsProvider calls,
) => MultiProvider(
  providers: [
    ChangeNotifierProvider<NotificationsProvider>.value(value: notifications),
    ChangeNotifierProvider<CallsProvider>.value(value: calls),
  ],
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder:
        (context, _) => const MaterialApp(home: NotificationsInboxScreen()),
  ),
);

void main() {
  testWidgets('loading shows skeletons, never a bare blank screen', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final repo = MockNotificationsRepository(
      latency: const Duration(seconds: 1),
    );
    await tester.pumpWidget(inboxHarness(providerFor(repo)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CallsLoadingView), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('ready renders one row per notification and the unread count', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(inboxHarness(providerFor(MockNotificationsRepository())));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationRow), findsNWidgets(4));
    expect(find.text('3 unread'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Unread'), findsOneWidget);
  });

  testWidgets('every one of the four kinds is rendered, labelled', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(inboxHarness(providerFor(MockNotificationsRepository())));
    await tester.pumpAndSettle();

    for (final kind in CallNotificationKind.values) {
      expect(
        find.text(kind.label.toUpperCase()),
        findsOneWidget,
        reason: '${kind.wire} row is missing',
      );
    }
  });

  testWidgets('the inbox never shows an amount, a stake or crowd pressure', (
    tester,
  ) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(inboxHarness(providerFor(MockNotificationsRepository())));
    await tester.pumpAndSettle();

    final texts =
        tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => (t.data ?? '').toLowerCase())
            .join(' | ');

    // A market question may legitimately contain a price — "Will BTC trade
    // above \$150,000…" is the venue's exact wording and contract §3 forbids
    // paraphrasing it. What must never appear is a stake, a payout, a balance,
    // a crowd number or a copy-trade control.
    final banned = <RegExp>[
      RegExp(r'\bwager'),
      RegExp(r'\bpayout'),
      RegExp(r'\bbalance\b'),
      RegExp(r'\bodds\b'),
      RegExp(r'\bprofit\b'),
      RegExp(r'stake of'),
      RegExp(r'at stake'),
      RegExp(r'you staked'),
      RegExp(r'people are'),
      RegExp(r'\beveryone\b'),
      RegExp(r'copy[- ]trade'),
      RegExp(r'\bhurry\b'),
      RegExp(r'last chance'),
      // A number attached to a currency symbol anywhere but inside a question.
      RegExp(r'\$\s*[\d.,]+\s*(staked|to win|prize|pot)'),
    ];
    for (final pattern in banned) {
      expect(
        pattern.hasMatch(texts),
        isFalse,
        reason: 'inbox copy matched ${pattern.pattern}',
      );
    }

    // …and the rematch row says, positively, that there is nothing at stake.
    expect(texts, contains('no stake, no escrow, nothing to fund'));
  });

  testWidgets('tapping a row marks it read and opens its target', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockNotificationsRepository());
    final opened = <CallNotificationTarget>[];

    await tester.pumpWidget(
      inboxHarness(
        provider,
        openTarget: (context, target) async => opened.add(target),
      ),
    );
    await tester.pumpAndSettle();

    final first = provider.notifications.first;
    expect(first.isUnread, isTrue);

    await tester.tap(find.byType(NotificationRow).first);
    await tester.pumpAndSettle();

    expect(opened, [first.target]);
    expect(
      provider.notifications.firstWhere((n) => n.id == first.id).isUnread,
      isFalse,
    );
    expect(provider.unreadCount, 2);
  });

  testWidgets('each kind opens the destination it refers to', (tester) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockNotificationsRepository());
    final opened = <CallNotificationTarget>[];

    await tester.pumpWidget(
      inboxHarness(
        provider,
        openTarget: (context, target) async => opened.add(target),
      ),
    );
    await tester.pumpAndSettle();

    final rows = provider.notifications;
    for (var i = 0; i < rows.length; i++) {
      await tester.tap(find.byType(NotificationRow).at(i));
      await tester.pumpAndSettle();
    }

    expect(opened.length, rows.length);
    for (var i = 0; i < rows.length; i++) {
      expect(opened[i], rows[i].target);
    }
    // A resolution goes to the receipt; the rest go to the call itself.
    final resolved = rows.firstWhere(
      (n) => n.kind == CallNotificationKind.resolved,
    );
    expect(resolved.target, isA<NotificationReceiptTarget>());
  });

  testWidgets('tapping an actor avatar opens that person, not the call', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockNotificationsRepository());
    final opened = <CallNotificationTarget>[];

    await tester.pumpWidget(
      inboxHarness(
        provider,
        openTarget: (context, target) async => opened.add(target),
      ),
    );
    await tester.pumpAndSettle();

    final withActor = provider.notifications.indexWhere(
      (n) => n.actor != null,
    );
    final row = provider.notifications[withActor];

    await tester.tap(
      find.descendant(
        of: find.byType(NotificationRow).at(withActor),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Open ${row.actor!.displayName}',
        ),
      ),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(opened, [NotificationPersonTarget(row.actor!.id)]);
  });

  testWidgets('signed out asks for an account, never for a wallet', (
    tester,
  ) async {
    usePhoneSurface(tester);
    var asked = false;
    await tester.pumpWidget(
      inboxHarness(
        providerFor(MockNotificationsRepository(), viewerUserId: null),
        onSignIn: () => asked = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CallsSignedOutView), findsOneWidget);
    expect(find.textContaining('No wallet needed'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(asked, isTrue);
  });

  testWidgets('empty is a designed state with a way out', (tester) async {
    usePhoneSurface(tester);
    final repo = MockNotificationsRepository()..debugClear();
    await tester.pumpWidget(inboxHarness(providerFor(repo)));
    await tester.pumpAndSettle();

    expect(find.byType(CallsEmptyView), findsOneWidget);
    expect(find.text('Nothing has come back yet'), findsOneWidget);
  });

  testWidgets('the unread filter has its own empty state and a way back', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockNotificationsRepository());
    await tester.pumpWidget(inboxHarness(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing unread'), findsOneWidget);
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationRow), findsNWidgets(4));
  });

  testWidgets('offline is its own state, with a retry', (tester) async {
    usePhoneSurface(tester);
    final repo = MockNotificationsRepository()..simulateOffline = true;
    await tester.pumpWidget(inboxHarness(providerFor(repo)));
    await tester.pumpAndSettle();

    expect(find.byType(CallsOfflineView), findsOneWidget);

    repo.simulateOffline = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationRow), findsNWidgets(4));
  });

  testWidgets('offline with rows underneath says they are cached', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final repo = MockNotificationsRepository();
    final provider = providerFor(repo);
    await tester.pumpWidget(inboxHarness(provider));
    await tester.pumpAndSettle();

    repo.simulateOffline = true;
    await provider.load(force: true);
    await tester.pumpAndSettle();

    expect(find.byType(NotificationRow), findsNWidgets(4));
    expect(
      find.text('Offline — showing what we already had.'),
      findsOneWidget,
    );
  });

  testWidgets('a failure is an error state, not a silent empty list', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final repo = MockNotificationsRepository()..simulateFailure = true;
    await tester.pumpWidget(inboxHarness(providerFor(repo)));
    await tester.pumpAndSettle();

    expect(find.byType(CallsErrorView), findsOneWidget);
    expect(find.byType(CallsEmptyView), findsNothing);
  });

  testWidgets('mark all read empties the badge and softens every row', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final provider = providerFor(MockNotificationsRepository());
    await tester.pumpWidget(inboxHarness(provider));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mark all read'));
    await tester.pumpAndSettle();

    expect(provider.unreadCount, 0);
    expect(find.text('Mark all read'), findsNothing);
    expect(find.text('3 unread'), findsNothing);
    expect(find.byType(NotificationRow), findsNWidgets(4));
  });

  group('the real router', () {
    testWidgets('a call notification opens that call', (tester) async {
      usePhoneSurface(tester);
      final notifications = providerFor(MockNotificationsRepository());
      final calls = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);

      await tester.pumpWidget(wiredHarness(notifications, calls));
      await tester.pumpAndSettle();

      final index = notifications.notifications.indexWhere(
        (n) => n.target is NotificationCallTarget,
      );
      await tester.tap(find.byType(NotificationRow).at(index));
      await tester.pumpAndSettle();

      expect(find.byType(CallDetailScreen), findsOneWidget);
    });

    testWidgets('a resolution notification opens the receipt', (tester) async {
      usePhoneSurface(tester);
      final notifications = providerFor(MockNotificationsRepository());
      final calls = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);

      await tester.pumpWidget(wiredHarness(notifications, calls));
      await tester.pumpAndSettle();

      final index = notifications.notifications.indexWhere(
        (n) => n.target is NotificationReceiptTarget,
      );
      await tester.tap(find.byType(NotificationRow).at(index));
      await tester.pumpAndSettle();

      expect(find.byType(CallReceiptSheet), findsOneWidget);
      // The receipt's own hero is the sheet's top; its title is the sheet's
      // accessible heading rather than a second header.
      expect(find.bySemanticsLabel('Your receipt'), findsOneWidget);
    });

    testWidgets('an actor avatar opens that person', (tester) async {
      usePhoneSurface(tester);
      final notifications = providerFor(MockNotificationsRepository());
      final calls = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);

      await tester.pumpWidget(wiredHarness(notifications, calls));
      await tester.pumpAndSettle();

      final index = notifications.notifications.indexWhere(
        (n) => n.actor != null,
      );
      final actor = notifications.notifications[index].actor!;

      await tester.tap(
        find.descendant(
          of: find.byType(NotificationRow).at(index),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Open ${actor.displayName}',
          ),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(CallPersonScreen), findsOneWidget);
    });
  });
}
