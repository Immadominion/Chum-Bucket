/// State + orchestration for the inbox.
///
/// Registered nowhere yet — the integration owner wires it into `main.dart`
/// (see `docs/contracts/integration-requests/packet-g.md`). It depends on a
/// [NotificationsRepository], not on a transport, so swapping
/// [MockNotificationsRepository] for a BFF implementation changes one
/// constructor argument.
///
/// Shaped after `CallsProvider` on purpose: same `setViewer` cache flush, same
/// offline-keeps-what-is-on-screen rule, same staleness window. The load-state
/// enum is declared here rather than imported from the call slice so this
/// feature owns its own vocabulary and a frozen file stays a read-only
/// dependency.
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';

/// The states the inbox must be able to reach. Mirrors `CallsLoadState`, plus
/// `signedOut` — an inbox is personal, so that is a first-class state here
/// rather than an empty list.
enum NotificationsLoadState {
  /// Nothing requested yet.
  idle,

  /// First load in flight, nothing to show underneath.
  loading,

  /// Loaded and non-empty.
  ready,

  /// Loaded and genuinely empty — not an error.
  empty,

  /// There is no signed-in person, so there is no inbox to show.
  signedOut,

  /// The last attempt failed and there is nothing cached to fall back to.
  error,

  /// No connection. Any content shown alongside this is cached, not live.
  offline,
}

class NotificationsProvider extends ChangeNotifier {
  NotificationsProvider({
    required NotificationsRepository repository,
    DateTime Function()? clock,
    this.staleAfter = const Duration(minutes: 2),
  }) : _repository = repository,
       _clock = clock ?? DateTime.now;

  final NotificationsRepository _repository;
  final DateTime Function() _clock;

  /// How old served data may be before the UI must say so.
  final Duration staleAfter;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  String? _viewerUserId;

  /// The canonical `public.users.id` of the signed-in person, or null.
  /// **Never a wallet.**
  String? get viewerUserId => _viewerUserId;

  bool get isSignedIn => _viewerUserId != null && _viewerUserId!.isNotEmpty;

  /// Called by the shell when the session changes. Clears everything so a
  /// second account never sees the first one's inbox.
  void setViewer(String? userId) {
    if (_viewerUserId == userId) return;
    _viewerUserId = userId;
    _notifications = const [];
    _servedAt = null;
    _nextCursor = null;
    _unreadCount = 0;
    _error = null;
    _isOffline = false;
    _isSignedOut = userId == null;
    _notify();
  }

  // -------------------------------------------------------------------------
  // Inbox
  // -------------------------------------------------------------------------

