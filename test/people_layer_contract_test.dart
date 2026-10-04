/// The people layer end to end: the REAL sibling BFF routers and CallsService
/// (over an in-memory store with synthetic data, via
/// test/harness/people_bff_harness.ts) answering the REAL Dart client.
///
/// What hand-written fixtures cannot prove, this does: that the server's
/// actual output for the leaderboard, search, following, top calls, the
/// thesis thread and the enriched person page parses under the client's
/// strict rules — and that the crowd-split and sample gates hold across the
/// wire. Stdio, not localhost HTTP; no credentials, database or network.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_refusals.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_suggestions.dart';
import 'package:chumbucket/features/people/data/person_finder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Pipe {
  _Pipe(this.process) {
    _out = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final message = jsonDecode(line) as Map<String, dynamic>;
          final pending = _pending.remove(message['id']);
          if (message['failed'] == true) {
            pending?.completeError(StateError('Harness refused the request.'));
          } else {
            pending?.complete(message['result'] as Map<String, dynamic>);
          }
        });
    _err = process.stderr.listen((_) {});
  }

  final Process process;
  late final StreamSubscription<String> _out;
  late final StreamSubscription<List<int>> _err;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _seq = 0;

  static Directory? apiRoot() {
    final root = Directory.current.absolute;
    for (final name in ['chumbucket-social-calls-api', 'api']) {
      final dir = Directory('${root.parent.path}/$name');
      if (File('${dir.path}/src/calls/people.ts').existsSync()) return dir;
    }
    return null;
  }

  static Future<_Pipe> start(Directory api) async => _Pipe(
    await Process.start(
      '/opt/homebrew/bin/bun',
      [
        '--no-env-file',
        '${Directory.current.absolute.path}/test/harness/people_bff_harness.ts',
        api.path,
      ],
      workingDirectory: api.path,
      includeParentEnvironment: false,
      environment: {'PATH': '/opt/homebrew/bin:/usr/bin:/bin'},
    ),
  );

  Future<Map<String, dynamic>> request(Map<String, Object?> input) {
    final id = ++_seq;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    process.stdin.writeln(jsonEncode({...input, 'id': id}));
    return completer.future.timeout(const Duration(seconds: 15));
  }

  Future<void> close() async {
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await _out.cancel();
    await _err.cancel();
  }
}

class _PipeClient extends http.BaseClient {
  _PipeClient(this.pipe);
  final _Pipe pipe;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.decode(await request.finalize().toBytes());
    final path =
        request.url.hasQuery
            ? '${request.url.path}?${request.url.query}'
            : request.url.path;
    final response = await pipe.request({
      'method': request.method,
      'path': path,
      'headers': request.headers,
      'body': body,
    });
    return http.StreamedResponse(
      Stream.value(utf8.encode(response['body'] as String)),
      response['status'] as int,
    );
  }
}

