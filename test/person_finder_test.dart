/// `people.find` on the wire, and the provider's follow-by-id behind Add a
/// friend. Driven by [FakeBffServer]; no test here opens a socket, and no
/// request carries a wallet field, a signature or a viewer id.
library;

import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/data/person_finder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';
import 'people_layer_bff_test.dart' show recordJson;

const String kBase = 'https://bff.test.invalid';
const String kPic = 'https://pbs.twimg.com/profile_images/1/irfan_400x400.jpg';

BffCallsRepository build(FakeBffServer server, {String? token = 'tok'}) =>
    BffCallsRepository(
      baseUrl: kBase,
      httpClient: server.client,
      authToken: token == null ? null : () => token,
      linkHost: 'https://chumbucket.fun',
      verbose: false,
    );

Map<String, dynamic> matchJson({
  String id = 'user_irfan',
  bool following = false,
  Object? xHandle = 'Irfan',
  Object? xAvatarUrl = kPic,
  Object? avatarId = 3,
  bool isViewer = false,
  String matchedBy = 'x',
}) => {
  'person': {
    'id': id,
    'handle': 'irfan_calls',
    'displayName': 'Irfan',
    'avatarUrl': null,
    'avatarId': avatarId,
    'record': recordJson(correct: 3, incorrect: 1),
    'viewerIsFollowing': following,
  },
  'matchedBy': matchedBy,
  'xHandle': xHandle,
  'xAvatarUrl': xAvatarUrl,
  'isViewer': isViewer,
};

Map<String, dynamic> lookupJson({
  String kind = 'handle',
  List<Map<String, dynamic>>? matches,
  Map<String, dynamic>? notOnChumbucket,
}) => {
  'kind': kind,
  'handle': 'irfan',
  'matches': matches ?? [matchJson()],
  'notOnChumbucket': notOnChumbucket,
  'servedAt': kNowMs,
};

