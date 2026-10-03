import 'dart:async';

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const String viewer = MockCallsRepository.demoViewerUserId;

/// A repository that counts reads, so the caching guard can be asserted.
class _CountingRepository implements CallsRepository {
  _CountingRepository(this._inner);

  final MockCallsRepository _inner;

  int feedCalls = 0;
  int marketCalls = 0;
  int personCalls = 0;

  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) {
    feedCalls++;
    return _inner.fetchFeed(
      mode: mode,
      viewerUserId: viewerUserId,
      cursor: cursor,
      limit: limit,
    );
  }

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) {
    marketCalls++;
    return _inner.fetchMarketDetail(
      marketId: marketId,
      viewerUserId: viewerUserId,
    );
  }

  @override
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  }) {
    personCalls++;
    return _inner.fetchPerson(
      personRef: personRef,
      viewerUserId: viewerUserId,
    );
  }

  @override
  Future<bool> setFollowing({
    required String personId,
    required bool following,
    required String? viewerUserId,
  }) => _inner.setFollowing(
    personId: personId,
    following: following,
    viewerUserId: viewerUserId,
  );

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) => _inner.fetchCall(callId: callId, viewerUserId: viewerUserId);

  @override
  Future<List<VenueMarket>> fetchOpenMarkets({String? category}) =>
      _inner.fetchOpenMarkets(category: category);

  @override
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  }) => _inner.createCall(input: input, viewerUserId: viewerUserId);

  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) => _inner.respondToCall(input: input, viewerUserId: viewerUserId);

  @override
  Future<List<ChallengeInvitation>> fetchInvitations({
    required String? viewerUserId,
  }) => _inner.fetchInvitations(viewerUserId: viewerUserId);

  @override
  String shareLinkForCall(String callId) => _inner.shareLinkForCall(callId);

  @override
  String shareLinkForPerson(String handleOrId) =>
      _inner.shareLinkForPerson(handleOrId);
}

/// Holds the open-market read until the test lets it finish.
class _GatedOpenMarkets extends MockCallsRepository {
  _GatedOpenMarkets(this._gate);

  final Future<void> _gate;

  @override
  Future<List<VenueMarket>> fetchOpenMarkets({String? category}) async {
    await _gate;
    return super.fetchOpenMarkets(category: category);
  }
}

