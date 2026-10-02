// The calls inbox against the calls BFF's real wire format.
//
// test/fixtures/inbox_page_server.json is an `inbox.list` page produced by the
// API's own code (NotificationsService over the Packet D harness: Ann's call
// backed, faded and challenged, then settled), wrapped in the tRPC envelope.
import 'dart:convert';
import 'dart:io';

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/notifications/data/bff_notifications_repository.dart';
import 'package:chumbucket/features/notifications/data/notification_models.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final page = File('test/fixtures/inbox_page_server.json').readAsStringSync();
  late List<http.Request> requests;

  BffNotificationsRepository repo(
    Future<http.Response> Function(http.Request) handler,
  ) {
    requests = [];
    return BffNotificationsRepository(
      transport: CallsBffTransport(
        baseUrl: 'https://bff.test',
        authToken: () => 'session-token',
        verbose: false,
        httpClient: MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
      ),
    );
  }

  Map<String, dynamic> inputOf(http.Request request) =>
      (jsonDecode(
                request.method == 'GET'
                    ? request.url.queryParameters['input']!
                    : request.body,
              )
              as Map<String, dynamic>)['json']
          as Map<String, dynamic>;

  test('reads the server page onto the existing inbox model', () async {
    final inbox = repo((_) async => http.Response(page, 200));
    final result = await inbox.fetchNotifications(viewerUserId: 'u-ann');

    expect(requests.single.url.path, '/inbox.list');
    expect(requests.single.headers['authorization'], 'Bearer session-token');
    // The recipient is the session; the request never names a person.
    final input = inputOf(requests.single);
    expect(input.keys, unorderedEquals(['limit', 'unreadOnly']));

    expect(result.unreadCount, 4);
    expect(result.nextCursor, isNull);
    final kinds = result.notifications.map((n) => n.kind).toList();
    expect(kinds, [
      CallNotificationKind.resolved,
      CallNotificationKind.rematch,
      CallNotificationKind.faded,
      CallNotificationKind.backed,
    ]);
    for (final n in result.notifications) {
      expect(n.recipientUserId, 'u-ann');
      expect(n.isUnread, isTrue);
      expect(n.title, isNotEmpty);
      expect(n.body, isNotEmpty);
    }

    final resolved = result.notifications[0];
    expect(resolved.actor, isNull);
    expect(resolved.outcome, CallOutcome.correct);
    expect(resolved.target, isA<NotificationReceiptTarget>());
    expect(
      (resolved.target as NotificationReceiptTarget).callId,
      resolved.subjectCallId,
    );

    final backed = result.notifications[3];
    expect(backed.actor?.id, 'u-bob');
    expect(backed.target, isA<NotificationCallTarget>());
    expect(
      (backed.target as NotificationCallTarget).callId,
      backed.subjectCallId,
    );
    // Copy is the server's, verbatim.
    expect(backed.title, 'U-BOB backed your call');
  });

  test(
    'the unread filter is a server argument, and a cursor is passed on',
    () async {
      final inbox = repo((_) async => http.Response(page, 200));
      await inbox.fetchNotifications(
        viewerUserId: 'u-ann',
        filter: NotificationFilter.unread,
        cursor: 'opaque-cursor',
        limit: 5,
      );
      expect(inputOf(requests.single), {
        'limit': 5,
        'unreadOnly': true,
        'cursor': 'opaque-cursor',
      });
    },
  );

  test('unread count and mark read use the session procedures', () async {
    final inbox = repo((request) async {
      if (request.url.path == '/inbox.unreadCount') {
        return http.Response(
          jsonEncode({
            'result': {
              'data': {
                'json': {'unread': 3, 'servedAt': 1},
              },
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'result': {
            'data': {
              'json': {'marked': 1, 'unread': 2},
            },
          },
        }),
        200,
      );
    });
    expect(await inbox.unreadCount(viewerUserId: 'u-ann'), 3);

    await inbox.markRead(viewerUserId: 'u-ann', notificationId: 'notif-001');
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/inbox.markRead');
    expect(inputOf(requests.last), {
      'ids': ['notif-001'],
    });

    await inbox.markAllRead(viewerUserId: 'u-ann');
    expect(inputOf(requests.last), isEmpty);
  });

  test(
    'no session: nothing is sent, and the screen gets its signed-out state',
    () async {
      final inbox = repo((_) async => http.Response(page, 200));
      await expectLater(
        inbox.fetchNotifications(viewerUserId: null),
        throwsA(isA<NotificationsSignedOutException>()),
      );
      expect(requests, isEmpty);
    },
  );

  test('the server refusing the session reads as signed out', () async {
    final inbox = repo(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'json': {
              'message': 'Sign in to see your notifications.',
              'data': {'code': 'UNAUTHORIZED', 'httpStatus': 401},
            },
          },
        }),
        401,
      ),
    );
    await expectLater(
      inbox.fetchNotifications(viewerUserId: 'u-ann'),
      throwsA(isA<NotificationsSignedOutException>()),
    );
  });

  test('one unreadable row is skipped, never the whole inbox', () {
    final items =
        (jsonDecode(page)['result']['data']['json']['items'] as List)
            .cast<Map<String, dynamic>>();
    final broken = {...items.first, 'kind': 'SOMETHING_NEW'};
    expect(notificationFromInboxView(broken, recipientUserId: 'u-ann'), isNull);
    expect(
      notificationFromInboxView(items.last, recipientUserId: 'u-ann'),
      isNotNull,
    );
  });
}
