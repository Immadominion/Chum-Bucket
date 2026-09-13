/// In-memory [NotificationsRepository]. This is the implementation the return
/// loop ships on until a BFF notification route exists.
///
/// It is not a stub: it enforces the same rules the server will. An inbox is
/// personal, so reading one without a signed-in user throws rather than
/// rendering "all caught up"; read state is owned here and `markRead` is
/// idempotent; the unread count is computed across the whole inbox rather than
/// across the current page; and every seeded row points at a call that
/// actually exists in [MockCallsRepository], so tapping one in the running app
/// opens real content instead of a dead end.
///
/// The seed deliberately covers every state the inbox has to render: all four
/// [CallNotificationKind] values, a read row alongside unread ones, an actor-
/// less row (a resolution has no actor — the venue is not a person), and every
/// one of the three [CallNotificationTarget] destinations.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';

class MockNotificationsRepository implements NotificationsRepository {
  MockNotificationsRepository({
    DateTime Function()? clock,
    this.latency = Duration.zero,
    this.viewerUserId = MockCallsRepository.demoViewerUserId,
  }) : _clock = clock ?? DateTime.now {
    _seed();
  }

  final DateTime Function() _clock;

  /// Whose inbox this mock holds. Defaults to the same demo person
  /// `MockCallsRepository` signs in, so the two seeds line up.
  final String viewerUserId;

  /// Artificial delay so the loading state is reachable in the running app.
  /// Tests construct with [Duration.zero].
  final Duration latency;

  /// Flip to make every call throw [NotificationsOfflineException] — the
  /// offline state is reachable from tests and from a debug affordance.
  bool simulateOffline = false;

  /// Flip to make every call throw [NotificationsFailure].
  bool simulateFailure = false;

  final List<CallNotification> _notifications = [];
  int _sequence = 0;

  int get _nowMs => _clock().toUtc().millisecondsSinceEpoch;

  String _nextId() => 'notif_${++_sequence}';

  // Actors mirror `MockCallsRepository`'s people, by canonical id. No wallet
  // appears anywhere in this file.
  static const NotificationActor _ada = NotificationActor(
    id: 'user_ada',
    handle: 'ada',
    displayName: 'Ada Okafor',
  );
  static const NotificationActor _kemi = NotificationActor(
    id: 'user_kemi',
    handle: 'kemi',
    displayName: 'Kemi Balogun',
  );
  static const NotificationActor _zed = NotificationActor(
    id: 'user_zed',
    handle: 'zed',
    displayName: 'Zed',
  );

  static const String _fedQuestion =
      'Did the FOMC cut by 25bp at the September meeting?';
  static const String _btcQuestion =
      'Will BTC trade above \$150,000 before 31 Dec 2026?';

  void _seed() {
    final now = _clock().toUtc();
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;

    // A rematch invitation. Mirrors the `ChallengeInvitation` already seeded in
    // `MockCallsRepository` (`invite_zed_you`): free, and structurally without
    // escrow — there is no amount field on any of these types to carry one.
    _add(
      kind: CallNotificationKind.rematch,
      actor: _zed,
      marketQuestion: _btcQuestion,
      target: const NotificationCallTarget('call_you_fed'),
      subjectCallId: 'call_you_fed',
      createdAt: ago(const Duration(hours: 2)),
      isUnread: true,
    );

    // The venue published a result. No actor: only the BFF synchroniser, from
    // venue evidence, may produce a resolution (contract invariant 2).
    _add(
      kind: CallNotificationKind.resolved,
      actor: null,
      marketQuestion: _fedQuestion,
      outcome: CallOutcome.correct,
      target: const NotificationReceiptTarget('call_you_fed'),
      subjectCallId: 'call_you_fed',
      createdAt: ago(const Duration(days: 5)),
      isUnread: true,
    );

    // Somebody backed the viewer's call.
    _add(
      kind: CallNotificationKind.backed,
      actor: _ada,
      marketQuestion: _fedQuestion,
      target: const NotificationCallTarget('call_you_fed'),
      subjectCallId: 'call_you_fed',
      createdAt: ago(const Duration(days: 6)),
      isUnread: true,
    );

    // …and somebody faded it. Already read, so the read treatment is reachable
    // without touching anything first.
    _add(
      kind: CallNotificationKind.faded,
      actor: _kemi,
      marketQuestion: _fedQuestion,
      target: const NotificationCallTarget('call_you_fed'),
      subjectCallId: 'call_you_fed',
      createdAt: ago(const Duration(days: 7)),
      isUnread: false,
    );
  }

