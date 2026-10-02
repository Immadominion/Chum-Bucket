/// The calls inbox, served by the calls BFF (`inbox.*`, Packet F).
///
/// The server derives the recipient from the verified session: no procedure
/// takes a user id or a wallet, so this repository sends none. [viewerUserId]
/// is only the local signed-in guard the [NotificationsRepository] contract
/// asks for, and the recipient written onto each row.
///
/// The server's view (`NotificationView` in the API's
/// `src/notifications/types.ts`) is mapped onto the app's existing
/// [CallNotification] here, so the inbox UI and its tests are unchanged:
///
///   BACKED / FADED          → your call, where the response shows
///   RESOLVED                → the receipt for your call
///   REMATCH (challenge)     → your call
///   REMATCH (rival called)  → the rival's new call
///
/// Title and body are the server's copy, rendered from its frozen, checked
/// table — never rewritten here.
library;

import 'dart:developer' as developer;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';

class BffNotificationsRepository implements NotificationsRepository {
  BffNotificationsRepository({
    CallsBffTransport? transport,
    CallsBffAuthTokenProvider? authToken,
  }) : _transport = transport ?? CallsBffTransport(authToken: authToken);

  final CallsBffTransport _transport;

  static const listPath = 'inbox.list';
  static const unreadCountPath = 'inbox.unreadCount';
  static const markReadPath = 'inbox.markRead';

  @override
  Future<NotificationPage> fetchNotifications({
    required String? viewerUserId,
    NotificationFilter filter = NotificationFilter.all,
    String? cursor,
    int limit = 20,
  }) async {
    final viewer = _requireViewer(viewerUserId);
    final raw = await _call(
      () => _transport.query(listPath, {
        'limit': limit,
        'unreadOnly': filter == NotificationFilter.unread,
        if (cursor != null) 'cursor': cursor,
      }),
    );
    final body = _map(raw, listPath);
    final items = body['items'];
    if (items is! List) {
      throw const NotificationsFailure('The inbox came back incomplete.');
    }
    final notifications = <CallNotification>[];
    for (final item in items) {
      final parsed = notificationFromInboxView(item, recipientUserId: viewer);
      if (parsed != null) notifications.add(parsed);
    }
    return NotificationPage(
      notifications: notifications,
      nextCursor: body['nextCursor'] as String?,
      servedAt: (body['servedAt'] as num?)?.toInt() ?? 0,
      unreadCount: (body['unread'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<int> unreadCount({required String? viewerUserId}) async {
    _requireViewer(viewerUserId);
    final body = _map(
      await _call(() => _transport.query(unreadCountPath)),
      unreadCountPath,
    );
    return (body['unread'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> markRead({
    required String? viewerUserId,
    required String notificationId,
  }) async {
    _requireViewer(viewerUserId);
    await _call(
      () => _transport.mutate(markReadPath, {
        'ids': [notificationId],
      }),
    );
  }

  @override
  Future<void> markAllRead({required String? viewerUserId}) async {
    _requireViewer(viewerUserId);
    // `ids` omitted marks everything in the caller's own inbox.
    await _call(() => _transport.mutate(markReadPath, const {}));
  }

  String _requireViewer(String? viewerUserId) {
    if (viewerUserId == null || viewerUserId.isEmpty) {
      throw const NotificationsSignedOutException();
    }
    return viewerUserId;
  }

  Map<String, dynamic> _map(Object? raw, String path) {
    if (raw is Map<String, dynamic>) return raw;
    throw NotificationsFailure('The server sent something unexpected ($path).');
  }

  /// One transport, one error vocabulary: the calls transport's failures
  /// become the inbox's, so the screen keeps its offline / signed-out /
  /// failure states.
  Future<Object?> _call(Future<Object?> Function() run) async {
    try {
      return await run();
    } on CallsSignedOutException {
      throw const NotificationsSignedOutException();
    } on CallsOfflineException {
      throw const NotificationsOfflineException();
    } on CallsRejectedException catch (e) {
      throw NotificationsFailure(e.message);
    } on CallsFailure catch (e) {
      throw NotificationsFailure(e.message);
    }
  }
}

/// One server inbox row as a [CallNotification], or null when the row cannot
/// be read — logged and skipped, so one malformed row never hides the inbox.
CallNotification? notificationFromInboxView(
  Object? raw, {
  required String recipientUserId,
}) {
  if (raw is! Map<String, dynamic>) return null;
  try {
    final kind = switch (raw['kind']) {
      'BACKED' => CallNotificationKind.backed,
      'FADED' => CallNotificationKind.faded,
      'RESOLVED' => CallNotificationKind.resolved,
      'REMATCH' => CallNotificationKind.rematch,
      final other => throw FormatException('unknown kind $other'),
    };
    final subject = raw['subjectCallId'] as String;
    final rival = raw['rivalCallId'] as String?;
    final target = switch (kind) {
      CallNotificationKind.resolved => NotificationReceiptTarget(subject),
      CallNotificationKind.rematch
          when raw['rematchReason'] == 'rival_called_again' && rival != null =>
        NotificationCallTarget(rival),
      _ => NotificationCallTarget(subject),
    };
    final actor = raw['actor'];
    return CallNotification(
      id: raw['id'] as String,
      recipientUserId: recipientUserId,
      kind: kind,
      actor:
          actor is Map<String, dynamic>
              ? NotificationActor(
                id: actor['userId'] as String,
                handle: actor['handle'] as String,
                displayName: actor['displayName'] as String,
                avatarUrl: actor['avatarUrl'] as String?,
              )
              : null,
      title: raw['title'] as String,
      body: raw['body'] as String,
      createdAt: (raw['createdAt'] as num).toInt(),
      isUnread: raw['readAt'] == null,
      target: target,
      subjectCallId: subject,
      outcome:
          raw['outcome'] == null ? null : CallOutcome.fromWire(raw['outcome']),
    );
  } catch (error) {
    developer.log('📣 Inbox: skipped an unreadable row: $error');
    return null;
  }
}