  NotificationFilter _filter = NotificationFilter.all;
  List<CallNotification> _notifications = const [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isMarkingRead = false;
  String? _error;
  int? _servedAt;
  String? _nextCursor;
  int _unreadCount = 0;
  bool _isOffline = false;
  bool _isSignedOut = false;
  bool _fromCache = false;

  NotificationFilter get filter => _filter;
  List<CallNotification> get notifications => List.unmodifiable(_notifications);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isMarkingRead => _isMarkingRead;
  String? get error => _error;
  bool get hasMore => _nextCursor != null;

  /// Unread across the whole inbox — what the header badge shows.
  int get unreadCount => _unreadCount;

  /// True when the last read failed because the device or BFF was unreachable.
  /// Anything rendered while this is true is cached, and must say so.
  bool get isOffline => _isOffline;

  bool get isFromCache => _fromCache;

  DateTime? get servedAtUtc =>
      _servedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(_servedAt!, isUtc: true);

  /// How old the currently-rendered inbox is. Null before the first success.
  Duration? get age {
    final servedAt = servedAtUtc;
    if (servedAt == null) return null;
    final delta = _clock().toUtc().difference(servedAt);
    return delta.isNegative ? Duration.zero : delta;
  }

  /// Data is on screen but older than [staleAfter]. Not an error.
  bool get isStale {
    final current = age;
    return current != null && current > staleAfter;
  }

  NotificationsLoadState get state {
    if (_isLoading && _notifications.isEmpty) {
      return NotificationsLoadState.loading;
    }
    if (_isSignedOut && _notifications.isEmpty) {
      return NotificationsLoadState.signedOut;
    }
    if (_isOffline && _notifications.isEmpty) {
      return NotificationsLoadState.offline;
    }
    if (_error != null && _notifications.isEmpty) {
      return NotificationsLoadState.error;
    }
    if (_servedAt == null && _notifications.isEmpty) {
      return NotificationsLoadState.idle;
    }
    if (_notifications.isEmpty) return NotificationsLoadState.empty;
    return NotificationsLoadState.ready;
  }

  Future<void> setFilter(NotificationFilter next) async {
    if (_filter == next) return;
    _filter = next;
    _notifications = const [];
    _servedAt = null;
    _nextCursor = null;
    _notify();
    await load(force: true);
  }

  Future<void> load({bool force = false}) async {
    if (_isLoading) return;
    if (!force && _servedAt != null && !isStale) return;

    _isLoading = true;
    _error = null;
    _notify();
    try {
      final page = await _repository.fetchNotifications(
        viewerUserId: _viewerUserId,
        filter: _filter,
      );
      _notifications = page.notifications;
      _servedAt = page.servedAt;
      _nextCursor = page.nextCursor;
      _unreadCount = page.unreadCount;
      _fromCache = page.fromCache;
      _isOffline = false;
      _isSignedOut = false;
    } on NotificationsSignedOutException catch (e) {
      _isSignedOut = true;
      _notifications = const [];
      _unreadCount = 0;
      _error = e.message;
    } on NotificationsOfflineException catch (e) {
      // Keep whatever is already on screen; it is now explicitly cached.
      developer.log('NotificationsProvider.load offline: $e');
      _isOffline = true;
      _fromCache = _notifications.isNotEmpty;
      _error = e.message;
    } on NotificationsException catch (e) {
      developer.log('NotificationsProvider.load failed: $e');
      _error = e.message;
    } catch (e) {
      developer.log('NotificationsProvider.load failed: $e');
      _error = const NotificationsFailure().message;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _isLoadingMore || _isLoading) return;
    _isLoadingMore = true;
    _notify();
    try {
      final page = await _repository.fetchNotifications(
        viewerUserId: _viewerUserId,
        filter: _filter,
        cursor: cursor,
      );
      _notifications = [..._notifications, ...page.notifications];
      _nextCursor = page.nextCursor;
      _unreadCount = page.unreadCount;
      _isOffline = false;
    } on NotificationsOfflineException {
      _isOffline = true;
    } on NotificationsException catch (e) {
      developer.log('NotificationsProvider.loadMore failed: $e');
    } finally {
      _isLoadingMore = false;
      _notify();
    }
  }

  /// Marks one row read. Applied optimistically so opening a notification feels
  /// instant; a failure re-reads rather than leaving the list lying.
  Future<void> markRead(String notificationId) async {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index < 0 || !_notifications[index].isUnread) return;

    final previous = _notifications;
    final previousUnread = _unreadCount;
    final next = [..._notifications];
    next[index] = next[index].copyWith(isUnread: false);
    _notifications = next;
    _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    _notify();

    try {
      await _repository.markRead(
        viewerUserId: _viewerUserId,
        notificationId: notificationId,
      );
      // The unread filter hides a row the moment it is read; re-read so the
      // list on screen matches what the server would return.
      if (_filter == NotificationFilter.unread) await load(force: true);
    } on NotificationsException catch (e) {
      developer.log('NotificationsProvider.markRead failed: $e');
      _notifications = previous;
      _unreadCount = previousUnread;
      _notify();
    }
  }

  Future<void> markAllRead() async {
    if (_isMarkingRead || _unreadCount == 0) return;
    _isMarkingRead = true;
    _notify();
    try {
      await _repository.markAllRead(viewerUserId: _viewerUserId);
      await load(force: true);
    } on NotificationsException catch (e) {
      developer.log('NotificationsProvider.markAllRead failed: $e');
      _error = e.message;
    } finally {
      _isMarkingRead = false;
      _notify();
    }
  }

  /// Just the badge. Safe to call on a signed-out session: it reports zero
  /// rather than throwing, because a badge is not a screen.
  Future<void> refreshUnreadCount() async {
    try {
      _unreadCount = await _repository.unreadCount(
        viewerUserId: _viewerUserId,
      );
    } on NotificationsException catch (e) {
      developer.log('NotificationsProvider.refreshUnreadCount failed: $e');
      _unreadCount = 0;
    }
    _notify();
  }
}