void main() {
  group('open catalog across a sign-in', () {
    test('a session landing mid-load keeps the catalog load alive', () async {
      // Markets starts this load at launch; the restored session reaches
      // setViewer a moment later. The catalog is the same for everyone.
      final gate = Completer<void>();
      final provider = CallsProvider(
        repository: _GatedOpenMarkets(gate.future),
      );
      final load = provider.loadOpenMarkets();
      expect(provider.isLoadingOpenMarkets, isTrue);

      provider.setViewer(viewer);
      expect(provider.isLoadingOpenMarkets, isTrue);

      gate.complete();
      await load;
      expect(provider.isLoadingOpenMarkets, isFalse);
      expect(provider.openMarkets, isNotEmpty);
    });
  });

  group('session', () {
    test('reads work signed out; only writes are gated', () async {
      final provider = CallsProvider(repository: MockCallsRepository());
      expect(provider.isSignedIn, isFalse);

      await provider.loadFeed();
      expect(provider.feed, isNotEmpty);
      expect(provider.feedState, CallsLoadState.ready);

      await expectLater(
        provider.createCall(
          const CreateCallInput(marketId: 'market_btc_150k', side: Side.yes),
        ),
        throwsA(isA<CallsSignedOutException>()),
      );
    });

    test('changing the viewer clears every viewer-scoped cache', () async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      await provider.loadFeed();
      await provider.loadMarketDetail('market_btc_150k');
      expect(provider.feed, isNotEmpty);
      expect(provider.marketDetail('market_btc_150k'), isNotNull);

      provider.setViewer('someone_else');
      expect(provider.feed, isEmpty);
      expect(provider.marketDetail('market_btc_150k'), isNull);
      expect(provider.feedState, CallsLoadState.idle);
    });

    test('setting the same viewer is a no-op', () {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.setViewer(viewer);
      expect(notifications, 0);
    });
  });

  group('canonical follows', () {
    test('server-confirmed follow and unfollow update the person page', () async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      final initial = await provider.loadPerson('user_zed');
      expect(initial!.viewerIsFollowing, isFalse);
      expect(await provider.setFollowing(initial, true), isTrue);
      expect(provider.personDetail('user_zed')!.viewerIsFollowing, isTrue);
      expect(await provider.setFollowing(provider.personDetail('user_zed')!, false), isFalse);
      expect(provider.personDetail('user_zed')!.viewerIsFollowing, isFalse);
    });

    test('unfollow withdraws followers-only rows from every cached surface', () async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      final initial = (await provider.loadPerson('user_zed'))!;
      await provider.setFollowing(initial, true);
      expect(provider.personDetail('user_zed')!.calls
          .any((entry) => entry.call.id == 'call_zed_sol'), isTrue);
      await provider.loadCall('call_zed_sol');
      expect(provider.callDetail('call_zed_sol'), isNotNull);
      expect(provider.feed.any((entry) => entry.call.id == 'call_zed_sol'), isTrue);

      await provider.setFollowing(provider.personDetail('user_zed')!, false);
      expect(provider.personDetail('user_zed')!.calls
          .any((entry) => entry.call.id == 'call_zed_sol'), isFalse);
      expect(provider.callDetail('call_zed_sol'), isNull);
      expect(provider.feed.any((entry) => entry.call.id == 'call_zed_sol'), isFalse);
    });

    test('offline refusal leaves the prior follow state untouched', () async {
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      final initial = (await provider.loadPerson('user_zed'))!;
      repo.simulateOffline = true;
      await expectLater(provider.setFollowing(initial, true),
          throwsA(isA<CallsOfflineException>()));
      expect(provider.personDetail('user_zed')!.viewerIsFollowing, isFalse);
    });

    test('account switch during a follow cannot populate the new account cache', () async {
      final repo = MockCallsRepository(latency: const Duration(milliseconds: 25));
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      final initial = (await provider.loadPerson('user_zed'))!;
      final pending = provider.setFollowing(initial, true);
      provider.setViewer('someone_else');
      await expectLater(pending, throwsA(isA<CallsRejectedException>()));
      expect(provider.personDetail('user_zed'), isNull);
      expect(provider.isFollowBusy('user_zed'), isFalse);
    });
  });

  group('feed states', () {
    test('idle before the first load', () {
      final provider = CallsProvider(repository: MockCallsRepository());
      expect(provider.feedState, CallsLoadState.idle);
      expect(provider.feedAge, isNull);
      expect(provider.isFeedStale, isFalse);
    });

    test('ready after a successful load', () async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      await provider.loadFeed();
      expect(provider.feedState, CallsLoadState.ready);
      expect(provider.isOffline, isFalse);
      expect(provider.feedError, isNull);
    });

    test('empty when the repository genuinely has nothing', () async {
      final repo = MockCallsRepository()..debugClearCalls();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      await provider.loadFeed();
      expect(provider.feedState, CallsLoadState.empty);
      expect(provider.feedError, isNull);
    });

    test('offline with no cache is offline, not error', () async {
      final repo = MockCallsRepository()..simulateOffline = true;
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      await provider.loadFeed();
      expect(provider.feedState, CallsLoadState.offline);
      expect(provider.isOffline, isTrue);
    });

    test('offline WITH a cache keeps the rows and flags them as cached', () async {
      final repo = MockCallsRepository();
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      await provider.loadFeed();
      final cached = provider.feed.length;
      expect(cached, greaterThan(0));

      repo.simulateOffline = true;
      await provider.loadFeed(force: true);

      expect(provider.feed.length, cached, reason: 'cached rows are kept');
      expect(provider.isOffline, isTrue);
      expect(provider.isFeedFromCache, isTrue);
      expect(provider.feedState, CallsLoadState.ready);
    });

    test('a generic failure with no cache is the error state', () async {
      final repo = MockCallsRepository()..simulateFailure = true;
      final provider = CallsProvider(repository: repo)..setViewer(viewer);
      await provider.loadFeed();
      expect(provider.feedState, CallsLoadState.error);
      expect(provider.feedError, isNotNull);
      expect(provider.isOffline, isFalse);
    });

    test('stale once the served page is older than staleAfter', () async {
      var now = DateTime.utc(2026, 9, 13, 12);
      final provider = CallsProvider(
        repository: MockCallsRepository(clock: () => now),
        clock: () => now,
        staleAfter: const Duration(minutes: 2),
      )..setViewer(viewer);

      await provider.loadFeed();
      expect(provider.isFeedStale, isFalse);

      now = now.add(const Duration(minutes: 3));
      expect(provider.isFeedStale, isTrue);
      expect(provider.feedAge, const Duration(minutes: 3));
      // Stale is not an error and does not blank the screen.
      expect(provider.feedState, CallsLoadState.ready);
      expect(provider.feedError, isNull);
    });

    test('a snapshot older than staleAfter reports stale', () async {
      final now = DateTime.utc(2026, 9, 13, 12);
      final provider = CallsProvider(
        repository: MockCallsRepository(clock: () => now),
        clock: () => now,
        staleAfter: const Duration(minutes: 2),
      )..setViewer(viewer);

      await provider.loadMarketDetail('market_btc_150k');
      await provider.loadMarketDetail('market_sol_flip');

      // btc snapshot is 2 minutes old, sol is 5 hours old.
      expect(provider.isSnapshotStale('market_btc_150k'), isFalse);
      expect(provider.isSnapshotStale('market_sol_flip'), isTrue);
      expect(provider.snapshotAge('market_sol_flip'), const Duration(hours: 5));
      // A market with no snapshot reports no age rather than a fake zero.
      await provider.loadMarketDetail('market_paused_depeg');
      expect(provider.snapshotAge('market_paused_depeg'), isNull);
      expect(provider.isSnapshotStale('market_paused_depeg'), isFalse);
    });
  });

  group('caching, following arena_provider.dart:640-666', () {
    test('a second load of the same market is served from cache', () async {
      final counting = _CountingRepository(MockCallsRepository());
      final provider = CallsProvider(repository: counting)..setViewer(viewer);

      await provider.loadMarketDetail('market_btc_150k');
      await provider.loadMarketDetail('market_btc_150k');
      expect(counting.marketCalls, 1);

      await provider.loadMarketDetail('market_btc_150k', force: true);
      expect(counting.marketCalls, 2);
    });

    test('concurrent loads of the same key fire one request', () async {
      final counting = _CountingRepository(
        MockCallsRepository(latency: const Duration(milliseconds: 5)),
      );
      final provider = CallsProvider(repository: counting)..setViewer(viewer);

      await Future.wait([
        provider.loadPerson('user_ada'),
        provider.loadPerson('user_ada'),
        provider.loadPerson('user_ada'),
      ]);
      expect(counting.personCalls, 1);
    });

    test('a fresh feed is not refetched until it goes stale', () async {
      var now = DateTime.utc(2026, 9, 13, 12);
      final counting = _CountingRepository(
        MockCallsRepository(clock: () => now),
      );
      final provider = CallsProvider(
        repository: counting,
        clock: () => now,
        staleAfter: const Duration(minutes: 2),
      )..setViewer(viewer);

      await provider.loadFeed();
      await provider.loadFeed();
      expect(counting.feedCalls, 1);

      now = now.add(const Duration(minutes: 5));
      await provider.loadFeed();
      expect(counting.feedCalls, 2);
    });

    test('switching feed mode refetches and resets the list', () async {
      final counting = _CountingRepository(MockCallsRepository());
      final provider = CallsProvider(repository: counting)..setViewer(viewer);

      await provider.loadFeed();
      final globalCount = provider.feed.length;
      await provider.setFeedMode(CallFeedMode.following);

      expect(provider.feedMode, CallFeedMode.following);
      expect(counting.feedCalls, 2);
      expect(provider.feed.length, lessThan(globalCount));

      // Selecting the mode already active is a no-op.
      await provider.setFeedMode(CallFeedMode.following);
      expect(counting.feedCalls, 2);
    });

    test('loadMore appends without duplicating', () async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      await provider.loadFeed();
      // Seeded feed is small; paging is exercised in the repository test.
      expect(provider.hasMore, isFalse);
      await provider.loadMore();
      expect(provider.feed.map((e) => e.call.id).toSet().length,
          provider.feed.length);
    });
  });

  group('writes', () {
    test('a new call lands at the top of the feed', () async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      await provider.loadFeed();
      final before = provider.feed.length;

      final entry = await provider.createCall(
        const CreateCallInput(
          marketId: 'market_btc_150k',
          side: Side.yes,
          confidence: 0.75,
          thesis: 'Mine.',
        ),
      );

      expect(provider.feed.length, before + 1);
      expect(provider.feed.first.call.id, entry.call.id);
      expect(entry.call.fundingState, FundingState.none);
      expect(provider.isSubmitting, isFalse);
    });

    test('creating a call invalidates that market\'s cached detail', () async {
      final counting = _CountingRepository(MockCallsRepository());
      final provider = CallsProvider(repository: counting)..setViewer(viewer);

      await provider.loadMarketDetail('market_btc_150k');
      expect(provider.marketDetail('market_btc_150k')!.crowdSplit, isNull);

      await provider.createCall(
        const CreateCallInput(marketId: 'market_btc_150k', side: Side.yes),
      );
      expect(provider.marketDetail('market_btc_150k'), isNull);

      await provider.loadMarketDetail('market_btc_150k');
      expect(provider.marketDetail('market_btc_150k')!.crowdSplit, isNotNull);
    });

    test('Back and Fade push the responder\'s own call into the feed', () async {
      for (final kind in [CallResponseKind.back, CallResponseKind.fade]) {
        final provider = CallsProvider(repository: MockCallsRepository())
          ..setViewer(viewer);
        await provider.loadFeed();
        final before = provider.feed.length;

        final result = await provider.respondToCall(
          RespondToCallInput(targetCallId: 'call_ada_btc', kind: kind),
        );

        expect(result.resultingCall, isNotNull, reason: kind.name);
        expect(provider.feed.length, before + 1, reason: kind.name);
        expect(
          provider.feed.first.call.id,
          result.resultingCall!.call.id,
          reason: kind.name,
        );
        expect(provider.feed.first.call.userId, viewer);
      }
    });

    test('Challenge adds no call to the feed and carries no escrow', () async {
      final provider = CallsProvider(repository: MockCallsRepository())
        ..setViewer(viewer);
      await provider.loadFeed();
      final before = provider.feed.length;

      final result = await provider.respondToCall(
        const RespondToCallInput(
          targetCallId: 'call_ada_btc',
          kind: CallResponseKind.challenge,
        ),
      );

      expect(result.resultingCall, isNull);
      expect(result.invitation!.hasEscrow, isFalse);
      expect(provider.feed.length, before);
    });

    test('invitations load for the signed-in viewer only', () async {
      final provider = CallsProvider(repository: MockCallsRepository());
      await provider.loadInvitations();
      expect(provider.invitations, isEmpty);

      provider.setViewer(viewer);
      await provider.loadInvitations();
      expect(provider.invitations, isNotEmpty);
      expect(provider.invitations.every((i) => i.hasEscrow == false), isTrue);
    });
  });

  test('notifying after dispose does not throw', () async {
    final provider = CallsProvider(
      repository: MockCallsRepository(latency: const Duration(milliseconds: 5)),
    )..setViewer(viewer);
    final pending = provider.loadFeed();
    provider.dispose();
    await pending;
  });
}
