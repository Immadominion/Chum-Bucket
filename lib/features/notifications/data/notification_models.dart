/// The relational notification vocabulary for the free call loop.
///
/// This is **not** a frozen contract type. `docs/contracts/pivot-contracts-v1.md`
/// §3 freezes `Call`, `CallResponse`, `CallResult` and `ChallengeInvitation`
/// but declares no notification shape, so this file is Packet-G local and is
/// deliberately derived from those frozen types rather than duplicating them:
///
/// * a BACKED / FADED notification is a projection of a [CallResponse],
/// * a RESOLVED notification is a projection of a [CallResult],
/// * a REMATCH notification is a projection of a `challenge` [CallResponse]
///   and its [ChallengeInvitation] — which structurally has no escrow.
///
/// Rules this file exists to enforce:
///
/// * Timestamps are **unix milliseconds, integer, UTC**, exactly as §3 requires
///   of everything else on the wire.
/// * There is **no amount, no stake and no balance field**, and there must
///   never be one. A widget cannot render money it was never handed.
/// * Every notification carries exactly one primary [target], so "tapping a
///   notification opens the thing it refers to" is a type-level guarantee
///   rather than a convention.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';

/// Thrown when a wire value is not a member of one of this file's enums.
/// Loud on purpose, mirroring [CallVocabularyException].
class NotificationVocabularyException implements Exception {
  final String message;
  const NotificationVocabularyException(this.message);
  @override
  String toString() => 'NotificationVocabularyException: $message';
}

Never _unknown(String type, Object? value) =>
    throw NotificationVocabularyException('Unknown $type: "$value"');

int _requireTimestampMs(Object? value, String field) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw NotificationVocabularyException(
    '$field must be unix milliseconds (integer), got "$value"',
  );
}

String _requireString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw NotificationVocabularyException(
    '$field must be a non-empty string, got "$value"',
  );
}

/// The four relational kinds, and only these four.
///
/// Each one is somebody else's action landing on something you already own.
/// There is no "market moved", no "N people are betting", no price alert and
/// no streak nag — none of those is relational and all of them are urgency
/// copy the pivot explicitly refuses.
enum CallNotificationKind {
  /// Somebody made their OWN call on the same side as yours.
  backed('CALL_BACKED', 'Backed'),

  /// Somebody made their OWN call on the opposite side to yours.
  faded('CALL_FADED', 'Faded'),

  /// The venue published a result and your call now has a receipt.
  resolved('CALL_RESOLVED', 'Resolved'),

  /// Somebody offered you a free rematch. No escrow, no stake, no amount.
  rematch('REMATCH_AVAILABLE', 'Rematch');

  const CallNotificationKind(this.wire, this.label);

  /// The exact JSON value. Never lower-cased on the wire.
  final String wire;

  /// Short human label for a row's eyebrow.
  final String label;

  /// True when another person did this to you. A resolution is published by
  /// the venue, so it has no actor (contract invariant 2).
  bool get hasActor => this != CallNotificationKind.resolved;

  static CallNotificationKind fromWire(Object? value) => switch (value) {
    'CALL_BACKED' => CallNotificationKind.backed,
    'CALL_FADED' => CallNotificationKind.faded,
    'CALL_RESOLVED' => CallNotificationKind.resolved,
    'REMATCH_AVAILABLE' => CallNotificationKind.rematch,
    _ => _unknown('CallNotificationKind', value),
  };
}

// ---------------------------------------------------------------------------
// Targets
// ---------------------------------------------------------------------------

/// Where a notification goes when it is tapped.
///
/// Sealed, so a `switch` over it is exhaustive and a new kind of destination
/// cannot be added without every caller being forced to handle it. There are
/// exactly three destinations in this slice: a call, a receipt, a person.
sealed class CallNotificationTarget {
  const CallNotificationTarget();

  Map<String, dynamic> toJson();

  static CallNotificationTarget fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    return switch (type) {
      'call' => NotificationCallTarget(
        _requireString(json['callId'], 'target.callId'),
      ),
      'receipt' => NotificationReceiptTarget(
        _requireString(json['callId'], 'target.callId'),
      ),
      'person' => NotificationPersonTarget(
        _requireString(json['personRef'], 'target.personRef'),
      ),
      _ => _unknown('CallNotificationTarget', type),
    };
  }
}

