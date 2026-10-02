/// Wire tests for the people layer on `BffCallsRepository`: leaderboard,
/// people search, the viewer's following list, top calls and the thesis
/// thread — plus the additive fields on `calls.get` and `people.get`.
///
/// Driven by [FakeBffServer]; no test here opens a socket.
library;

import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_bff_payloads.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';

const String kBase = 'https://bff.test.invalid';

BffCallsRepository build(FakeBffServer server, {String? token = 'tok'}) =>
    BffCallsRepository(
      baseUrl: kBase,
      httpClient: server.client,
      authToken: token == null ? null : () => token,
      linkHost: 'https://chumbucket.app',
      verbose: false,
    );

Map<String, dynamic> recordJson({
  int correct = 4,
  int incorrect = 0,
  int voided = 0,
  int pending = 0,
  double? accuracy,
}) {
  final decided = correct + incorrect;
  return {
    'counts': {
      'correct': correct,
      'incorrect': incorrect,
      'voided': voided,
      'resolved': decided + voided,
      'decided': decided,
      'pending': pending,
    },
    'display':
        accuracy == null
            ? {
              'mode': 'counts',
              'reason': 'A percentage needs at least 10 decided calls.',
              'correct': correct,
              'incorrect': incorrect,
              'voided': voided,
              'decided': decided,
              'pending': pending,
              'minimumDecided': 10,
            }
            : {
              'mode': 'accuracy',
              'accuracy': accuracy,
              'correct': correct,
              'incorrect': incorrect,
              'voided': voided,
              'decided': decided,
              'pending': pending,
              'minimumDecided': 10,
            },
  };
}

Map<String, dynamic> summaryJson(String id, {String? name}) => {
  'id': id,
  'handle': id.replaceFirst('user_', ''),
  'displayName': name ?? id,
  'avatarUrl': null,
};

Map<String, dynamic> leaderboardJson({String window = '30d'}) => {
  'window': window,
  'ranked': [
    {
      'rank': 1,
      'person': summaryJson('user_ace', name: 'Ace Caller'),
      'record': recordJson(correct: 47, incorrect: 3, accuracy: 0.94),
    },
  ],
  'building': [
    {
      'rank': null,
      'person': summaryJson('user_new', name: 'New Caller'),
      'record': recordJson(correct: 4),
    },
  ],
  'viewer': {
    'rank': null,
    'person': summaryJson('user_you', name: 'You'),
    'record': recordJson(correct: 1, incorrect: 1),
    'decidedToRank': 8,
  },
  'minimumDecided': 10,
  'rule': 'Ranked by accuracy on at least 10 calls the venue decided.',
  'servedAt': kNowMs,
};

Map<String, dynamic> topCallJson({
  bool viewerHasCalled = false,
  Map<String, int>? split,
  int responses = 3,
}) => {
  'call': callJson(),
  'author': {
    ...summaryJson('user_ada', name: 'Ada Okafor'),
    'record': recordJson(),
  },
  'market': marketJson(),
  'responses': responses,
  'split': split,
  'viewerHasCalled': viewerHasCalled,
};

