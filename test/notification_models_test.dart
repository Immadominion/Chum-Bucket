/// The notification vocabulary: wire fidelity, targets, and the copy rules the
/// pivot will not bend on.
library;

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

const NotificationActor ada = NotificationActor(
  id: 'user_ada',
  handle: 'ada',
  displayName: 'Ada Okafor',
);

CallNotification build({
  required CallNotificationKind kind,
  NotificationActor? actor,
  CallOutcome? outcome,
  CallNotificationTarget? target,
  bool isUnread = true,
}) => CallNotification(
  id: 'notif_1',
  recipientUserId: 'user_you',
  kind: kind,
  actor: actor,
  title: CallNotificationCopy.title(kind: kind, actor: actor, outcome: outcome),
  body: CallNotificationCopy.body(
    kind: kind,
    marketQuestion: 'Will it rain?',
    actor: actor,
    outcome: outcome,
  ),
  createdAt: 1700000000000,
  isUnread: isUnread,
  target: target ?? const NotificationCallTarget('call_1'),
  subjectCallId: 'call_1',
  outcome: outcome,
);

void main() {
  group('kinds', () {
    test('there are exactly four, and they are the relational ones', () {
      expect(CallNotificationKind.values.length, 4);
      expect(
        CallNotificationKind.values.map((k) => k.wire).toList(),
        ['CALL_BACKED', 'CALL_FADED', 'CALL_RESOLVED', 'REMATCH_AVAILABLE'],
      );
    });

    test('every wire value round-trips', () {
      for (final kind in CallNotificationKind.values) {
        expect(CallNotificationKind.fromWire(kind.wire), kind);
      }
    });

    test('an unknown wire value fails loudly rather than being coerced', () {
      expect(
        () => CallNotificationKind.fromWire('CALL_LIQUIDATED'),
        throwsA(isA<NotificationVocabularyException>()),
      );
    });

    test('only a resolution has no actor — the venue is not a person', () {
      expect(CallNotificationKind.resolved.hasActor, isFalse);
      expect(CallNotificationKind.backed.hasActor, isTrue);
      expect(CallNotificationKind.faded.hasActor, isTrue);
      expect(CallNotificationKind.rematch.hasActor, isTrue);
    });
  });

  group('targets', () {
    test('all three round-trip through JSON', () {
      final targets = <CallNotificationTarget>[
        const NotificationCallTarget('call_9'),
        const NotificationReceiptTarget('call_9'),
        const NotificationPersonTarget('ada'),
      ];
      for (final target in targets) {
        expect(CallNotificationTarget.fromJson(target.toJson()), target);
      }
    });

    test('a call target and a receipt target are not the same thing', () {
      expect(
        const NotificationCallTarget('call_9'),
        isNot(const NotificationReceiptTarget('call_9')),
      );
    });

    test('an unknown target type fails loudly', () {
      expect(
        () => CallNotificationTarget.fromJson({'type': 'wallet'}),
        throwsA(isA<NotificationVocabularyException>()),
      );
    });
  });

  group('the notification', () {
    test('round-trips through JSON with every field intact', () {
      final original = build(
        kind: CallNotificationKind.resolved,
        outcome: CallOutcome.voided,
        target: const NotificationReceiptTarget('call_1'),
        isUnread: false,
      );
      final restored = CallNotification.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.kind, original.kind);
      expect(restored.actor, isNull);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.createdAt, original.createdAt);
      expect(restored.isUnread, isFalse);
      expect(restored.target, original.target);
      expect(restored.outcome, CallOutcome.voided);
    });

    test('a float timestamp is rejected, not silently truncated', () {
      final json = build(kind: CallNotificationKind.backed, actor: ada).toJson();
      json['createdAt'] = 1700000000000.5;
      expect(
        () => CallNotification.fromJson(json),
        throwsA(isA<NotificationVocabularyException>()),
      );
    });

    test('the actor avatar taps through to that person, and only then', () {
      expect(
        build(kind: CallNotificationKind.backed, actor: ada).actorTarget,
        const NotificationPersonTarget('user_ada'),
      );
      expect(
        build(
          kind: CallNotificationKind.resolved,
          outcome: CallOutcome.correct,
        ).actorTarget,
        isNull,
      );
    });

    test('marking read changes only the read flag', () {
      final unread = build(kind: CallNotificationKind.backed, actor: ada);
      final read = unread.copyWith(isUnread: false);
      expect(read.isUnread, isFalse);
      expect(read.id, unread.id);
      expect(read.title, unread.title);
      expect(read.target, unread.target);
    });

    test('an actor with one name still yields initials', () {
      const zed = NotificationActor(
        id: 'user_zed',
        handle: 'zed',
        displayName: 'Zed',
      );
      expect(zed.initials, 'Z');
      expect(ada.initials, 'AO');
    });
  });

  group('copy', () {
    test('Back is described as their own call, never as a copy of yours', () {
      final body = CallNotificationCopy.body(
        kind: CallNotificationKind.backed,
        marketQuestion: 'Will it rain?',
        actor: ada,
      );
      expect(body, contains('their own call'));
      expect(body, contains('not a copy of yours'));
    });

    test('Fade is their own call too, not a move against you', () {
      final body = CallNotificationCopy.body(
        kind: CallNotificationKind.faded,
        marketQuestion: 'Will it rain?',
        actor: ada,
      );
      expect(body, contains('their own call'));
      expect(body, contains('under their own name'));
    });

    test('a rematch says out loud that nothing is at stake', () {
      final body = CallNotificationCopy.body(
        kind: CallNotificationKind.rematch,
        marketQuestion: 'Will it rain?',
        actor: ada,
      );
      expect(body, contains('no stake'));
      expect(body, contains('no escrow'));
      expect(body, contains('nothing to fund'));
    });

    test('a void resolution is neither a win nor a loss, in those words', () {
      final title = CallNotificationCopy.title(
        kind: CallNotificationKind.resolved,
        outcome: CallOutcome.voided,
      );
      final body = CallNotificationCopy.body(
        kind: CallNotificationKind.resolved,
        marketQuestion: 'Will it rain?',
        outcome: CallOutcome.voided,
      );
      expect(title, 'Your call was voided');
      expect(body, contains('neither a win nor a loss'));
      expect(body, contains('stays off your accuracy'));
    });

    test('a miss is named a miss, not softened away', () {
      expect(
        CallNotificationCopy.title(
          kind: CallNotificationKind.resolved,
          outcome: CallOutcome.incorrect,
        ),
        'Your call was incorrect',
      );
      expect(
        CallNotificationCopy.body(
          kind: CallNotificationKind.resolved,
          marketQuestion: 'Will it rain?',
          outcome: CallOutcome.incorrect,
        ),
        contains('The miss is on your record too'),
      );
    });

    test('no notification copy carries money or crowd pressure', () {
      // Every kind crossed with every outcome, so nothing slips in on a branch
      // that is rarely rendered.
      const banned = [
        r'$',
        'stake of',
        'wager',
        'odds',
        'payout',
        'balance',
        'everyone',
        'people are',
        'trending',
        'hurry',
        'last chance',
        'don\'t miss',
      ];
      for (final kind in CallNotificationKind.values) {
        for (final outcome in [null, ...CallOutcome.values]) {
          final title = CallNotificationCopy.title(
            kind: kind,
            actor: ada,
            outcome: outcome,
          );
          final body = CallNotificationCopy.body(
            kind: kind,
            marketQuestion: 'Will it rain?',
            actor: ada,
            outcome: outcome,
          );
          for (final word in banned) {
            expect(
              title.toLowerCase(),
              isNot(contains(word)),
              reason: '$kind/$outcome title contains "$word"',
            );
            expect(
              body.toLowerCase(),
              isNot(contains(word)),
              reason: '$kind/$outcome body contains "$word"',
            );
          }
        }
      }
    });

    test('copy never invents a person when there is no actor', () {
      final title = CallNotificationCopy.title(
        kind: CallNotificationKind.rematch,
      );
      expect(title, 'Someone wants a rematch');
    });
  });
}