/// Opens the call detail screen for [callId].
class NotificationCallTarget extends CallNotificationTarget {
  final String callId;
  const NotificationCallTarget(this.callId);

  @override
  Map<String, dynamic> toJson() => {'type': 'call', 'callId': callId};

  @override
  bool operator ==(Object other) =>
      other is NotificationCallTarget && other.callId == callId;

  @override
  int get hashCode => Object.hash('call', callId);

  @override
  String toString() => 'NotificationCallTarget($callId)';
}

/// Opens the receipt for [callId].
///
/// A receipt only exists once the venue has settled the call, so this target is
/// only ever produced for a settled one — [CallNotificationKind.resolved].
class NotificationReceiptTarget extends CallNotificationTarget {
  final String callId;
  const NotificationReceiptTarget(this.callId);

  @override
  Map<String, dynamic> toJson() => {'type': 'receipt', 'callId': callId};

  @override
  bool operator ==(Object other) =>
      other is NotificationReceiptTarget && other.callId == callId;

  @override
  int get hashCode => Object.hash('receipt', callId);

  @override
  String toString() => 'NotificationReceiptTarget($callId)';
}

/// Opens a person's page. [personRef] is a canonical `public.users.id` or a
/// handle — **never** a wallet address.
class NotificationPersonTarget extends CallNotificationTarget {
  final String personRef;
  const NotificationPersonTarget(this.personRef);

  @override
  Map<String, dynamic> toJson() => {'type': 'person', 'personRef': personRef};

  @override
  bool operator ==(Object other) =>
      other is NotificationPersonTarget && other.personRef == personRef;

  @override
  int get hashCode => Object.hash('person', personRef);

  @override
  String toString() => 'NotificationPersonTarget($personRef)';
}

// ---------------------------------------------------------------------------
// The notification
// ---------------------------------------------------------------------------

/// Who did the thing. A minimal projection of the canonical user so a row can
/// draw an avatar without the notification feature depending on the whole
/// person view model.
///
/// [id] is `public.users.id`. There is no wallet field, by construction.
class NotificationActor {
  final String id;
  final String handle;
  final String displayName;
  final String? avatarUrl;

  const NotificationActor({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarUrl,
  });

  /// Same derivation as `Person.initials`, so an avatar looks identical
  /// wherever it is drawn.
  String get initials {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts.first[0]}${parts.last[0]}';
    return parts.first.substring(0, 1);
  }

  factory NotificationActor.fromJson(Map<String, dynamic> json) =>
      NotificationActor(
        id: _requireString(json['id'], 'NotificationActor.id'),
        handle: _requireString(json['handle'], 'NotificationActor.handle'),
        displayName: _requireString(
          json['displayName'],
          'NotificationActor.displayName',
        ),
        avatarUrl: json['avatarUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
  };
}

/// One row of the inbox.
///
/// Renders generically off [title] / [body] / [createdAt] / [isUnread] and
/// branches on [kind] — the same shape `ArenaNotification` already has, so the
/// inbox reads as one app and a future BFF payload maps onto it unchanged.
class CallNotification {
  final String id;

  /// The canonical `public.users.id` this landed on.
  final String recipientUserId;

  final CallNotificationKind kind;

  /// Null for [CallNotificationKind.resolved]: the venue is the only source of
  /// a result, and the venue is not a person (contract invariant 2).
  final NotificationActor? actor;

  final String title;
  final String body;

  /// Unix milliseconds, UTC.
  final int createdAt;

  final bool isUnread;

  /// Where tapping the row goes. Exactly one, always present.
  final CallNotificationTarget target;

  /// The call this is about, when there is one. Display/telemetry only — the
  /// destination is [target].
  final String? subjectCallId;

  /// The settled outcome, for a [CallNotificationKind.resolved] row. Null for
  /// every other kind. Void is rendered as neither a win nor a loss.
  final CallOutcome? outcome;

  const CallNotification({
    required this.id,
    required this.recipientUserId,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.target,
    this.actor,
    this.isUnread = true,
    this.subjectCallId,
    this.outcome,
  });