void main() {
  test('the live repository offers the people capability', () {
    expect(build(FakeBffServer.replying(null)), isA<PeopleRepository>());
  });

  test(
    'an older server without these paths reads as "not yet", not as a refusal',
    () async {
      final server = FakeBffServer.failing(
        code: 'NOT_FOUND',
        httpStatus: 404,
        message: 'No "query"-procedure on path "people.leaderboard"',
      );
      await expectLater(
        build(server).fetchLeaderboard(window: LeaderboardWindow.all),
        throwsA(
          isA<CallsFailure>().having(
            (e) => e.message,
            'message',
            contains("isn't available on the server yet"),
          ),
        ),
      );
      // A real refusal is still shown verbatim.
      final refused = FakeBffServer.failing(
        code: 'NOT_FOUND',
        httpStatus: 404,
        message: "We couldn't find that call.",
      );
      await expectLater(
        build(refused).appendThesisUpdate(callId: 'c', body: 'x'),
        throwsA(
          isA<CallsRejectedException>().having(
            (e) => e.message,
            'message',
            "We couldn't find that call.",
          ),
        ),
      );
    },
  );

  group('people.leaderboard', () {
    test('asks for a window and never names a viewer', () async {
      final server = FakeBffServer.routes({
        'people.leaderboard': leaderboardJson(),
      });
      final board = await build(
        server,
      ).fetchLeaderboard(window: LeaderboardWindow.month);

      expect(server.lastRequest.method, 'GET');
      expect(server.lastRequest.input, {'window': '30d', 'limit': 50});
      for (final key in kForbiddenRequestKeys) {
        expect(server.lastRequest.input.containsKey(key), isFalse);
      }

      expect(board.ranked.single.rank, 1);
      expect(board.ranked.single.record.accuracy, 0.94);
      expect(board.building.single.rank, isNull);
      // Below the sample: no percentage on the wire, so none here.
      expect(board.building.single.record.accuracy, isNull);
      expect(board.viewer!.person.id, 'user_you');
      expect(board.viewer!.record.decidedToRank, 8);
    });

    test('refuses a ranked row without the accuracy it was ranked on', () {
      final json = leaderboardJson();
      (json['ranked'] as List).first['record'] = recordJson(correct: 4);
      expect(
        () => Leaderboard.fromJson(json),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('refuses a record that drops its misses', () {
      final record = recordJson(correct: 7, incorrect: 3);
      (record['counts'] as Map)['decided'] = 7;
      expect(
        () => PublicRecord.fromJson(record),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('refuses an accuracy below the decided sample', () {
      expect(
        () => PublicRecord.fromJson(recordJson(correct: 4, accuracy: 1)),
        throwsA(isA<CallVocabularyException>()),
      );
    });

    test('refuses an answer for a different window', () async {
      final server = FakeBffServer.routes({
        'people.leaderboard': leaderboardJson(window: '7d'),
      });
      expect(
        build(server).fetchLeaderboard(window: LeaderboardWindow.all),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  });

  group('people.search / people.following', () {
    test('an empty query never leaves the device', () async {
      final server = FakeBffServer.replying({'people': <Object>[]});
      expect(await build(server).searchPeople('   '), isEmpty);
      expect(server.received, isEmpty);
    });

    test('search sends the query and parses cards', () async {
      final server = FakeBffServer.routes({
        'people.search': {
          'query': 'ada',
          'people': [
            {
              ...summaryJson('user_ada', name: 'Ada Okafor'),
              'record': recordJson(),
              'viewerIsFollowing': true,
            },
          ],
          'servedAt': kNowMs,
        },
      });
      final people = await build(server).searchPeople(' ada ');
      expect(server.lastRequest.input, {'query': 'ada', 'limit': 20});
      expect(people.single.viewerIsFollowing, isTrue);
      expect(people.single.record.correct, 4);
    });

    test(
      'following takes no input and a 401 is the signed-out state',
      () async {
        final server = FakeBffServer.failing(
          code: 'UNAUTHORIZED',
          httpStatus: 401,
          message: 'Sign in to do that.',
        );
        await expectLater(
          build(server, token: null).fetchFollowing(),
          throwsA(isA<CallsSignedOutException>()),
        );
        expect(server.lastRequest.input, isEmpty);
      },
    );
  });

  group('calls.top', () {
    test('no split before the viewer has called', () async {
      final server = FakeBffServer.routes({
        'calls.top': {
          'entries': [topCallJson()],
          'servedAt': kNowMs,
        },
      });
      final calls = await build(server).fetchTopCalls();
      expect(server.lastRequest.input, {'limit': 10});
      expect(calls.single.responses, 3);
      expect(calls.single.split, isNull);
      expect(calls.single.author.displayName, 'Ada Okafor');
    });

    test('a split arrives only with the viewer\'s own call', () async {
      final ok = TopCall.fromJson(
        topCallJson(viewerHasCalled: true, split: {'backs': 2, 'fades': 1}),
      );
      expect(ok.split!.backs, 2);
      expect(
        () => TopCall.fromJson(topCallJson(split: {'backs': 2, 'fades': 1})),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  });

  group('the thesis thread', () {
    Map<String, dynamic> updateJson({
      String callId = 'call_ada_btc',
      String author = 'user_ada',
      int at = kNowMs - kHour,
      String body = 'Flows still accelerating.',
    }) => {
      'id': 'upd_$at',
      'callId': callId,
      'authorUserId': author,
      'body': body,
      'createdAt': at,
    };

    test('posts the trimmed body to calls.addUpdate', () async {
      final server = FakeBffServer.routes({'calls.addUpdate': updateJson()});
      final update = await build(server).appendThesisUpdate(
        callId: 'call_ada_btc',
        body: '  Flows still accelerating.  ',
      );
      expect(server.lastRequest.method, 'POST');
      expect(server.lastRequest.input, {
        'callId': 'call_ada_btc',
        'body': 'Flows still accelerating.',
      });
      expect(update.body, 'Flows still accelerating.');
    });

    test('an empty or over-long update never leaves the device', () async {
      final server = FakeBffServer.replying(null);
      final repo = build(server);
      await expectLater(
        repo.appendThesisUpdate(callId: 'c', body: '  '),
        throwsA(isA<CallsRejectedException>()),
      );
      await expectLater(
        repo.appendThesisUpdate(callId: 'c', body: 'x' * 281),
        throwsA(isA<CallsRejectedException>()),
      );
      expect(server.received, isEmpty);
    });

    test('calls.get carries the thread, oldest first', () {
      final detail = callDetailFromJson({
        ...callDetailJson(entry: feedEntryJson(), parent: null),
        'updates': [
          updateJson(at: kNowMs - kHour, body: 'second'),
          updateJson(at: kNowMs - 2 * kHour, body: 'first'),
        ],
        'updatesAvailable': true,
      });
      expect(detail.updates.map((u) => u.body), ['first', 'second']);
      expect(detail.updatesAvailable, isTrue);
      // The original reason is untouched by the thread.
      expect(detail.entry.call.thesis, callJson()['thesis']);
    });

    test('a server without the thread reads as an empty, closed thread', () {
      final detail = callDetailFromJson(
        callDetailJson(entry: feedEntryJson(), parent: null),
      );
      expect(detail.updates, isEmpty);
      expect(detail.updatesAvailable, isFalse);
    });

    test('an update by someone other than the author is refused', () {
      expect(
        () => callDetailFromJson({
          ...callDetailJson(entry: feedEntryJson(), parent: null),
          'updates': [updateJson(author: 'user_mallory')],
          'updatesAvailable': true,
        }),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  });

  group('people.get additions', () {
    test('counts, record, bio and join date when sent', () {
      final detail = personDetailFromJson({
        ...personDetailJson(
          person: {
            ...personJson(),
            'bio': '  Macro and crypto.  ',
            'joinedAt': kNowMs - 200 * kDay,
          },
        ),
        'followerCount': 12,
        'followingCount': 3,
        'record': recordJson(correct: 7, incorrect: 3, accuracy: 0.7),
      });
      expect(detail.followerCount, 12);
      expect(detail.followingCount, 3);
      expect(detail.record!.accuracy, 0.7);
      expect(detail.person.bio, 'Macro and crypto.');
      expect(
        detail.person.joinedAtUtc!.millisecondsSinceEpoch,
        kNowMs - 200 * kDay,
      );
    });

    test('absent stays unknown, never zero', () {
      final detail = personDetailFromJson(personDetailJson());
      expect(detail.followerCount, isNull);
      expect(detail.followingCount, isNull);
      expect(detail.record, isNull);
      expect(detail.person.joinedAt, isNull);
    });
  });
}
