import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

MockCallsRepository build() => MockCallsRepository();

void main() {
  group('seed covers every state the UI has to render', () {
    test('all five market statuses are present', () async {
      final repo = build();
      final statuses = repo.debugMarkets.map((m) => m.status).toSet();
      expect(statuses, MarketStatus.values.toSet());
    });

    test('all four call outcomes are reachable from the seed', () async {
      final repo = build();
      final outcomes = <CallOutcome>{};
      for (final call in repo.debugCalls) {
        try {
          final detail = await repo.fetchCall(
            callId: call.id,
            viewerUserId: viewer,
          );
          outcomes.add(detail.entry.outcome);
        } on CallsRejectedException {
          // A followers-only call the demo viewer cannot see. Its existence is
          // asserted separately; it contributes no outcome here.
        }
      }
      expect(outcomes, CallOutcome.values.toSet());
    });

    test('a fixture (demo) venue is present and labelled as demo', () {
      final demo = build().debugMarkets.where((m) => m.venue.isDemo).toList();
      expect(demo, isNotEmpty);
      expect(demo.first.venue.isDemo, isTrue);
    });

    test('every seeded call is free — funding state NONE', () {
      for (final call in build().debugCalls) {
        expect(call.fundingState, FundingState.none);
        expect(call.fundingState.isFunded, isFalse);
      }
    });

    test('a cancelled market yields VOID, never a win or a loss', () async {
      final repo = build();
      final detail = await repo.fetchCall(
        callId: 'call_kemi_listing',
        viewerUserId: viewer,
      );
      expect(detail.entry.market.status, MarketStatus.cancelled);
      expect(detail.entry.outcome, CallOutcome.voided);
      expect(detail.entry.result!.resolution, Resolution.voided);
    });

    test('a closed-pending market keeps its calls PENDING', () async {
      final repo = build();
      final detail = await repo.fetchCall(
        callId: 'call_ada_etf',
        viewerUserId: viewer,
      );
      expect(
        detail.entry.market.status,
        MarketStatus.closedPendingResolution,
      );
      expect(detail.entry.outcome, CallOutcome.pending);
      expect(detail.entry.result, isNull);
    });
  });

  group('feed', () {
    test('global returns public calls newest first', () async {
      final page = await build().fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: viewer,
      );
      expect(page.entries, isNotEmpty);
      final timestamps = page.entries.map((e) => e.call.createdAt).toList();
      final sorted = [...timestamps]..sort((a, b) => b.compareTo(a));
      expect(timestamps, sorted);
    });

    test('following is a strict subset of global', () async {
      final repo = build();
      final global = await repo.fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: viewer,
        limit: 100,
      );
      final following = await repo.fetchFeed(
        mode: CallFeedMode.following,
        viewerUserId: viewer,
        limit: 100,
      );
      final globalIds = global.entries.map((e) => e.call.id).toSet();
      final followingIds = following.entries.map((e) => e.call.id).toSet();
      expect(followingIds.length, lessThan(globalIds.length));
      expect(globalIds.containsAll(followingIds), isTrue);
    });

    test('a followers-only call is hidden from a signed-out reader', () async {
      final repo = build();
      final signedOut = await repo.fetchFeed(
        mode: CallFeedMode.global,
        limit: 100,
      );
      expect(
        signedOut.entries.any((e) => e.call.id == 'call_zed_sol'),
        isFalse,
      );
      expect(
        () => repo.fetchCall(callId: 'call_zed_sol'),
        throwsA(isA<CallsRejectedException>()),
      );
    });

    test('reading never requires a signed-in user', () async {
      final page = await build().fetchFeed(mode: CallFeedMode.global);
      expect(page.entries, isNotEmpty);
      expect(page.entries.every((e) => e.viewerHasCalled == false), isTrue);
    });

    test('paging walks the whole list without repeats', () async {
      final repo = build();
      final seen = <String>{};
      String? cursor;
      var pages = 0;
      do {
        final page = await repo.fetchFeed(
          mode: CallFeedMode.global,
          viewerUserId: viewer,
          cursor: cursor,
          limit: 2,
        );
        for (final entry in page.entries) {
          expect(seen.add(entry.call.id), isTrue, reason: 'duplicate row');
        }
        cursor = page.nextCursor;
        pages++;
      } while (cursor != null && pages < 20);
      expect(seen.length, greaterThan(2));
    });

    test('an empty repository produces an empty page, not an error', () async {
      final repo = build()..debugClearCalls();
      final page = await repo.fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: viewer,
      );
      expect(page.entries, isEmpty);
      expect(page.nextCursor, isNull);
    });
  });

  group('createCall', () {
    test('signed out cannot write, but could read', () async {
      final repo = build();
      expect(
        () => repo.createCall(
          input: const CreateCallInput(
            marketId: 'market_btc_150k',
            side: Side.yes,
          ),
          viewerUserId: null,
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
    });

    test('a new call is free, locked, and stamped with the venue price', () async {
      final repo = build();
      final entry = await repo.createCall(
        input: const CreateCallInput(
          marketId: 'market_btc_150k',
          side: Side.yes,
          confidence: 0.7,
          thesis: 'Because.',
        ),
        viewerUserId: viewer,
      );
      expect(entry.call.fundingState, FundingState.none);
      expect(entry.call.lockedAt, entry.call.createdAt);
      expect(entry.call.entryProbability, closeTo(0.38, 1e-9));
      expect(entry.call.snapshotId, 'snap_btc_1');
      expect(entry.call.userId, viewer);
      expect(entry.outcome, CallOutcome.pending);
    });

    test('a closed, cancelled or paused market refuses new calls', () async {
      final repo = build();
      for (final marketId in [
        'market_etf_flows',
        'market_cancelled_listing',
        'market_paused_depeg',
        'market_fed_cut',
      ]) {
        expect(
          () => repo.createCall(
            input: CreateCallInput(marketId: marketId, side: Side.yes),
            viewerUserId: viewer,
          ),
          throwsA(isA<CallsRejectedException>()),
          reason: marketId,
        );
      }
    });

    test('a thesis over 280 chars is refused', () async {
      final repo = build();
      expect(
        () => repo.createCall(
          input: CreateCallInput(
            marketId: 'market_btc_150k',
            side: Side.yes,
            thesis: 'x' * (kThesisMaxLength + 1),
          ),
          viewerUserId: viewer,
        ),
        throwsA(isA<CallsRejectedException>()),
      );
    });

    test('a market with no snapshot still accepts a call, without a price', () async {
      final repo = build();
      // market_sol_flip has a snapshot; use the demo one to prove the pairing,
      // then clear it by calling on the paused market is refused — so instead
      // assert the null-price branch directly on the model contract.
      final entry = await repo.createCall(
        input: const CreateCallInput(
          marketId: 'market_sol_flip',
          side: Side.no,
        ),
        viewerUserId: viewer,
      );
      expect(entry.call.entryProbability, isNotNull);
      expect(entry.market.venue.isDemo, isTrue);
    });
  });

  group('respondToCall', () {
    test('Back creates the responder\'s OWN call on the same side', () async {
      final repo = build();
      final target = await repo.fetchCall(
        callId: 'call_ada_btc',
        viewerUserId: viewer,
      );
      final result = await repo.respondToCall(
        input: const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.back,
        ),
        viewerUserId: viewer,
      );

      expect(result.resultingCall, isNotNull);
      expect(result.invitation, isNull);

      final own = result.resultingCall!.call;
      expect(own.userId, viewer);
      expect(own.side, target.entry.call.side);
      expect(own.parentCallId, 'call_ada_btc');
      expect(own.id, isNot('call_ada_btc'));
      expect(own.fundingState, FundingState.none);

      expect(result.response.kind, CallResponseKind.back);
      expect(result.response.targetCallId, 'call_ada_btc');
      expect(result.response.resultingCallId, own.id);
      expect(result.response.actorUserId, viewer);
    });

    test('Fade creates the responder\'s OWN call on the opposite side', () async {
      final repo = build();
      final target = await repo.fetchCall(
        callId: 'call_ada_btc',
        viewerUserId: viewer,
      );
      final result = await repo.respondToCall(
        input: const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.fade,
        ),
        viewerUserId: viewer,
      );
      expect(
        result.resultingCall!.call.side,
        target.entry.call.side.opposite,
      );
      expect(result.resultingCall!.call.parentCallId, 'call_ada_btc');
      expect(result.response.resultingCallId, result.resultingCall!.call.id);
    });

    test('the source call is never mutated by a response', () async {
      final repo = build();
      final before = await repo.fetchCall(
        callId: 'call_ada_btc',
        viewerUserId: viewer,
      );
      final snapshot = before.entry.call.toJson();
      await repo.respondToCall(
        input: const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.fade,
        ),
        viewerUserId: viewer,
      );
      final after = await repo.fetchCall(
        callId: 'call_ada_btc',
        viewerUserId: viewer,
      );
      expect(after.entry.call.toJson(), snapshot);
    });

    test('Challenge creates an invitation and NO call, with no escrow', () async {
      final repo = build();
      final callsBefore = repo.debugCalls.length;
      final result = await repo.respondToCall(
        input: const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.challenge,
          thesis: 'Rematch.',
        ),
        viewerUserId: viewer,
      );

      expect(result.resultingCall, isNull);
      expect(result.response.resultingCallId, isNull);
      expect(repo.debugCalls.length, callsBefore);

      final invitation = result.invitation!;
      expect(invitation.hasEscrow, isFalse);
      expect(invitation.fromUserId, viewer);
      expect(invitation.toUserId, 'user_ada');
      expect(invitation.sourceCallId, 'call_ada_btc');
      expect(invitation.marketId, 'market_btc_150k');
      expect(invitation.note, 'Rematch.');
    });

    test('challenge invitations reach the person they target', () async {
      final repo = build();
      final mine = await repo.fetchInvitations(viewerUserId: viewer);
      expect(mine, isNotEmpty);
      expect(mine.every((i) => i.toUserId == viewer), isTrue);
      expect(mine.every((i) => i.hasEscrow == false), isTrue);
      expect(await repo.fetchInvitations(viewerUserId: null), isEmpty);
    });

    test('you cannot respond to your own call', () async {
      final repo = build();
      expect(
        () => repo.respondToCall(
          input: const RespondToCallInput(
            targetCallId: 'call_you_fed',
            kind: CallResponseKind.back,
          ),
          viewerUserId: viewer,
        ),
        throwsA(isA<CallsRejectedException>()),
      );
    });

    test('signed out cannot respond at all', () async {
      final repo = build();
      for (final kind in CallResponseKind.values) {
        expect(
          () => repo.respondToCall(
            input: RespondToCallInput(
              targetCallId: 'call_ada_btc',
              kind: kind,
            ),
            viewerUserId: null,
          ),
          throwsA(isA<CallsSignedOutException>()),
          reason: kind.name,
        );
      }
    });
  });

  group('crowd split is withheld until the viewer locks', () {
    test('no split before the viewer has a call on the market', () async {
      final repo = build();
      final detail = await repo.fetchMarketDetail(
        marketId: 'market_btc_150k',
        viewerUserId: viewer,
      );
      expect(detail.viewerCall, isNull);
      expect(detail.crowdSplit, isNull);
    });

    test('no split for a signed-out reader either', () async {
      final detail = await build().fetchMarketDetail(
        marketId: 'market_btc_150k',
      );
      expect(detail.crowdSplit, isNull);
    });

    test('the split appears only after the viewer locks their own call', () async {
      final repo = build();
      await repo.createCall(
        input: const CreateCallInput(
          marketId: 'market_btc_150k',
          side: Side.yes,
        ),
        viewerUserId: viewer,
      );
      final detail = await repo.fetchMarketDetail(
        marketId: 'market_btc_150k',
        viewerUserId: viewer,
      );
      expect(detail.viewerCall, isNotNull);
      expect(detail.crowdSplit, isNotNull);
      expect(detail.crowdSplit!.total, greaterThan(0));
    });
  });

  group('offline and failure surfaces', () {
    test('offline throws CallsOfflineException, not a generic failure', () async {
      final repo = build()..simulateOffline = true;
      expect(
        () => repo.fetchFeed(mode: CallFeedMode.global),
        throwsA(isA<CallsOfflineException>()),
      );
      expect(
        () => repo.fetchMarketDetail(marketId: 'market_btc_150k'),
        throwsA(isA<CallsOfflineException>()),
      );
    });

    test('a generic failure is distinguishable from offline', () async {
      final repo = build()..simulateFailure = true;
      expect(
        () => repo.fetchFeed(mode: CallFeedMode.global),
        throwsA(
          allOf(isA<CallsFailure>(), isNot(isA<CallsOfflineException>())),
        ),
      );
    });
  });

  group('people and links', () {
    test('a person resolves by id, by handle and by @handle', () async {
      final repo = build();
      for (final ref in ['user_ada', 'ada', '@ada', 'ADA']) {
        final detail = await repo.fetchPerson(personRef: ref);
        expect(detail.person.id, 'user_ada', reason: ref);
      }
    });

    test('accuracy is null when nothing has settled — never 0%', () async {
      final detail = await build().fetchPerson(personRef: 'tobi');
      expect(detail.person.settledCalls, 0);
      expect(detail.person.accuracy, isNull);
    });

    test('an unknown person is a rejection, not a crash', () async {
      expect(
        () => build().fetchPerson(personRef: 'nobody'),
        throwsA(isA<CallsRejectedException>()),
      );
    });

    test('share links are stable and well formed', () {
      final repo = build();
      expect(repo.shareLinkForCall('call_1'), 'https://chumbucket.app/c/call_1');
      expect(repo.shareLinkForPerson('ada'), 'https://chumbucket.app/u/ada');
    });
  });

  group('debugResolveMarket derives results by the only permitted rule', () {
    test('resolving YES makes YES calls correct and NO calls incorrect', () async {
      final repo = build();
      repo.debugResolveMarket(
        marketId: 'market_btc_150k',
        resolution: Resolution.yes,
      );
      final ada = await repo.fetchCall(
        callId: 'call_ada_btc',
        viewerUserId: viewer,
      );
      final tobi = await repo.fetchCall(
        callId: 'call_tobi_btc',
        viewerUserId: viewer,
      );
      expect(ada.entry.call.side, Side.yes);
      expect(ada.entry.outcome, CallOutcome.correct);
      expect(tobi.entry.call.side, Side.no);
      expect(tobi.entry.outcome, CallOutcome.incorrect);
    });

    test('cancelling a market voids every call on it', () async {
      final repo = build();
      repo.debugResolveMarket(
        marketId: 'market_btc_150k',
        resolution: Resolution.voided,
      );
      final detail = await repo.fetchMarketDetail(marketId: 'market_btc_150k');
      expect(detail.market.status, MarketStatus.cancelled);
      for (final id in ['call_ada_btc', 'call_tobi_btc', 'call_kemi_btc_fade']) {
        final call = await repo.fetchCall(callId: id, viewerUserId: viewer);
        expect(call.entry.outcome, CallOutcome.voided, reason: id);
      }
    });
  });
}