void main() {
  final api = _Pipe.apiRoot();
  final bun = File('/opt/homebrew/bin/bun').existsSync();
  final skip =
      api == null || !bun
          ? 'Needs the sibling BFF checkout and bun at /opt/homebrew/bin.'
          : null;

  late _Pipe pipe;
  late String openCallId;

  BffCallsRepository as(String? token) => BffCallsRepository(
    baseUrl: 'https://synthetic.invalid/trpc',
    httpClient: _PipeClient(pipe),
    authToken: token == null ? null : () => token,
    linkHost: 'https://chumbucket.fun',
    verbose: false,
  );

  setUpAll(() async {
    if (skip != null) return;
    pipe = await _Pipe.start(api!);
    openCallId = (await pipe.request({'op': 'meta'}))['openCallId'] as String;
  });

  tearDownAll(() async {
    if (skip == null) await pipe.close();
  });

  test('leaderboard: ranked by record, sample-gated, viewer pinned', () async {
    final board = await as(
      'synthetic-bob',
    ).fetchLeaderboard(window: LeaderboardWindow.all);
    expect(board.ranked.map((r) => r.person.handle), ['ann']);
    expect(board.ranked.single.rank, 1);
    expect(board.ranked.single.record.accuracy, closeTo(10 / 12, 1e-9));
    expect(board.building.map((r) => r.person.handle), ['bob']);
    expect(board.building.single.record.accuracy, isNull);
    expect(board.viewer!.person.handle, 'bob');
    expect(board.viewer!.rank, isNull);
    expect(board.viewer!.record.decidedToRank, 7);

    final signedOut = await as(
      null,
    ).fetchLeaderboard(window: LeaderboardWindow.week);
    expect(signedOut.viewer, isNull);
  }, skip: skip);

  test('top calls: direction-free until the viewer has called', () async {
    final forBob = await as('synthetic-bob').fetchTopCalls();
    final cid = forBob.singleWhere((c) => c.call.id == openCallId);
    // Ann backed and Bob challenged: two responses, no direction for Bob,
    // who only challenged and so has no call on this market.
    expect(cid.responses, 2);
    expect(cid.split, isNull);
    expect(cid.viewerHasCalled, isFalse);

    final forAnn = await as('synthetic-ann').fetchTopCalls();
    final same = forAnn.singleWhere((c) => c.call.id == openCallId);
    expect(same.viewerHasCalled, isTrue);
    expect(same.split!.backs, 1);
    expect(same.split!.fades, 0);
    // Your own call never appears on your own strip.
    expect(forAnn.any((c) => c.author.handle == 'ann'), isFalse);
  }, skip: skip);

  test('search and following', () async {
    final found = await as('synthetic-cid').searchPeople('@an');
    expect(found.map((p) => p.handle), contains('ann'));
    expect(
      found.firstWhere((p) => p.handle == 'ann').viewerIsFollowing,
      isTrue,
    );

    final following = await as('synthetic-cid').fetchFollowing();
    expect(following.map((p) => p.handle), ['ann']);
    await expectLater(
      as(null).fetchFollowing(),
      throwsA(isA<CallsSignedOutException>()),
    );
  }, skip: skip);

  test('the enriched person page parses', () async {
    final detail = await as(
      'synthetic-cid',
    ).fetchPerson(personRef: 'ann', viewerUserId: 'user-cid');
    expect(detail.followerCount, 1);
    expect(detail.followingCount, 0);
    expect(detail.record!.decided, 12);
    expect(detail.record!.accuracy, closeTo(10 / 12, 1e-9));
    expect(detail.person.bio, 'Ann Caller calls crypto.');
    expect(detail.person.joinedAtUtc, isNotNull);
    expect(detail.viewerIsFollowing, isTrue);
  }, skip: skip);

  test(
    'the thesis thread: author-only, appended, original untouched',
    () async {
      final cid = as('synthetic-cid');
      await pipe.request({'op': 'advance', 'millis': 60000});
      final update = await cid.appendThesisUpdate(
        callId: openCallId,
        body: '  Funding flipped overnight.  ',
      );
      expect(update.body, 'Funding flipped overnight.');

      final detail = await as(
        'synthetic-bob',
      ).fetchCall(callId: openCallId, viewerUserId: 'user-bob');
      expect(detail.updatesAvailable, isTrue);
      expect(detail.updates.single.body, 'Funding flipped overnight.');
      expect(detail.entry.call.thesis, 'The original reason.');

      await expectLater(
        as(
          'synthetic-bob',
        ).appendThesisUpdate(callId: openCallId, body: 'Not mine'),
        throwsA(
          isA<CallsRejectedException>().having(
            (e) => e.message,
            'message',
            'Only the person who made this call can add to its thesis.',
          ),
        ),
      );
    },
    skip: skip,
  );

  test('people.suggested: real callers, the server\'s own order, self and '
      'followed left out, parsed by the client', () async {
    final anon = await as(null).fetchSuggestedPeople();
    expect(anon.friends, isEmpty);
    expect(anon.people.map((p) => p.id), ['user-ann', 'user-cid', 'user-bob']);
    expect(anon.people.map((p) => p.reason), [
      SuggestionReason.ranked,
      SuggestionReason.topCall,
      SuggestionReason.building,
    ]);
    // Ann's record arrives with its accuracy; Bob's without one.
    expect(anon.people.first.person.record.hasAccuracy, isTrue);
    expect(anon.people.last.person.record.hasAccuracy, isFalse);
    // Cid's open call is live; it comes with its question and side.
    final cid = anon.people[1];
    expect(cid.latestLiveCall?.callId, openCallId);
    expect(cid.latestLiveCall?.question, '[DEMO] Will open-1 happen?');

    // Cid follows Ann: Ann is not suggested to Cid, nor Cid to himself.
    final mine = await as('synthetic-cid').fetchSuggestedPeople();
    expect(mine.people.map((p) => p.id), isNot(contains('user-ann')));
    expect(mine.people.map((p) => p.id), isNot(contains('user-cid')));
  }, skip: skip);

  test('people.find: the server\'s card parses, and adding is a separate, '
      'signature-free follow', () async {
    final cid = as('synthetic-cid');
    final byX = await cid.findPerson('https://x.com/AnnOnX');
    expect(byX.kind, PersonLookupKind.x);
    final ann = byX.matches.single;
    expect(ann.person.id, 'user-ann');
    expect(ann.person.handle, 'ann');
    expect(ann.matchedBy, PersonMatchedBy.x);
    expect(ann.xHandle, 'AnnOnX');
    expect(
      ann.xAvatarUrl,
      'https://pbs.twimg.com/profile_images/1/ann_400x400.jpg',
    );
    expect(ann.pictures.first, ann.xAvatarUrl);
    // The same record people.get shows, and Cid already follows Ann.
    expect(ann.person.record.decided, 12);
    expect(ann.person.viewerIsFollowing, isTrue);
    expect(ann.isViewer, isFalse);

    final annSide = as('synthetic-ann');
    final bob = (await annSide.findPerson('@bob')).matches.single;
    expect(bob.person.id, 'user-bob');
    expect(bob.matchedBy, PersonMatchedBy.username);
    expect(bob.xHandle, isNull);
    expect(bob.person.viewerIsFollowing, isFalse);

    const bobWallet = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
    final byWallet = await annSide.findPerson(bobWallet);
    expect(byWallet.kind, PersonLookupKind.wallet);
    expect(byWallet.handle, isNull);
    expect(byWallet.matches.single.matchedBy, PersonMatchedBy.wallet);

    final nobody = await cid.findPerson('@nobody_here');
    expect(nobody.matches, isEmpty);
    expect(nobody.notOnChumbucket!.xHandle, 'nobody_here');
    expect(nobody.notOnChumbucket!.xAvatarUrl, isNull);

    expect((await cid.findPerson('@cid')).matches.single.isViewer, isTrue);
    await expectLater(
      as(null).findPerson('@bob'),
      throwsA(isA<CallsSignedOutException>()),
    );
    await expectLater(
      cid.findPerson('alice.skr'),
      throwsA(
        isA<CallsRejectedException>().having(
          (e) => e.message,
          'message',
          'Enter their X handle, Chumbucket @username or Solana wallet.',
        ),
      ),
    );

    // Add friend = follow; the next card says so. Undone after.
    await annSide.setFollowing(
      personId: 'user-bob',
      following: true,
      viewerUserId: 'user-ann',
    );
    final after = await annSide.findPerson('@bob');
    expect(after.matches.single.person.viewerIsFollowing, isTrue);
    await annSide.setFollowing(
      personId: 'user-bob',
      following: false,
      viewerUserId: 'user-ann',
    );
  }, skip: skip);

  // calls.respond as the app sends it (RespondToCallInput.toJson(), nulls
  // included), against the real routers: the refusals behind "Lock just
  // loads" must arrive as words the answer sheet can act on.
  group('answering a call', () {
    test('the author answering their own call is "your own call"', () async {
      await expectLater(
        as('synthetic-cid').respondToCall(
          input: RespondToCallInput(
            targetCallId: openCallId,
            kind: CallResponseKind.fade,
          ),
          viewerUserId: 'user-cid',
        ),
        throwsA(
          isA<CallsRejectedException>()
              .having((e) => e.message, 'message', contains('your own call'))
              .having(classifyCallRefusal, 'refusal', CallRefusal.ownCall),
        ),
      );
    }, skip: skip);

    test('a second call on the same market is "already on record"', () async {
      // Ann backed this call already, so she holds a live call here.
      await expectLater(
        as('synthetic-ann').respondToCall(
          input: RespondToCallInput(
            targetCallId: openCallId,
            kind: CallResponseKind.fade,
          ),
          viewerUserId: 'user-ann',
        ),
        throwsA(
          isA<CallsRejectedException>().having(
            classifyCallRefusal,
            'refusal',
            CallRefusal.alreadyOnRecord,
          ),
        ),
      );
    }, skip: skip);

    // The server keeps a challenge's words in `note` and drops `thesis`: a
    // Dare's message must arrive in the invitation, not vanish.
    test('a Dare\'s words reach the person dared', () async {
      final result = await as('synthetic-ann').respondToCall(
        input: RespondToCallInput(
          targetCallId: openCallId,
          kind: CallResponseKind.challenge,
          note: 'Say it again on Friday.',
        ),
        viewerUserId: 'user-ann',
      );
      expect(result.resultingCall, isNull);
      expect(result.invitation?.note, 'Say it again on Friday.');
    }, skip: skip);

    // Last: it adds a call to the shared harness.
    test(
      'anyone else Fades with the exact payload and gets their own call',
      () async {
        final result = await as('synthetic-bob').respondToCall(
          input: RespondToCallInput(
            targetCallId: openCallId,
            kind: CallResponseKind.fade,
          ),
          viewerUserId: 'user-bob',
        );
        final own = result.resultingCall!.call;
        expect(own.userId, 'user-bob');
        expect(own.side, Side.no);
        expect(own.parentCallId, openCallId);
        expect(result.response.kind, CallResponseKind.fade);
      },
      skip: skip,
    );
  });
}