  DateTime get createdAtUtc =>
      DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true);

  /// Tapping an actor's avatar goes to that person. Null when the venue, not a
  /// person, produced the row.
  NotificationPersonTarget? get actorTarget =>
      actor == null ? null : NotificationPersonTarget(actor!.id);

  CallNotification copyWith({bool? isUnread}) => CallNotification(
    id: id,
    recipientUserId: recipientUserId,
    kind: kind,
    actor: actor,
    title: title,
    body: body,
    createdAt: createdAt,
    isUnread: isUnread ?? this.isUnread,
    target: target,
    subjectCallId: subjectCallId,
    outcome: outcome,
  );

  factory CallNotification.fromJson(Map<String, dynamic> json) =>
      CallNotification(
        id: _requireString(json['id'], 'CallNotification.id'),
        recipientUserId: _requireString(
          json['recipientUserId'],
          'CallNotification.recipientUserId',
        ),
        kind: CallNotificationKind.fromWire(json['kind']),
        actor:
            json['actor'] == null
                ? null
                : NotificationActor.fromJson(
                  json['actor'] as Map<String, dynamic>,
                ),
        title: _requireString(json['title'], 'CallNotification.title'),
        body: _requireString(json['body'], 'CallNotification.body'),
        createdAt: _requireTimestampMs(
          json['createdAt'],
          'CallNotification.createdAt',
        ),
        isUnread: json['isUnread'] as bool? ?? true,
        target: CallNotificationTarget.fromJson(
          json['target'] as Map<String, dynamic>,
        ),
        subjectCallId: json['subjectCallId'] as String?,
        outcome:
            json['outcome'] == null
                ? null
                : CallOutcome.fromWire(json['outcome']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipientUserId': recipientUserId,
    'kind': kind.wire,
    'actor': actor?.toJson(),
    'title': title,
    'body': body,
    'createdAt': createdAt,
    'isUnread': isUnread,
    'target': target.toJson(),
    'subjectCallId': subjectCallId,
    'outcome': outcome?.wire,
  };
}

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

/// The one place notification copy is written.
///
/// It lives beside the model rather than in a widget so that the rules the
/// pivot cares about are enforceable by test rather than by review:
///
/// * Back and Fade are described as the other person's **own** call, never as
///   a copy of yours and never as a position taken against you for money.
/// * A rematch says, in words, that there is no stake and nothing to fund.
/// * `VOID` is spelled out as neither a win nor a loss.
/// * No sentence contains an amount, a balance, a crowd count or a deadline
///   nudge.
class CallNotificationCopy {
  CallNotificationCopy._();

  static String title({
    required CallNotificationKind kind,
    NotificationActor? actor,
    CallOutcome? outcome,
  }) {
    final who = actor?.displayName ?? 'Someone';
    return switch (kind) {
      CallNotificationKind.backed => '$who backed your call',
      CallNotificationKind.faded => '$who faded your call',
      CallNotificationKind.resolved => switch (outcome) {
        CallOutcome.correct => 'Your call was correct',
        CallOutcome.incorrect => 'Your call was incorrect',
        CallOutcome.voided => 'Your call was voided',
        _ => 'Your call has a result',
      },
      CallNotificationKind.rematch => '$who wants a rematch',
    };
  }

  static String body({
    required CallNotificationKind kind,
    required String marketQuestion,
    NotificationActor? actor,
    CallOutcome? outcome,
  }) {
    final who = actor?.displayName ?? 'They';
    return switch (kind) {
      CallNotificationKind.backed =>
        '$who went on record on the same side of "$marketQuestion". '
            'That is their own call, not a copy of yours.',
      CallNotificationKind.faded =>
        '$who went on record on the other side of "$marketQuestion". '
            'That is their own call, made under their own name.',
      CallNotificationKind.resolved => switch (outcome) {
        CallOutcome.voided =>
          'The venue cancelled "$marketQuestion". Void counts as neither a '
              'win nor a loss, and it stays off your accuracy.',
        CallOutcome.correct =>
          'The venue published a result for "$marketQuestion". Your receipt '
              'is ready to share.',
        CallOutcome.incorrect =>
          'The venue published a result for "$marketQuestion". The miss is on '
              'your record too — open the receipt.',
        _ => 'The venue published a result for "$marketQuestion".',
      },
      CallNotificationKind.rematch =>
        '$who asked you to go on record on "$marketQuestion". '
            'Free — no stake, no escrow, nothing to fund.',
    };
  }
}
