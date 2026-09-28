import 'dart:async';

import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Delays delivery, not authorization: the request has already been served for
/// the old viewer when the device signs out or switches accounts.
class DelayedCallsRepository extends MockCallsRepository {
  DelayedCallsRepository() : super(latency: Duration.zero);

  final captured = Completer<void>();
  final release = Completer<void>();
  String? delay;
  bool fail = false;

  Future<T> hold<T>(String operation, Future<T> request) async {
    final result = await request;
    if (operation == delay) {
      delay = null;
      captured.complete();
      await release.future;
      if (fail) throw const CallsOfflineException();
    }
    return result;
  }

  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) => hold(
    cursor == null ? 'feed' : 'more',
    super.fetchFeed(
      mode: mode,
      viewerUserId: viewerUserId,
      cursor: cursor,
      limit: 1,
    ),
  );

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) =>
      hold('call', super.fetchCall(callId: callId, viewerUserId: viewerUserId));

  @override
  Future<MarketDetail> fetchMarketDetail({
    required String marketId,
    String? viewerUserId,
  }) => hold(
    'market',
    super.fetchMarketDetail(marketId: marketId, viewerUserId: viewerUserId),
  );

  @override
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  }) => hold(
    'person',
    super.fetchPerson(personRef: personRef, viewerUserId: viewerUserId),
  );

  @override
  Future<List<ChallengeInvitation>> fetchInvitations({
    required String? viewerUserId,
  }) => hold('invitations', super.fetchInvitations(viewerUserId: viewerUserId));

  @override
  Future<CallFeedEntry> createCall({
    required CreateCallInput input,
    required String? viewerUserId,
  }) => hold(
    'create',
    super.createCall(input: input, viewerUserId: viewerUserId),
  );

  @override
  Future<CallResponseResult> respondToCall({
    required RespondToCallInput input,
    required String? viewerUserId,
  }) => hold(
    'respond',
    super.respondToCall(input: input, viewerUserId: viewerUserId),
  );
}

void main() {
  late DelayedCallsRepository repo;
  late CallsProvider provider;
  setUp(() {
    repo = DelayedCallsRepository();
    provider = CallsProvider(repository: repo)
      ..setViewer(MockCallsRepository.demoViewerUserId);
  });
  tearDown(() => provider.dispose());

  Future<void> switchBeforeDelivery() async {
    await repo.captured.future;
    provider.setViewer(null);
    repo.release.complete();
  }

  test(
    'a previous viewer feed response cannot repopulate signed-out state',
    () async {
      repo.delay = 'feed';
      final pending = provider.loadFeed();
      await switchBeforeDelivery();
      await pending;
      expect(provider.feed, isEmpty);
      expect(provider.feedServedAtUtc, isNull);
      expect(provider.isLoadingFeed, isFalse);
    },
  );

  test('late errors cannot replace the next account feed state', () async {
    repo.delay = 'feed';
    repo.fail = true;
    final pending = provider.loadFeed();
    await repo.captured.future;
    provider.setViewer('user_ada');
    await provider.loadFeed();
    expect(provider.feed, isNotEmpty);
    repo.release.complete();
    await pending;
    expect(provider.feedError, isNull);
    expect(provider.isOffline, isFalse);
  });

  test('pagination cannot append previous-account rows', () async {
    await provider.loadFeed();
    expect(provider.hasMore, isTrue);
    repo.delay = 'more';
    final pending = provider.loadMore();
    await switchBeforeDelivery();
    await pending;
    expect(provider.feed, isEmpty);
    expect(provider.hasMore, isFalse);
  });

  test('switching feed mode invalidates an in-flight previous mode', () async {
    repo.delay = 'feed';
    final old = provider.loadFeed();
    await repo.captured.future;
    await provider.setFeedMode(CallFeedMode.following);
    final expected = provider.feed.map((e) => e.call.id).toList();
    expect(expected, isNotEmpty);
    repo.release.complete();
    await old;
    expect(provider.feed.map((e) => e.call.id), expected);
  });

  for (final kind in ['call', 'market', 'person']) {
    test(
      '$kind discards the old detail and return value after sign-out',
      () async {
        final seed = await repo.fetchFeed(
          mode: CallFeedMode.global,
          viewerUserId: provider.viewerUserId,
        );
        final entry = seed.entries.first;
        repo.delay = kind;
        final Future<Object?> pending = switch (kind) {
          'call' => provider.loadCall(entry.call.id),
          'market' => provider.loadMarketDetail(entry.market.id),
          _ => provider.loadPerson(entry.author.id),
        };
        await switchBeforeDelivery();
        expect(await pending, isNull);
        expect(provider.callDetail(entry.call.id), isNull);
        expect(provider.marketDetail(entry.market.id), isNull);
        expect(provider.personDetail(entry.author.id), isNull);
      },
    );
  }

  test('a new detail request does not wait for the previous account', () async {
    final seed = await repo.fetchFeed(mode: CallFeedMode.global);
    final id = seed.entries.first.call.id;
    repo.delay = 'call';
    final old = provider.loadCall(id);
    await repo.captured.future;
    provider.setViewer(null);
    final current = await provider.loadCall(id);
    expect(current, isNotNull);
    repo.release.complete();
    expect(await old, isNull);
    expect(provider.callDetail(id), same(current));
  });

  test('old invitations do not cross account boundaries', () async {
    repo.delay = 'invitations';
    final pending = provider.loadInvitations();
    await switchBeforeDelivery();
    await pending;
    expect(provider.invitations, isEmpty);
  });

  for (final kind in ['create', 'respond']) {
    test(
      '$kind cannot return or publish old-account success after a switch',
      () async {
        final markets = await repo.fetchOpenMarkets();
        repo.delay = kind;
        final Future<Object> pending;
        if (kind == 'create') {
          pending = provider.createCall(
            CreateCallInput(marketId: markets.first.id, side: Side.yes),
          );
        } else {
          final feed = await repo.fetchFeed(mode: CallFeedMode.global);
          pending = provider.respondToCall(
            RespondToCallInput(
              targetCallId: feed.entries.first.call.id,
              kind: CallResponseKind.challenge,
            ),
          );
        }
        final checked = expectLater(
          pending,
          throwsA(isA<CallsRejectedException>()),
        );
        await switchBeforeDelivery();
        await checked;
        expect(provider.feed, isEmpty);
        expect(provider.isSubmitting, isFalse);
      },
    );
  }
}
