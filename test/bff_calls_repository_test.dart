/// Round-trip tests for `BffCallsRepository` — the original eight methods plus
/// canonical person Follow/Unfollow against the BFF procedure surface
/// (`docs/contracts/integration-requests/packet-c.md`).
///
/// Every repository here is driven by [FakeBffServer], an injected in-memory
/// `http.Client`. **No test in this file touches the network.**
library;

import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';

const String kBase = 'https://bff.test.invalid';
const String kViewer = 'user_you';

BffCallsRepository build(
  FakeBffServer server, {
  String? token,
  String linkHost = 'https://chumbucket.fun',
}) => BffCallsRepository(
  baseUrl: kBase,
  httpClient: server.client,
  authToken: token == null ? null : () => token,
  linkHost: linkHost,
  verbose: false,
);

void main() {
  group('fetchFeed → calls.feed', () {
    test('round-trips a realistic page', () async {
      final server = FakeBffServer.routes({'calls.feed': feedPageJson()});
      final page = await build(server).fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: kViewer,
      );

      expect(server.lastRequest.method, 'GET');
      expect(server.lastRequest.procedurePath, 'calls.feed');
      expect(server.lastRequest.url.toString(), startsWith('$kBase/calls.feed'));
      expect(server.lastRequest.input, {'mode': 'global', 'limit': 20});

      expect(page.entries, hasLength(1));
      expect(page.nextCursor, '20');
      expect(page.servedAt, kNowMs);
      // A page that came from the BFF is live by definition.
      expect(page.fromCache, isFalse);

      final entry = page.entries.single;
      expect(entry.call.id, 'call_ada_btc');
      expect(entry.call.side, Side.yes);
      expect(entry.call.confidence, 0.7);
      expect(entry.call.fundingState, FundingState.none);
      expect(entry.call.visibility, CallVisibility.public);
      expect(entry.call.createdAt, kNowMs - 3 * kHour);
      expect(entry.author.handle, 'ada');
      expect(entry.author.accuracy, closeTo(19 / 31, 1e-9));
      expect(entry.market.status, MarketStatus.open);
      expect(entry.market.venue, MarketVenue.jupiter);
      expect(entry.market.outcomes.map((o) => o.side), [Side.yes, Side.no]);
      expect(entry.backCount, 2);
      expect(entry.fadeCount, 1);
      expect(entry.viewerHasCalled, isFalse);
      // No result yet → PENDING by the one permitted derivation.
      expect(entry.result, isNull);
      expect(entry.outcome, CallOutcome.pending);
      expect(entry.isShareableReceipt, isFalse);
    });

    test('following mode and a cursor reach the wire', () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson(nextCursor: null),
      });
      final page = await build(server).fetchFeed(
        mode: CallFeedMode.following,
        viewerUserId: kViewer,
        cursor: '40',
        limit: 5,
      );

      expect(server.lastRequest.input, {
        'mode': 'following',
        'cursor': '40',
        'limit': 5,
      });
      expect(page.nextCursor, isNull);
    });

    test('a settled entry carries its service-derived result', () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson(
          entries: [
            feedEntryJson(
              call: callJson(id: 'call_you_fed', userId: kViewer, side: 'YES'),
              result: resultJson(),
              viewerHasCalled: true,
            ),
          ],
          nextCursor: null,
        ),
      });
      final entry = (await build(server).fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: kViewer,
      )).entries.single;

      expect(entry.result!.outcome, CallOutcome.correct);
      expect(entry.result!.resolution, Resolution.yes);
      expect(entry.result!.marketResolutionId, 'res_fomc_sep_2026');
      expect(entry.outcome, CallOutcome.correct);
      expect(entry.isShareableReceipt, isTrue);
      // The client's local derivation must agree exactly with the server's.
      expect(
        deriveCallOutcome(
          side: entry.call.side,
          resolution: entry.result!.resolution,
        ),
        entry.result!.outcome,
      );
    });

    test('an empty feed is an empty page, not a failure', () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson(entries: const [], nextCursor: null),
      });
      final page = await build(server).fetchFeed(mode: CallFeedMode.global);
      expect(page.entries, isEmpty);
      expect(page.servedAt, kNowMs);
    });

    test('reading works with no session at all', () async {
      final server = FakeBffServer.routes({'calls.feed': feedPageJson()});
      final page = await build(server).fetchFeed(mode: CallFeedMode.global);
      expect(page.entries, hasLength(1));
      expect(
        server.lastRequest.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')),
      );
    });
  });

  group('fetchOpenMarkets → markets.open', () {
    test('round-trips a list of markets', () async {
      final server = FakeBffServer.routes({
        'markets.open': [
          marketJson(),
          marketJson(
            id: 'market_sol_flip',
            venue: 'fixture',
            rawStatus: 'demo-open',
          ),
        ],
      });
      final markets = await build(server).fetchOpenMarkets();

      expect(server.lastRequest.method, 'GET');
      expect(server.lastRequest.procedurePath, 'markets.open');
      expect(server.lastRequest.input, isEmpty);

      expect(markets, hasLength(2));
      expect(markets.first.id, 'market_btc_150k');
      expect(markets.first.venueMarketId, 'jup:btc-above-150000-2026-12-31');
      expect(markets.first.rulesText, contains('Coinbase Exchange'));
      expect(markets.first.payloadVersion, 1);
      // A fixture market must stay identifiable as demo (contract §4).
      expect(markets.last.venue, MarketVenue.fixture);
      expect(markets.last.venue.isDemo, isTrue);
    });

    test('category reaches the wire only when given', () async {
      final server = FakeBffServer.routes({'markets.open': const []});
      final repo = build(server);

      await repo.fetchOpenMarkets();
      expect(server.received.last.input, isEmpty);

      await repo.fetchOpenMarkets(category: 'crypto');
      expect(server.received.last.input, {'category': 'crypto'});
    });
  });

  group('fetchMarketDetail → markets.detail', () {
    test('round-trips market, snapshot, viewer call and split', () async {
      final server = FakeBffServer.routes({
        'markets.detail': marketDetailJson(
          viewerCall: feedEntryJson(
            call: callJson(id: 'call_you_btc', userId: kViewer),
            author: personJson(
              id: kViewer,
              handle: 'you',
              displayName: 'You',
              walletAddress: null,
              settledCalls: 4,
              correctCalls: 3,
            ),
            viewerHasCalled: true,
          ),
          crowdSplit: crowdSplitJson(),
        ),
      });
      final detail = await build(server).fetchMarketDetail(
        marketId: 'market_btc_150k',
        viewerUserId: kViewer,
      );

      expect(server.lastRequest.method, 'GET');
      expect(server.lastRequest.input, {'marketId': 'market_btc_150k'});

      expect(detail.market.id, 'market_btc_150k');
      expect(detail.snapshot!.yesProbability, 0.38);
      expect(detail.snapshot!.noProbability, closeTo(0.62, 1e-9));
      expect(detail.snapshot!.source, SnapshotSource.venue);
      expect(detail.snapshot!.id, 'snap_btc_1');
      expect(detail.viewerHasCalled, isTrue);
      expect(detail.viewerCall!.call.id, 'call_you_btc');
      expect(detail.crowdSplit!.yesCalls, 14);
      expect(detail.crowdSplit!.noCalls, 9);
      expect(detail.crowdSplit!.total, 23);
      expect(detail.servedAt, kNowMs);
      expect(detail.fromCache, isFalse);
    });

    test('a market with no snapshot renders without inventing a price', () async {
      final server = FakeBffServer.routes({
        'markets.detail': marketDetailJson(
          market: marketJson(
            id: 'market_paused_depeg',
            status: 'PAUSED',
            rawStatus: 'halted',
          ),
          snapshot: null,
        ),
      });
      final detail = await build(server).fetchMarketDetail(
        marketId: 'market_paused_depeg',
      );

      expect(detail.snapshot, isNull);
      expect(detail.market.status, MarketStatus.paused);
      expect(detail.market.status.acceptsNewCalls, isFalse);
      expect(detail.market.rawStatus, 'halted');
    });
  });

  group('fetchCall → calls.get', () {
    test('round-trips entry, parent and responses', () async {
      final server = FakeBffServer.routes({'calls.get': callDetailJson()});
      final detail = await build(server).fetchCall(
        callId: 'call_kemi_btc_fade',
        viewerUserId: kViewer,
      );

      expect(server.lastRequest.method, 'GET');
      expect(server.lastRequest.input, {'callId': 'call_kemi_btc_fade'});

      expect(detail.entry.call.id, 'call_kemi_btc_fade');
      expect(detail.entry.call.side, Side.no);
      expect(detail.entry.call.parentCallId, 'call_ada_btc');
      expect(detail.parent!.call.id, 'call_ada_btc');
      expect(detail.parent!.call.side, Side.yes);
      expect(detail.responses, hasLength(1));
      expect(detail.responses.single.kind, CallResponseKind.fade);
      expect(detail.responses.single.resultingCallId, 'call_kemi_btc_fade');
      expect(detail.responses.single.kind.createsOwnCall, isTrue);
    });

    test('a call with no parent comes back with none', () async {
      final server = FakeBffServer.routes({
        'calls.get': callDetailJson(
          entry: feedEntryJson(),
          parent: null,
          responses: const [],
        ),
      });
      final detail = await build(server).fetchCall(callId: 'call_ada_btc');
      expect(detail.parent, isNull);
      expect(detail.responses, isEmpty);
    });
  });

  group('fetchPerson → people.get', () {
    test('round-trips a person and their calls', () async {
      final server = FakeBffServer.routes({'people.get': personDetailJson()});
      final detail = await build(server).fetchPerson(
        personRef: 'ada',
        viewerUserId: kViewer,
      );

      expect(server.lastRequest.method, 'GET');
      expect(server.lastRequest.input, {'personRef': 'ada'});

      expect(detail.person.id, 'user_ada');
      expect(detail.person.handle, 'ada');
      expect(detail.person.initials, 'AO');
      expect(detail.person.settledCalls, 31);
      expect(detail.person.accuracy, closeTo(19 / 31, 1e-9));
      expect(detail.calls, hasLength(1));
      expect(detail.viewerIsFollowing, isFalse);
      expect(detail.servedAt, kNowMs);
    });

    test('a leading @ is stripped before it reaches the wire', () async {
      final server = FakeBffServer.routes({'people.get': personDetailJson()});
      await build(server).fetchPerson(personRef: '@ada');
      expect(server.lastRequest.input, {'personRef': 'ada'});
    });

    test('a person with nothing settled reports null accuracy', () async {
      final server = FakeBffServer.routes({
        'people.get': personDetailJson(
          person: personJson(
            id: 'user_tobi',
            handle: 'tobi',
            displayName: 'Tobi Eze',
            walletAddress: null,
            settledCalls: 0,
            correctCalls: 0,
          ),
          calls: const [],
        ),
      });
      final detail = await build(server).fetchPerson(personRef: 'tobi');
      // Never render "0%" for "no data".
      expect(detail.person.accuracy, isNull);
    });
  });

  group('canonical Follow/Unfollow → people.follow/unfollow', () {
    test('sends only the target person, never the actor or a wallet', () async {
      final server = FakeBffServer.routes({
        'people.follow': {'personId': 'user_ada', 'following': true},
        'people.unfollow': {'personId': 'user_ada', 'following': false},
      });
      final repo = build(server, token: 'synthetic-session');
      expect(await repo.setFollowing(
        personId: 'user_ada', following: true, viewerUserId: kViewer,
      ), isTrue);
      expect(await repo.setFollowing(
        personId: 'user_ada', following: false, viewerUserId: kViewer,
      ), isFalse);
      expect(server.received.map((r) => r.procedurePath),
          ['people.follow', 'people.unfollow']);
      for (final request in server.received) {
        expect(request.method, 'POST');
        expect(request.input, {'personRef': 'user_ada'});
        expect(request.headers['authorization'], 'Bearer synthetic-session');
      }
    });

    test('signed out refuses before a request leaves the device', () async {
      final server = FakeBffServer.routes(const {});
      await expectLater(
        build(server).setFollowing(
          personId: 'user_ada', following: true, viewerUserId: null,
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
      expect(server.received, isEmpty);
    });

    test('a mismatched server acknowledgement is loud', () async {
      final server = FakeBffServer.routes({
        'people.follow': {'personId': 'someone_else', 'following': true},
      });
      await expectLater(
        build(server).setFollowing(
          personId: 'user_ada', following: true, viewerUserId: kViewer,
        ),
        throwsA(isA<CallVocabularyException>()),
      );
    });
  });

  group('createCall → calls.create', () {
    test('POSTs CreateCallInput.toJson() verbatim and returns the entry',
        () async {
      final server = FakeBffServer.routes({
        'calls.create': feedEntryJson(
          call: callJson(id: 'call_new', userId: kViewer),
          author: personJson(
            id: kViewer,
            handle: 'you',
            displayName: 'You',
            walletAddress: null,
            settledCalls: 4,
            correctCalls: 3,
          ),
          backCount: 0,
          fadeCount: 0,
          viewerHasCalled: true,
        ),
      });

      const input = CreateCallInput(
        marketId: 'market_btc_150k',
        side: Side.yes,
        confidence: 0.72,
        thesis: 'Exchange supply keeps falling.',
        snapshotId: 'snap_btc_1',
      );
      final entry = await build(
        server,
      ).createCall(input: input, viewerUserId: kViewer);

      expect(server.lastRequest.method, 'POST');
      expect(server.lastRequest.procedurePath, 'calls.create');
      expect(server.lastRequest.input, input.toJson());
      expect(server.lastRequest.envelope.keys, ['json']);

      expect(entry.call.id, 'call_new');
      expect(entry.call.userId, kViewer);
      expect(entry.call.fundingState, FundingState.none);
      expect(entry.viewerHasCalled, isTrue);
    });

    test('signed out throws before any request is sent', () async {
      final server = FakeBffServer.routes({'calls.create': feedEntryJson()});
      await expectLater(
        build(server).createCall(
          input: const CreateCallInput(
            marketId: 'market_btc_150k',
            side: Side.yes,
          ),
          viewerUserId: null,
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
      expect(server.received, isEmpty);
    });

    test('an over-long thesis is refused locally, not sent', () async {
      final server = FakeBffServer.routes({'calls.create': feedEntryJson()});
      await expectLater(
        build(server).createCall(
          input: CreateCallInput(
            marketId: 'market_btc_150k',
            side: Side.yes,
            thesis: 'x' * (kThesisMaxLength + 1),
          ),
          viewerUserId: kViewer,
        ),
        throwsA(isA<CallsRejectedException>()),
      );
      expect(server.received, isEmpty);
    });
  });

  group('respondToCall → calls.respond', () {
    test('a fade mints the actor\'s own call on the opposite side', () async {
      final server = FakeBffServer.routes({
        'calls.respond': responseResultJson(),
      });
      const input = RespondToCallInput(
        targetCallId: 'call_ada_btc',
        kind: CallResponseKind.fade,
        confidence: 0.55,
        thesis: 'The ETF bid is already in the price.',
      );
      final result = await build(
        server,
      ).respondToCall(input: input, viewerUserId: 'user_kemi');

      expect(server.lastRequest.method, 'POST');
      expect(server.lastRequest.input, input.toJson());

      expect(result.response.kind, CallResponseKind.fade);
      expect(result.resultingCall, isNotNull);
      expect(result.resultingCall!.call.side, Side.no);
      expect(result.resultingCall!.call.parentCallId, 'call_ada_btc');
      expect(result.response.resultingCallId, result.resultingCall!.call.id);
      expect(result.invitation, isNull);
    });

    test('a back mints the actor\'s own call on the same side', () async {
      final server = FakeBffServer.routes({
        'calls.respond': responseResultJson(
          response: responseJson(
            id: 'response_kemi_back',
            kind: 'back',
            resultingCallId: 'call_kemi_btc_back',
          ),
          resultingCall: feedEntryJson(
            call: callJson(
              id: 'call_kemi_btc_back',
              userId: 'user_kemi',
              side: 'YES',
              parentCallId: 'call_ada_btc',
            ),
            author: personJson(
              id: 'user_kemi',
              handle: 'kemi',
              displayName: 'Kemi Balogun',
              walletAddress: null,
            ),
          ),
        ),
      });
      final result = await build(server).respondToCall(
        input: const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.back,
        ),
        viewerUserId: 'user_kemi',
      );

      expect(result.response.kind, CallResponseKind.back);
      expect(result.resultingCall!.call.side, Side.yes);
      expect(result.invitation, isNull);
    });

    test('a challenge mints no call and carries no escrow', () async {
      final server = FakeBffServer.routes({
        'calls.respond': <String, dynamic>{
          'response': responseJson(
            id: 'response_zed_challenge',
            actorUserId: 'user_zed',
            targetCallId: 'call_you_fed',
            kind: 'challenge',
            resultingCallId: null,
          ),
          'resultingCall': null,
          'invitation': invitationJson(),
        },
      });
      final result = await build(server).respondToCall(
        input: const RespondToCallInput(
          targetCallId: 'call_you_fed',
          kind: CallResponseKind.challenge,
          thesis: 'Rematch. Go on record on BTC.',
        ),
        viewerUserId: 'user_zed',
      );

      expect(result.response.kind, CallResponseKind.challenge);
      expect(result.response.kind.createsOwnCall, isFalse);
      expect(result.resultingCall, isNull);
      expect(result.response.resultingCallId, isNull);
      expect(result.invitation!.id, 'invite_zed_you');
      expect(result.invitation!.note, 'Rematch. Go on record on BTC.');
      // Structurally true — there is no field that could make it false.
      expect(result.invitation!.hasEscrow, isFalse);
    });

    test('signed out throws before any request is sent', () async {
      final server = FakeBffServer.routes({
        'calls.respond': responseResultJson(),
      });
      await expectLater(
        build(server).respondToCall(
          input: const RespondToCallInput(
            targetCallId: 'call_ada_btc',
            kind: CallResponseKind.back,
          ),
          viewerUserId: null,
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
      expect(server.received, isEmpty);
    });
  });

  group('fetchInvitations → calls.invitations', () {
    test('round-trips invitations for the signed-in viewer', () async {
      final server = FakeBffServer.routes({
        'calls.invitations': [invitationJson()],
      });
      final invitations = await build(
        server,
      ).fetchInvitations(viewerUserId: kViewer);

      expect(server.lastRequest.method, 'GET');
      expect(server.lastRequest.procedurePath, 'calls.invitations');
      expect(server.lastRequest.input, isEmpty);

      expect(invitations, hasLength(1));
      expect(invitations.single.toUserId, kViewer);
      expect(invitations.single.fromUserId, 'user_zed');
      expect(invitations.single.sourceCallId, 'call_you_fed');
      expect(invitations.single.hasEscrow, isFalse);
    });

    test('signed out is an empty list and sends nothing', () async {
      final server = FakeBffServer.routes({
        'calls.invitations': [invitationJson()],
      });
      expect(await build(server).fetchInvitations(viewerUserId: null), isEmpty);
      expect(server.received, isEmpty);
    });
  });

  group('share links', () {
    test('are built from the configured host, never a hardcoded one', () {
      final repo = build(
        FakeBffServer.replying(null),
        linkHost: 'https://staging.chumbucket.fun/',
      );
      expect(
        repo.shareLinkForCall('call_ada_btc'),
        'https://staging.chumbucket.fun/c/call_ada_btc',
      );
      expect(
        repo.shareLinkForPerson('@ada'),
        'https://staging.chumbucket.fun/u/ada',
      );
    });
  });

  group('transport', () {
    test('attaches the session as a bearer token, never a body field',
        () async {
      final server = FakeBffServer.routes({'calls.feed': feedPageJson()});
      await build(
        server,
        token: 'session-token-abc',
      ).fetchFeed(mode: CallFeedMode.global, viewerUserId: kViewer);

      final headers = server.lastRequest.headers.map(
        (k, v) => MapEntry(k.toLowerCase(), v),
      );
      expect(headers['authorization'], 'Bearer session-token-abc');
      expect(server.lastRequest.input.containsKey('viewerUserId'), isFalse);
    });

    test('falls back to raw data when the reply is not superjson-wrapped',
        () async {
      final server = FakeBffServer((_) => okResponseUnwrapped([marketJson()]));
      final markets = await build(server).fetchOpenMarkets();
      expect(markets.single.id, 'market_btc_150k');
    });

    test('the base URL is configuration, never a hardcoded host', () {
      expect(build(FakeBffServer.replying(null)).baseUrl, kBase);
      expect(
        BffCallsRepository(
          baseUrl: 'https://bff.test.invalid/',
          httpClient: FakeBffServer.replying(null).client,
          verbose: false,
        ).baseUrl,
        'https://bff.test.invalid',
      );
    });
  });

  group('money never leaves the device', () {
    test('no request from any of the eight methods carries a money, wallet '
        'or transaction field', () async {
      final server = FakeBffServer.routes({
        'calls.feed': feedPageJson(),
        'markets.open': [marketJson()],
        'markets.detail': marketDetailJson(),
        'calls.get': callDetailJson(),
        'people.get': personDetailJson(),
        'calls.create': feedEntryJson(),
        'calls.respond': responseResultJson(),
        'calls.invitations': [invitationJson()],
      });
      final repo = build(server, token: 'session-token-abc');

      await repo.fetchFeed(mode: CallFeedMode.global, viewerUserId: kViewer);
      await repo.fetchOpenMarkets(category: 'crypto');
      await repo.fetchMarketDetail(
        marketId: 'market_btc_150k',
        viewerUserId: kViewer,
      );
      await repo.fetchCall(callId: 'call_ada_btc', viewerUserId: kViewer);
      await repo.fetchPerson(personRef: 'ada', viewerUserId: kViewer);
      await repo.createCall(
        input: const CreateCallInput(
          marketId: 'market_btc_150k',
          side: Side.yes,
          confidence: 0.72,
          thesis: 'Exchange supply keeps falling.',
          snapshotId: 'snap_btc_1',
        ),
        viewerUserId: kViewer,
      );
      await repo.respondToCall(
        input: const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.fade,
        ),
        viewerUserId: 'user_kemi',
      );
      await repo.fetchInvitations(viewerUserId: kViewer);

      // All eight procedures were exercised.
      expect(
        server.received.map((r) => r.procedurePath).toSet(),
        {
          'calls.feed',
          'markets.open',
          'markets.detail',
          'calls.get',
          'people.get',
          'calls.create',
          'calls.respond',
          'calls.invitations',
        },
      );

      for (final request in server.received) {
        final keys = collectJsonKeys(request.input);
        for (final forbidden in kForbiddenRequestKeys) {
          expect(
            keys,
            isNot(contains(forbidden)),
            reason:
                '${request.procedurePath} sent "$forbidden". A call is free '
                'and is not a trade (contract §0 invariant 1).',
          );
        }
        // Identity is proved by the session, never claimed in a body.
        expect(keys, isNot(contains('userid')));
        expect(keys, isNot(contains('vieweruserid')));
      }
    });
  });
}