void main() {
  group('PersonLookup.fromJson', () {
    test('a match: card, record, X account, pictures best first', () {
      final lookup = PersonLookup.fromJson(lookupJson());
      expect(lookup.kind, PersonLookupKind.handle);
      expect(lookup.handle, 'irfan');
      final m = lookup.matches.single;
      expect(m.person.id, 'user_irfan');
      expect(m.person.record.decided, 4);
      expect(m.matchedBy, PersonMatchedBy.x);
      expect(m.xHandle, 'Irfan');
      expect(m.isFollowing, isFalse);
      // X photo, then the avatar they chose.
      expect(m.pictures, [kPic, 'assets/images/ai_gen/profile_images/3.png']);
      expect(lookup.notOnChumbucket, isNull);
    });

    test('a picture that is not https, or a malformed handle, is dropped', () {
      final m =
          PersonLookup.fromJson(
            lookupJson(
              matches: [
                matchJson(
                  xAvatarUrl: 'http://pbs.twimg.com/a.jpg',
                  xHandle: 'not a handle',
                  avatarId: 9,
                ),
              ],
            ),
          ).matches.single;
      expect(m.xAvatarUrl, isNull);
      expect(m.xHandle, isNull);
      expect(m.pictures, isEmpty);
    });

    test('nobody: the X handle to invite, picture only when found', () {
      final lookup = PersonLookup.fromJson(
        lookupJson(
          matches: [],
          notOnChumbucket: {'xHandle': 'vitalik', 'xAvatarUrl': null},
        ),
      );
      expect(lookup.isEmpty, isTrue);
      expect(lookup.notOnChumbucket!.xHandle, 'vitalik');
      expect(lookup.notOnChumbucket!.xAvatarUrl, isNull);
    });

    test('an unknown kind or match is drift, not a default', () {
      expect(
        () => PersonLookup.fromJson(lookupJson(kind: 'email')),
        throwsA(isA<CallVocabularyException>()),
      );
      expect(
        () => PersonLookup.fromJson(
          lookupJson(matches: [matchJson(matchedBy: 'email')]),
        ),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  });

  group('BffCallsRepository.findPerson', () {
    test(
      'POSTs the query in the body: nothing in the URL, no wallet field',
      () async {
        final server = FakeBffServer.routes({'people.find': lookupJson()});
        const wallet = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
        await build(server).findPerson('  $wallet ');
        final request = server.lastRequest;
        expect(request.method, 'POST');
        expect(request.procedurePath, 'people.find');
        expect(request.url.query, isEmpty);
        expect(request.input, {'query': wallet});
        expect(
          collectJsonKeys(request.envelope).intersection(kForbiddenRequestKeys),
          isEmpty,
        );
        expect(request.headers['authorization'], 'Bearer tok');
      },
    );

    test('an empty query never leaves the phone', () async {
      final server = FakeBffServer.routes({'people.find': lookupJson()});
      await expectLater(
        build(server).findPerson('   '),
        throwsA(isA<CallsRejectedException>()),
      );
      expect(server.received, isEmpty);
    });

    test('a server without people.find says so', () async {
      // tRPC's own words for a path it does not serve.
      final server = FakeBffServer.failing(
        code: 'NOT_FOUND',
        httpStatus: 404,
        message: 'No "mutation"-procedure on path "people.find"',
      );
      await expectLater(
        build(server).findPerson('@irfan'),
        throwsA(isA<PersonFinderUnavailable>()),
      );
    });

    test('signed out, and refusals worded by the server', () async {
      await expectLater(
        build(
          FakeBffServer.failing(code: 'UNAUTHORIZED', httpStatus: 401),
          token: null,
        ).findPerson('@irfan'),
        throwsA(isA<CallsSignedOutException>()),
      );
      await expectLater(
        build(
          FakeBffServer.failing(
            code: 'SERVICE_UNAVAILABLE',
            httpStatus: 503,
            message:
                "We couldn't look that up right now. Try again in a moment.",
          ),
        ).findPerson('@irfan'),
        throwsA(
          isA<CallsFailure>().having(
            (e) => e.message,
            'message',
            "We couldn't look that up right now. Try again in a moment.",
          ),
        ),
      );
    });
  });

  group('CallsProvider', () {
    test('findPerson needs a session and a server that can look', () async {
      final server = FakeBffServer.routes({'people.find': lookupJson()});
      final provider = CallsProvider(repository: build(server));
      addTearDown(provider.dispose);
      expect(provider.supportsPersonFinder, isTrue);
      await expectLater(
        provider.findPerson('@irfan'),
        throwsA(isA<CallsSignedOutException>()),
      );
      expect(server.received, isEmpty);
      provider.setViewer('user_me');
      expect((await provider.findPerson('@irfan')).matches, hasLength(1));

      final mock = CallsProvider(repository: MockCallsRepository())
        ..setViewer('user_me');
      addTearDown(mock.dispose);
      expect(mock.supportsPersonFinder, isFalse);
      await expectLater(
        mock.findPerson('@irfan'),
        throwsA(isA<PersonFinderUnavailable>()),
      );
    });

    test('a lookup answered after the account changed is discarded', () async {
      late CallsProvider provider;
      final server = FakeBffServer((request) {
        provider.setViewer('user_other');
        return okResponse(lookupJson());
      });
      provider = CallsProvider(repository: build(server))..setViewer('user_me');
      addTearDown(provider.dispose);
      await expectLater(
        provider.findPerson('@irfan'),
        throwsA(
          isA<CallsRejectedException>().having(
            (e) => e.message,
            'message',
            contains('Your account changed'),
          ),
        ),
      );
    });

    test('setFollowingById: one durable follow, no signature; the follow list '
        'is read again', () async {
      final server = FakeBffServer.routes({
        'people.follow': {'personId': 'user_irfan', 'following': true},
        'people.unfollow': {'personId': 'user_irfan', 'following': false},
        'people.following': {'people': []},
        'calls.feed': feedPageJson(entries: []),
      });
      final provider = CallsProvider(repository: build(server))
        ..setViewer('user_me');
      addTearDown(provider.dispose);
      await provider.loadFollowing();
      expect(provider.following, isEmpty);

      expect(await provider.setFollowingById('user_irfan', true), isTrue);
      final follow = server.requestFor('people.follow');
      expect(follow.method, 'POST');
      expect(follow.input, {'personRef': 'user_irfan'});
      expect(
        collectJsonKeys(follow.envelope).intersection(kForbiddenRequestKeys),
        isEmpty,
      );
      // Dropped, to be read again when Following is next shown.
      expect(provider.following, isNull);
      expect(provider.isFollowBusy('user_irfan'), isFalse);

      expect(await provider.setFollowingById('user_irfan', false), isFalse);
      expect(server.requestFor('people.unfollow').input, {
        'personRef': 'user_irfan',
      });
    });

    test('setFollowingById refuses yourself and a signed-out caller', () async {
      final server = FakeBffServer.routes({});
      final provider = CallsProvider(repository: build(server));
      addTearDown(provider.dispose);
      await expectLater(
        provider.setFollowingById('user_irfan', true),
        throwsA(isA<CallsSignedOutException>()),
      );
      provider.setViewer('user_me');
      await expectLater(
        provider.setFollowingById('user_me', true),
        throwsA(isA<CallsRejectedException>()),
      );
      expect(server.received, isEmpty);
    });
  });
}