  void _add({
    required CallNotificationKind kind,
    required NotificationActor? actor,
    required String marketQuestion,
    required CallNotificationTarget target,
    required int createdAt,
    required bool isUnread,
    String? subjectCallId,
    CallOutcome? outcome,
  }) {
    _notifications.add(
      CallNotification(
        id: _nextId(),
        recipientUserId: viewerUserId,
        kind: kind,
        actor: actor,
        // Copy is derived, never hand-written per row, so the mock cannot
        // drift from the rules `CallNotificationCopy` enforces.
        title: CallNotificationCopy.title(
          kind: kind,
          actor: actor,
          outcome: outcome,
        ),
        body: CallNotificationCopy.body(
          kind: kind,
          marketQuestion: marketQuestion,
          actor: actor,
          outcome: outcome,
        ),
        createdAt: createdAt,
        isUnread: isUnread,
        target: target,
        subjectCallId: subjectCallId,
        outcome: outcome,
      ),
    );
  }

  Future<void> _gate() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (simulateOffline) throw const NotificationsOfflineException();
    if (simulateFailure) throw const NotificationsFailure();
  }

  String _requireViewer(String? viewerId) {
    if (viewerId == null || viewerId.isEmpty) {
      throw const NotificationsSignedOutException();
    }
    return viewerId;
  }

  List<CallNotification> _inboxFor(String viewerId) =>
      _notifications.where((n) => n.recipientUserId == viewerId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // -------------------------------------------------------------------------
  // NotificationsRepository
  // -------------------------------------------------------------------------

  @override
  Future<NotificationPage> fetchNotifications({
    required String? viewerUserId,
    NotificationFilter filter = NotificationFilter.all,
    String? cursor,
    int limit = 20,
  }) async {
    await _gate();
    final viewerId = _requireViewer(viewerUserId);

    final inbox = _inboxFor(viewerId);
    final filtered =
        filter == NotificationFilter.unread
            ? inbox.where((n) => n.isUnread).toList(growable: false)
            : inbox;

    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final slice = filtered.skip(start).take(limit).toList(growable: false);
    final nextIndex = start + slice.length;

    return NotificationPage(
      notifications: slice,
      nextCursor: nextIndex < filtered.length ? '$nextIndex' : null,
      servedAt: _nowMs,
      // Across the whole inbox, not the filtered page.
      unreadCount: inbox.where((n) => n.isUnread).length,
    );
  }

  @override
  Future<int> unreadCount({required String? viewerUserId}) async {
    await _gate();
    final viewerId = _requireViewer(viewerUserId);
    return _inboxFor(viewerId).where((n) => n.isUnread).length;
  }

  @override
  Future<void> markRead({
    required String? viewerUserId,
    required String notificationId,
  }) async {
    await _gate();
    final viewerId = _requireViewer(viewerUserId);
    final index = _notifications.indexWhere(
      (n) => n.id == notificationId && n.recipientUserId == viewerId,
    );
    // Unknown id is a no-op, not an error: marking read is idempotent and a
    // stale row id must never break the inbox.
    if (index < 0) return;
    _notifications[index] = _notifications[index].copyWith(isUnread: false);
  }

  @override
  Future<void> markAllRead({required String? viewerUserId}) async {
    await _gate();
    final viewerId = _requireViewer(viewerUserId);
    for (var i = 0; i < _notifications.length; i++) {
      if (_notifications[i].recipientUserId == viewerId) {
        _notifications[i] = _notifications[i].copyWith(isUnread: false);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Test / demo helpers
  // -------------------------------------------------------------------------

  /// Empty-state helper: drop every seeded row.
  void debugClear() => _notifications.clear();

  /// Push a row that the seed does not cover — a void resolution, a second
  /// recipient, a backdated row. Only tests and the demo affordance call this;
  /// in production a notification is derived server-side from a
  /// `CallResponse` or a `CallResult`, never written by a client.
  void debugAdd({
    required CallNotificationKind kind,
    required String marketQuestion,
    required CallNotificationTarget target,
    NotificationActor? actor,
    CallOutcome? outcome,
    String? subjectCallId,
    String? recipientUserId,
    int? createdAt,
    bool isUnread = true,
  }) {
    final recipient = recipientUserId ?? viewerUserId;
    _notifications.add(
      CallNotification(
        id: _nextId(),
        recipientUserId: recipient,
        kind: kind,
        actor: actor,
        title: CallNotificationCopy.title(
          kind: kind,
          actor: actor,
          outcome: outcome,
        ),
        body: CallNotificationCopy.body(
          kind: kind,
          marketQuestion: marketQuestion,
          actor: actor,
          outcome: outcome,
        ),
        createdAt: createdAt ?? _nowMs,
        isUnread: isUnread,
        target: target,
        subjectCallId: subjectCallId,
        outcome: outcome,
      ),
    );
  }

  List<CallNotification> get debugNotifications =>
      List.unmodifiable(_notifications);
}
