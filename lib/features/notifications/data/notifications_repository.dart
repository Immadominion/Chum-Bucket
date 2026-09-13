/// The seam between the inbox and whatever serves it.
///
/// Deliberately shaped like `CallsRepository`: one failure type per reachable
/// UI state, a page object that carries its own freshness metadata, and a
/// `viewerUserId` that is a canonical `public.users.id` and **never** a wallet.
/// When a BFF notification route lands, an implementation on the existing
/// `_postMutation(procedurePath, input)` transport replaces
/// [MockNotificationsRepository] and nothing above this file changes.
///
/// An inbox is personal, so unlike the call feed, reading it requires a signed
/// in user. That is the one deliberate difference from `CallsRepository`.
library;

import 'package:chumbucket/features/notifications/data/notification_models.dart';

// ---------------------------------------------------------------------------
// Failures — one per reachable UI state
// ---------------------------------------------------------------------------

/// Base class so a screen can branch on kind without string-matching.
sealed class NotificationsException implements Exception {
  final String message;
  const NotificationsException(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

/// The device (or the BFF) is unreachable. Distinct from
/// [NotificationsFailure] so the UI can offer "you're offline" rather than
/// "something went wrong".
class NotificationsOfflineException extends NotificationsException {
  const NotificationsOfflineException([
    super.message = 'No connection. Showing what we already had.',
  ]);
}

/// An inbox belongs to a person, so reading one needs an account. It does
/// **not** need a wallet.
class NotificationsSignedOutException extends NotificationsException {
  const NotificationsSignedOutException([
    super.message = 'Sign in to see what came back.',
  ]);
}

/// Anything else.
class NotificationsFailure extends NotificationsException {
  const NotificationsFailure([super.message = 'Something went wrong.']);
}

// ---------------------------------------------------------------------------
// View models
// ---------------------------------------------------------------------------

/// What the inbox is showing. The unread filter is a read-side concern, so it
/// is a repository argument rather than a client-side `where`: the server can
/// page unread rows without shipping the read ones.
enum NotificationFilter {
  all('All'),
  unread('Unread');

  const NotificationFilter(this.label);
  final String label;
}

/// A page of inbox rows plus the freshness metadata every state depends on.
class NotificationPage {
  final List<CallNotification> notifications;
  final String? nextCursor;

  /// Unix ms the server produced this page. Drives the "stale" treatment.
  final int servedAt;

  /// Unread across the WHOLE inbox, not just this page — the header badge has
  /// to be right on page one.
  final int unreadCount;

  /// True when this came from a local cache because the network was not
  /// reachable. The UI must say so rather than present it as live.
  final bool fromCache;

  const NotificationPage({
    required this.notifications,
    required this.servedAt,
    required this.unreadCount,
    this.nextCursor,
    this.fromCache = false,
  });

  static const NotificationPage empty = NotificationPage(
    notifications: [],
    servedAt: 0,
    unreadCount: 0,
  );
}

// ---------------------------------------------------------------------------
// The interface
// ---------------------------------------------------------------------------

abstract class NotificationsRepository {
  /// The viewer's inbox, newest first.
  ///
  /// Throws [NotificationsSignedOutException] when [viewerUserId] is null:
  /// there is no such thing as an anonymous inbox, and returning an empty list
  /// instead would render "you're all caught up" to someone who simply is not
  /// signed in.
  Future<NotificationPage> fetchNotifications({
    required String? viewerUserId,
    NotificationFilter filter = NotificationFilter.all,
    String? cursor,
    int limit = 20,
  });

  /// Unread across the whole inbox. Cheap enough for the header badge to poll.
  Future<int> unreadCount({required String? viewerUserId});

  /// Marks one row read. Idempotent.
  Future<void> markRead({
    required String? viewerUserId,
    required String notificationId,
  });

  /// Marks everything read. Idempotent.
  Future<void> markAllRead({required String? viewerUserId});
}
