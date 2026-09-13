/// The inbox repository and provider: read state, the unread count, the four
/// kinds, and every failure the screen has to be able to render.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/notifications/data/mock_notifications_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

NotificationsProvider providerFor(
  MockNotificationsRepository repo, {
  String? viewerUserId = viewer,
}) {
  final provider = NotificationsProvider(repository: repo);
  provider.setViewer(viewerUserId);
  return provider;
}

void main() {
  group('the mock inbox', () {
    test('seeds all four kinds, and every one points somewhere real', () async {
      final repo = MockNotificationsRepository();
      final page = await repo.fetchNotifications(viewerUserId: viewer);

      expect(
        page.notifications.map((n) => n.kind).toSet(),
        CallNotificationKind.values.toSet(),
      );

      // Every seeded target names a call that MockCallsRepository actually has.
      final calls = MockCallsRepository();
      final known = calls.debugCalls.map((c) => c.id).toSet();
      for (final notification in page.notifications) {
        final target = notification.target;
        final callId = switch (target) {
          NotificationCallTarget(:final callId) => callId,
          NotificationReceiptTarget(:final callId) => callId,
          NotificationPersonTarget() => null,
        };
        if (callId != null) {
          expect(known, contains(callId), reason: '${notification.kind}');
        }
      }
    });

    test('is newest first', () async {
      final repo = MockNotificationsRepository();
      final page = await repo.fetchNotifications(viewerUserId: viewer);
      final times = page.notifications.map((n) => n.createdAt).toList();
      final sorted = [...times]..sort((a, b) => b.compareTo(a));
      expect(times, sorted);
    });

    test('a resolution has no actor; the other three do', () async {
      final repo = MockNotificationsRepository();
      final page = await repo.fetchNotifications(viewerUserId: viewer);
      for (final notification in page.notifications) {
        expect(
          notification.actor == null,
          notification.kind == CallNotificationKind.resolved,
          reason: '${notification.kind}',
        );
      }
    });

    test('reports unread across the inbox, not across the page', () async {
      final repo = MockNotificationsRepository();
      final page = await repo.fetchNotifications(
        viewerUserId: viewer,
        filter: NotificationFilter.unread,
        limit: 1,
      );
      expect(page.notifications.length, 1);
      expect(page.unreadCount, 3);
      expect(await repo.unreadCount(viewerUserId: viewer), 3);
    });

    test('there is no such thing as an anonymous inbox', () async {
      final repo = MockNotificationsRepository();
      expect(
        () => repo.fetchNotifications(viewerUserId: null),
        throwsA(isA<NotificationsSignedOutException>()),
      );
      expect(
        () => repo.markAllRead(viewerUserId: null),
        throwsA(isA<NotificationsSignedOutException>()),
      );
    });

    test('one inbox never leaks into another', () async {
      final repo = MockNotificationsRepository();
      final other = await repo.fetchNotifications(viewerUserId: 'user_ada');
      expect(other.notifications, isEmpty);
      expect(other.unreadCount, 0);
    });

    test('marking read is idempotent and survives an unknown id', () async {
      final repo = MockNotificationsRepository();
      final page = await repo.fetchNotifications(viewerUserId: viewer);
      final first = page.notifications.firstWhere((n) => n.isUnread);

      await repo.markRead(viewerUserId: viewer, notificationId: first.id);
      await repo.markRead(viewerUserId: viewer, notificationId: first.id);
      await repo.markRead(viewerUserId: viewer, notificationId: 'nope');

      expect(await repo.unreadCount(viewerUserId: viewer), 2);
    });

    test('the unread filter hides read rows', () async {
      final repo = MockNotificationsRepository();
      final all = await repo.fetchNotifications(viewerUserId: viewer);
      final unread = await repo.fetchNotifications(
        viewerUserId: viewer,
        filter: NotificationFilter.unread,
      );
      expect(all.notifications.length, 4);
      expect(unread.notifications.length, 3);

      await repo.markAllRead(viewerUserId: viewer);
      final after = await repo.fetchNotifications(
        viewerUserId: viewer,
        filter: NotificationFilter.unread,
      );
      expect(after.notifications, isEmpty);
      expect(after.unreadCount, 0);
    });

    test('pages with a cursor', () async {
      final repo = MockNotificationsRepository();
      final first = await repo.fetchNotifications(
        viewerUserId: viewer,
        limit: 2,
      );
      expect(first.notifications.length, 2);
      expect(first.nextCursor, isNotNull);

      final second = await repo.fetchNotifications(
        viewerUserId: viewer,
        limit: 2,
        cursor: first.nextCursor,
      );
      expect(second.notifications.length, 2);
      expect(second.nextCursor, isNull);
      expect(
        {...first.notifications, ...second.notifications}.length,
        4,
      );
    });
  });

  group('the provider', () {
    test('signed out is a state, not an empty list', () async {
      final provider = providerFor(
        MockNotificationsRepository(),
        viewerUserId: null,
      );
      await provider.load();
      expect(provider.state, NotificationsLoadState.signedOut);
      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
    });

    test('empty is a state, not an error', () async {
      final repo = MockNotificationsRepository()..debugClear();
      final provider = providerFor(repo);
      await provider.load();
      expect(provider.state, NotificationsLoadState.empty);
      expect(provider.error, isNull);
    });

    test('ready carries the rows and the unread count', () async {
      final provider = providerFor(MockNotificationsRepository());
      await provider.load();
      expect(provider.state, NotificationsLoadState.ready);
      expect(provider.notifications.length, 4);
      expect(provider.unreadCount, 3);
    });

    test('offline with nothing cached is its own state', () async {
      final repo = MockNotificationsRepository()..simulateOffline = true;
      final provider = providerFor(repo);
      await provider.load();
      expect(provider.state, NotificationsLoadState.offline);
      expect(provider.isOffline, isTrue);
    });

    test('offline keeps what is already on screen and flags it cached', () async {
      final repo = MockNotificationsRepository();
      final provider = providerFor(repo);
      await provider.load();
      expect(provider.notifications, isNotEmpty);

      repo.simulateOffline = true;
      await provider.load(force: true);

      expect(provider.state, NotificationsLoadState.ready);
      expect(provider.isOffline, isTrue);
      expect(provider.isFromCache, isTrue);
      expect(provider.notifications, isNotEmpty);
    });

    test('a generic failure is an error state, not an offline one', () async {
      final repo = MockNotificationsRepository()..simulateFailure = true;
      final provider = providerFor(repo);
      await provider.load();
      expect(provider.state, NotificationsLoadState.error);
      expect(provider.isOffline, isFalse);
    });

    test('marking one read drops the badge immediately', () async {
      final provider = providerFor(MockNotificationsRepository());
      await provider.load();
      final unread = provider.notifications.firstWhere((n) => n.isUnread);

      await provider.markRead(unread.id);

      expect(provider.unreadCount, 2);
      expect(
        provider.notifications.firstWhere((n) => n.id == unread.id).isUnread,
        isFalse,
      );
    });

    test('a failed mark-read rolls the row back rather than lying', () async {
      final repo = MockNotificationsRepository();
      final provider = providerFor(repo);
      await provider.load();
      final unread = provider.notifications.firstWhere((n) => n.isUnread);

      repo.simulateFailure = true;
      await provider.markRead(unread.id);

      expect(provider.unreadCount, 3);
      expect(
        provider.notifications.firstWhere((n) => n.id == unread.id).isUnread,
        isTrue,
      );
    });

    test('mark all read clears the badge', () async {
      final provider = providerFor(MockNotificationsRepository());
      await provider.load();
      await provider.markAllRead();
      expect(provider.unreadCount, 0);
      expect(provider.notifications.every((n) => !n.isUnread), isTrue);
    });

    test('switching the filter refetches instead of filtering locally', () async {
      final provider = providerFor(MockNotificationsRepository());
      await provider.load();
      expect(provider.notifications.length, 4);

      await provider.setFilter(NotificationFilter.unread);
      expect(provider.filter, NotificationFilter.unread);
      expect(provider.notifications.length, 3);
    });

    test('reading a row under the unread filter removes it from the list',
        () async {
      final provider = providerFor(MockNotificationsRepository());
      await provider.setFilter(NotificationFilter.unread);
      expect(provider.notifications.length, 3);

      final first = provider.notifications.first;
      await provider.markRead(first.id);

      expect(provider.notifications.length, 2);
      expect(provider.notifications.any((n) => n.id == first.id), isFalse);
    });

    test('changing account empties the inbox rather than showing the last one',
        () async {
      final provider = providerFor(MockNotificationsRepository());
      await provider.load();
      expect(provider.notifications, isNotEmpty);

      provider.setViewer('user_ada');
      expect(provider.notifications, isEmpty);
      expect(provider.unreadCount, 0);
    });

    test('staleness is reported without being treated as an error', () async {
      var now = DateTime.utc(2026, 9, 13, 12);
      final repo = MockNotificationsRepository(clock: () => now);
      final provider = NotificationsProvider(
        repository: repo,
        clock: () => now,
        staleAfter: const Duration(minutes: 2),
      )..setViewer(viewer);

      await provider.load();
      expect(provider.isStale, isFalse);

      now = now.add(const Duration(minutes: 5));
      expect(provider.isStale, isTrue);
      expect(provider.state, NotificationsLoadState.ready);
      expect(provider.error, isNull);
    });

    test('the badge alone never throws on a signed-out session', () async {
      final provider = providerFor(
        MockNotificationsRepository(),
        viewerUserId: null,
      );
      await provider.refreshUnreadCount();
      expect(provider.unreadCount, 0);
    });

    test('a void resolution survives the whole path intact', () async {
      final repo = MockNotificationsRepository();
      repo.debugAdd(
        kind: CallNotificationKind.resolved,
        marketQuestion: 'Will the rumoured Q3 listing be announced?',
        target: const NotificationReceiptTarget('call_kemi_listing'),
        outcome: CallOutcome.voided,
        subjectCallId: 'call_kemi_listing',
      );
      final provider = providerFor(repo);
      await provider.load();

      final voided = provider.notifications.firstWhere(
        (n) => n.outcome == CallOutcome.voided,
      );
      expect(voided.title, 'Your call was voided');
      expect(voided.body, contains('neither a win nor a loss'));
    });
  });
}
