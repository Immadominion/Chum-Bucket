/// The app is stateful: screens open on what was there last time, refresh
/// silently, keep what they have when a refresh fails, and never narrate it.
///
/// * the on-phone snapshot store (files, expiry, corruption, sign-out wipe);
/// * the BFF repository saves the server's own JSON for the reads a cold
///   start draws, keyed by account, and never for the wrong account;
/// * providers draw the saved read at once and replace it with the live one;
/// * switching Home's tabs keeps each tab's rows;
/// * Activity opens on the saved inbox when offline.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chumbucket/core/cache/snapshot_store.dart';
import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/notifications/data/bff_notifications_repository.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';

import 'bff_calls_fixtures.dart';

const _base = 'https://bff.test.invalid';

BffCallsRepository _repo(FakeBffServer server, SnapshotStore store) =>
    BffCallsRepository(
      baseUrl: _base,
      httpClient: server.client,
      authToken: () => 'session-token',
      verbose: false,
      snapshots: store,
    );

void main() {
  group('FileSnapshotStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('snapshots'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('round-trips JSON and forgets everything on clear', () async {
      final store = FileSnapshotStore(directory: () async => dir);
      await store.write('feed.global.user_a', {
        'entries': [1, 2, 3],
      });
      expect(await store.read('feed.global.user_a'), {
        'entries': [1, 2, 3],
      });
      expect(await store.read('missing'), isNull);
      await store.clear();
      expect(await store.read('feed.global.user_a'), isNull);
    });

    test('an old or unreadable snapshot is ignored, never thrown', () async {
      var now = DateTime(2026, 10, 1);
      final store = FileSnapshotStore(
        directory: () async => dir,
        clock: () => now,
        maxAge: const Duration(days: 14),
      );
      await store.write('inbox.user_a', {'items': []});
      now = now.add(const Duration(days: 15));
      expect(await store.read('inbox.user_a'), isNull);

      File('${dir.path}/broken.json').writeAsStringSync('{not json');
      expect(await store.read('broken'), isNull);
    });

    test('no platform directory means no snapshots, not a crash', () async {
      final store = FileSnapshotStore(
        directory: () async => throw const FileSystemException('none'),
      );
      await store.write('k', {'a': 1});
      expect(await store.read('k'), isNull);
      await store.clear();
    });

    test('keys are file-safe and scoped to the account', () {
      expect(snapshotKey('feed', variant: 'global'), 'feed.global.anon');
      expect(
        snapshotKey('person', variant: '../x', viewer: 'user/a'),
        'person.___x.user_a',
      );
    });
  });

  group('BffCallsRepository snapshots', () {
    test(
      'the first feed page is saved per account and comes back as saved',
      () async {
        final store = MemorySnapshotStore();
        final server = FakeBffServer.routes({'calls.feed': feedPageJson()});
        final repo = _repo(server, store)..bindSnapshotViewer('user_a');
        await repo.fetchFeed(mode: CallFeedMode.global, viewerUserId: 'user_a');

        final saved = await repo.savedFeed(mode: CallFeedMode.global);
        expect(saved, isNotNull);
        expect(saved!.fromCache, isTrue);
        expect(saved.entries.single.call.id, 'call_ada_btc');

        // Another account on the same phone sees nothing of it.
        repo.bindSnapshotViewer('user_b');
        expect(await repo.savedFeed(mode: CallFeedMode.global), isNull);
        // Nor does the other tab.
        repo.bindSnapshotViewer('user_a');
        expect(await repo.savedFeed(mode: CallFeedMode.following), isNull);
      },
    );

    test('a later page is not saved: a cold start draws page one', () async {
      final store = MemorySnapshotStore();
      final server = FakeBffServer.routes({'calls.feed': feedPageJson()});
      final repo = _repo(server, store)..bindSnapshotViewer('user_a');
      await repo.fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: 'user_a',
        cursor: '20',
      );
      expect(store.keys, isEmpty);
    });

    test('a read that lands after the account changed is not saved', () async {
      final store = MemorySnapshotStore();
      final server = FakeBffServer.routes({'calls.feed': feedPageJson()})
        ..simulateLatency = const Duration(milliseconds: 30);
      final repo = _repo(server, store)..bindSnapshotViewer('user_a');
      final read = repo.fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: 'user_a',
      );
      repo.bindSnapshotViewer(null); // signed out mid-flight
      await read;
      expect(store.keys, isEmpty);
    });

    test('only your own profile is saved, and the follow list', () async {
      final store = MemorySnapshotStore();
      final server = FakeBffServer.routes({
        'people.get': personDetailJson(),
        'people.following': {
          'people': [
            {
              'id': 'user_kemi',
              'handle': 'kemi',
              'displayName': 'Kemi',
              'avatarUrl': null,
              'viewerIsFollowing': true,
              'record': {
                'counts': {
                  'correct': 1,
                  'incorrect': 0,
                  'void': 0,
                  'decided': 1,
                  'pending': 0,
                },
                'display': {'mode': 'counts', 'minimumDecided': 10},
              },
            },
          ],
        },
      });
      final repo = _repo(server, store)..bindSnapshotViewer('user_you');
      await repo.fetchPerson(personRef: 'user_other');
      expect(await repo.savedPerson('user_other'), isNull);
      await repo.fetchPerson(personRef: 'user_you');
      expect(await repo.savedPerson('user_you'), isNotNull);
      await repo.fetchFollowing();
      expect(await repo.savedFollowing(), hasLength(1));
    });
  });

  group('providers open on the saved read', () {
    test('Home draws the saved feed while the live one loads', () async {
      final store = MemorySnapshotStore();
      final warm = FakeBffServer.routes({'calls.feed': feedPageJson()});
      await (_repo(warm, store)..bindSnapshotViewer(
        'user_a',
      )).fetchFeed(mode: CallFeedMode.global, viewerUserId: 'user_a');

      final slow = FakeBffServer.routes({
        'calls.feed': feedPageJson(entries: const []),
      })..simulateLatency = const Duration(milliseconds: 80);
      final provider = CallsProvider(repository: _repo(slow, store))
        ..setViewer('user_a');
      addTearDown(provider.dispose);
      final load = provider.loadFeed();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.feedState, CallsLoadState.ready);
      expect(provider.feed.single.call.id, 'call_ada_btc');
      expect(provider.isLoadingFeed, isTrue);

      await load;
      // The live answer wins, even when it is genuinely empty.
      expect(provider.feedState, CallsLoadState.empty);
      expect(provider.isFeedFromCache, isFalse);
    });

    test('offline on a cold start still shows the saved feed', () async {
      final store = MemorySnapshotStore();
      final warm = FakeBffServer.routes({'calls.feed': feedPageJson()});
      await (_repo(warm, store)..bindSnapshotViewer(
        'user_a',
      )).fetchFeed(mode: CallFeedMode.global, viewerUserId: 'user_a');
      final dead = FakeBffServer.routes({})..simulateTransportFailure = true;
      final provider = CallsProvider(repository: _repo(dead, store))
        ..setViewer('user_a');
      addTearDown(provider.dispose);
      await provider.loadFeed();
      await Future<void>.delayed(Duration.zero);
      expect(provider.feedState, CallsLoadState.ready);
      expect(provider.isOffline, isTrue);
      expect(provider.feed, isNotEmpty);
    });

    test('switching Home tabs keeps each tab on screen', () async {
      final provider = CallsProvider(
        repository: MockCallsRepository(
          latency: const Duration(milliseconds: 40),
        ),
      )..setViewer(MockCallsRepository.demoViewerUserId);
      addTearDown(provider.dispose);
      await provider.loadFeed();
      final global = provider.feed.length;
      expect(global, greaterThan(0));

      unawaited(provider.setFeedMode(CallFeedMode.following));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      // Back to Global: the rows are there at once, no skeleton, while the
      // tab refreshes quietly.
      final back = provider.setFeedMode(CallFeedMode.global);
      expect(provider.feed.length, global);
      expect(provider.feedState, CallsLoadState.ready);
      await back;
    });
  });

  test('Activity opens on the saved inbox when offline', () async {
    final page =
        File('test/fixtures/inbox_page_server.json').readAsStringSync();
    final store = MemorySnapshotStore();
    var offline = false;
    BffNotificationsRepository repo() => BffNotificationsRepository(
      snapshots: store,
      transport: CallsBffTransport(
        baseUrl: 'https://bff.test',
        authToken: () => 'session-token',
        verbose: false,
        httpClient: MockClient((request) async {
          if (offline) {
            throw http.ClientException('Connection refused', request.url);
          }
          return http.Response(page, 200);
        }),
      ),
    );

    final first = NotificationsProvider(repository: repo())..setViewer('u-ann');
    addTearDown(first.dispose);
    await first.load();
    final rows = first.notifications.length;
    expect(rows, greaterThan(0));
    // What was saved is the server's page, nothing more.
    expect(jsonEncode(await store.read('inbox.u-ann')), contains('items'));

    offline = true;
    final cold = NotificationsProvider(repository: repo())..setViewer('u-ann');
    addTearDown(cold.dispose);
    await cold.load();
    await Future<void>.delayed(Duration.zero);
    expect(cold.state, NotificationsLoadState.ready);
    expect(cold.notifications, hasLength(rows));
    expect(cold.isOffline, isTrue);

    // Someone else signing in on this phone gets nothing of it.
    final other = NotificationsProvider(repository: repo())..setViewer('u-bob');
    addTearDown(other.dispose);
    await other.load();
    await Future<void>.delayed(Duration.zero);
    expect(other.notifications, isEmpty);
  });
}
