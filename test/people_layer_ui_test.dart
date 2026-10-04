/// The people layer on screen: the Leaderboard (with its pinned rank and its
/// refusal to rank a short record), Home's Top calls strip (with the crowd
/// split withheld until the viewer has called), the trader profile's
/// credibility strip and Open/Settled split, the thesis thread, and search.
///
/// Every surface is also mounted at 320dp and 2x text, where nothing may
/// overflow.
library;

import 'dart:async';

import 'package:chumbucket/core/theme/app_text_styles.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_composer_sheet.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_repository.dart';
import 'package:chumbucket/features/people/presentation/leaderboard_view.dart';
import 'package:chumbucket/features/people/presentation/search_screen.dart';
import 'package:chumbucket/features/people/presentation/widgets/credibility_strip.dart';
import 'package:chumbucket/features/people/presentation/widgets/thesis_thread.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'ui_people_layout_friends_test.dart' show QuietArena, friendsScreen, hub;
import 'ui_people_layout_profile_test.dart' show mountPeople, revealPeopleText;

const _viewer = MockCallsRepository.demoViewerUserId;

PublicRecord record({
  int correct = 4,
  int incorrect = 0,
  int pending = 0,
  double? accuracy,
}) => PublicRecord(
  correct: correct,
  incorrect: incorrect,
  voided: 0,
  decided: correct + incorrect,
  pending: pending,
  minimumDecided: 10,
  accuracy: accuracy,
);

PersonCard card(String id, String name, PublicRecord r) => PersonCard(
  id: id,
  handle: id.replaceFirst('user_', ''),
  displayName: name,
  record: r,
);

/// The seeded mock, plus the people capability backed by test-supplied data.
class PeopleFake extends MockCallsRepository implements PeopleRepository {
  final leaderboardRequests = <LeaderboardWindow>[];
  Leaderboard Function(LeaderboardWindow window)? board;
  List<TopCall> top = const [];
  List<PersonCard> directory = const [];
  List<PersonCard> follows = const [];
  final updates = <String, List<ThesisUpdate>>{};
  bool updatesAvailable = true;
  PublicRecord? personRecord;
  int? followers;
  int? followingCount;
  final posted = <String>[];

  @override
  Future<Leaderboard> fetchLeaderboard({
    required LeaderboardWindow window,
    int limit = 50,
  }) async {
    leaderboardRequests.add(window);
    return board!(window);
  }

  @override
  Future<List<PersonCard>> searchPeople(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    return directory
        .where((p) => p.displayName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<PersonCard>> fetchFollowing() async => follows;

  int topRequests = 0;

  @override
  Future<List<TopCall>> fetchTopCalls({int limit = 10}) async {
    topRequests++;
    return top;
  }

  @override
  Future<ThesisUpdate> appendThesisUpdate({
    required String callId,
    required String body,
  }) async {
    posted.add(body.trim());
    final update = ThesisUpdate(
      id: 'upd_${posted.length}',
      callId: callId,
      authorUserId: _viewer,
      body: body.trim(),
      createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    updates.putIfAbsent(callId, () => []).add(update);
    return update;
  }

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async {
    final detail = await super.fetchCall(
      callId: callId,
      viewerUserId: viewerUserId,
    );
    return CallDetail(
      entry: detail.entry,
      parent: detail.parent,
      responses: detail.responses,
      updates: List.of(updates[callId] ?? const []),
      updatesAvailable: updatesAvailable,
    );
  }

  @override
  Future<PersonDetail> fetchPerson({
    required String personRef,
    String? viewerUserId,
  }) async {
    final detail = await super.fetchPerson(
      personRef: personRef,
      viewerUserId: viewerUserId,
    );
    return PersonDetail(
      person: detail.person,
      calls: detail.calls,
      viewerIsFollowing: detail.viewerIsFollowing,
      servedAt: detail.servedAt,
      followerCount: followers,
      followingCount: followingCount,
      record: personRecord,
    );
  }
}

Leaderboard sampleBoard(LeaderboardWindow window, {bool empty = false}) =>
    Leaderboard(
      window: window,
      ranked:
          empty
              ? const []
              : [
                LeaderboardRow(
                  rank: 1,
                  person: card(
                    'user_ace',
                    'Ace Caller',
                    record(correct: 47, incorrect: 3, accuracy: 0.94),
                  ),
                ),
              ],
      building:
          empty
              ? const []
              : [
                LeaderboardRow(
                  rank: null,
                  person: card('user_new', 'New Caller', record(correct: 4)),
                ),
              ],
      viewer: LeaderboardRow(
        rank: null,
        person: card(_viewer, 'You', record(correct: 1, incorrect: 1)),
      ),
      minimumDecided: 10,
      rule: 'Ranked by accuracy on at least 10 calls the venue decided.',
      servedAt: 0,
    );

Future<CallsProvider> signedIn(PeopleFake repo) async {
  final provider = CallsProvider(repository: repo)..setViewer(_viewer);
  addTearDown(provider.dispose);
  return provider;
}

Widget withCalls(CallsProvider provider, Widget child) =>
    ChangeNotifierProvider<CallsProvider>.value(value: provider, child: child);

void main() {
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Load the bundled body fonts before any frame, so a chip changing
    // weight mid-test is not a font arriving mid-paint.
    GoogleFonts.montserrat(fontSize: 12, fontWeight: FontWeight.w500);
    GoogleFonts.montserrat(fontSize: 14);
    callJourneyBody();
    AppTextStyles.textTheme;
    AppTextStyles.sheetAction;
    await GoogleFonts.pendingFonts();
  });

  group('provider', () {
    test(
      'caches each window and forgets everything on an account change',
      () async {
        final repo = PeopleFake()..board = sampleBoard;
        final provider = await signedIn(repo);
        expect(provider.supportsPeople, isTrue);
        await provider.loadLeaderboard(LeaderboardWindow.month);
        await provider.loadLeaderboard(LeaderboardWindow.month);
        expect(repo.leaderboardRequests, [LeaderboardWindow.month]);
        expect(
          provider.leaderboard(LeaderboardWindow.month)!.ranked,
          hasLength(1),
        );

        provider.setViewer('user_someone_else');
        expect(provider.leaderboard(LeaderboardWindow.month), isNull);
        expect(provider.topCalls, isNull);
        expect(provider.following, isNull);
      },
    );

    test(
      'the seeded mock has no people layer, so nothing is invented',
      () async {
        final provider = CallsProvider(repository: MockCallsRepository());
        addTearDown(provider.dispose);
        expect(provider.supportsPeople, isFalse);
        await provider.loadLeaderboard(LeaderboardWindow.all);
        await provider.loadTopCalls();
        expect(provider.leaderboard(LeaderboardWindow.all), isNull);
        expect(provider.topCalls, isNull);
      },
    );

    test(
      'a follow change discards a Following read already in flight',
      () async {
        final repo = _SlowFollowingFake();
        final provider = await signedIn(repo);
        final pending = provider.loadFollowing();
        expect(provider.isLoadingFollowing, isTrue);

        final target =
            (await repo.fetchFeed(
              mode: CallFeedMode.global,
            )).entries.firstWhere((e) => e.author.id != _viewer).author;
        await provider.loadPerson(target.id);
        await provider.setFollowing(provider.personDetail(target.id)!, true);

        // The read that started before the follow answers with the old list.
        repo.gate.complete(const []);
        await pending;
        expect(provider.following, isNull, reason: 'stale membership kept');
        expect(provider.isLoadingFollowing, isFalse);
      },
    );
  });

  group('Leaderboard', () {
    testWidgets('ranks only the sample, pins your row, switches windows', (
      tester,
    ) async {
      final repo = PeopleFake()..board = sampleBoard;
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const Scaffold(body: LeaderboardView())),
        width: 390,
        scale: 1,
      );

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('Ace Caller'), findsOneWidget);
      expect(find.text('94%'), findsOneWidget);
      // Below the sample: listed, unnumbered, no percentage.
      expect(find.text('Building a record'), findsOneWidget);
      expect(
        find.text('4/4 correct · 6 more decided calls to rank'),
        findsOneWidget,
      );
      expect(find.text('#2'), findsNothing);
      // The pinned row is the viewer's, with what they still need.
      expect(find.text('Not ranked yet'), findsOneWidget);
      expect(
        find.textContaining('8 more decided calls to rank'),
        findsOneWidget,
      );
      expect(find.textContaining('PnL'), findsNothing);
      expect(find.textContaining('USDC'), findsNothing);

      await tester.tap(find.text('7D'));
      await tester.pumpAndSettle();
      expect(repo.leaderboardRequests.last, LeaderboardWindow.week);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty window says so and offers all time', (tester) async {
      final repo = PeopleFake()..board = (w) => sampleBoard(w, empty: true);
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const Scaffold(body: LeaderboardView())),
      );
      await revealPeopleText(tester, 'Show all time');
      expect(find.text('No records in the last 30 days yet'), findsOneWidget);
      await tester.tap(find.text('Show all time'));
      await tester.pumpAndSettle();
      expect(repo.leaderboardRequests.last, LeaderboardWindow.all);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      final repo = PeopleFake()..board = sampleBoard;
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const Scaffold(body: LeaderboardView())),
      );
      expect(find.text('Ace Caller'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('appears as a Friends hub tab only with the live capability', (
      tester,
    ) async {
      final repo =
          PeopleFake()
            ..board = sampleBoard
            ..follows = [card('user_ada', 'Ada Okafor', record())];
      final provider = await signedIn(repo);
      final arena = QuietArena();
      addTearDown(arena.dispose);
      await mountPeople(
        tester,
        friendsScreen(),
        wrap: (child) => hub(provider, arena, child),
      );
      // The record-based board, one tap away on the header's award icon,
      // and never the Arena's wealth ranking.
      expect(find.byTooltip('Leaderboard'), findsOneWidget);
      expect(arena.leaderboardLoads, 0);

      // Adding a friend follows them: the people you follow ARE the Friends
      // list, so there is no separate Following tab to explain.
      expect(find.text('Following'), findsNothing);
      await revealPeopleText(tester, 'Ada Okafor');
      expect(find.text('Ada Okafor'), findsOneWidget);

      await tester.tap(find.byTooltip('Leaderboard'));
      await tester.pumpAndSettle();
      expect(find.byType(LeaderboardScreen), findsOneWidget);
      expect(find.text('Ace Caller'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Top calls on Home', () {
    TopCall topCall(CallFeedEntry entry, {TopCallSplit? split}) => TopCall(
      call: entry.call,
      author: card(entry.author.id, entry.author.displayName, record()),
      market: entry.market,
      responses: 3,
      split: split,
      viewerHasCalled: split != null,
    );

    testWidgets('direction-free until the viewer has called', (tester) async {
      final repo = PeopleFake();
      final seed = (await repo.fetchFeed(
        mode: CallFeedMode.global,
      )).entries.firstWhere((e) => e.author.id != _viewer);
      repo.top = [topCall(seed)];
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const CallFeedScreen(showHeader: false)),
        width: 390,
        scale: 1,
      );
      expect(find.text('Top calls'), findsOneWidget);
      expect(find.text('3 responses'), findsOneWidget);
      expect(find.textContaining('back ·'), findsNothing);

      repo.top = [topCall(seed, split: const TopCallSplit(backs: 2, fades: 1))];
      await provider.loadTopCalls(force: true);
      await tester.pumpAndSettle();
      expect(find.text('3 responses · 2 back · 1 fade'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nothing real, nothing shown', (tester) async {
      final repo = PeopleFake();
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const CallFeedScreen(showHeader: false)),
      );
      expect(find.text('Top calls'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      final repo = PeopleFake();
      final seed = (await repo.fetchFeed(
        mode: CallFeedMode.global,
      )).entries.firstWhere((e) => e.author.id != _viewer);
      repo.top = [topCall(seed), topCall(seed)];
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const CallFeedScreen(showHeader: false)),
      );
      expect(find.text('Top calls'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty Following feed still shows the strip, at 320dp/2x', (
      tester,
    ) async {
      final repo = _EmptyFollowingFake();
      final seed = (await repo.fetchFeed(
        mode: CallFeedMode.global,
      )).entries.firstWhere((e) => e.author.id != _viewer);
      repo.top = [topCall(seed)];
      final provider = await signedIn(repo);
      provider.setFeedMode(CallFeedMode.following);
      await mountPeople(
        tester,
        withCalls(provider, const CallFeedScreen(showHeader: false)),
      );
      expect(provider.feed, isEmpty);
      expect(find.text('Top calls'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('locking a call on a top call’s market re-reads the strip', () async {
      final repo = PeopleFake();
      final provider = await signedIn(repo);
      final seed = (await repo.fetchFeed(
        mode: CallFeedMode.global,
        viewerUserId: _viewer,
      )).entries.firstWhere(
        (e) => e.author.id != _viewer && !e.viewerHasCalled,
      );
      repo.top = [topCall(seed)];
      await provider.loadTopCalls();
      expect(repo.topRequests, 1);

      // Calling elsewhere leaves the strip alone.
      final elsewhere = (await repo.fetchOpenMarkets()).firstWhere(
        (m) => m.id != seed.market.id,
      );
      await provider.createCall(
        CreateCallInput(marketId: elsewhere.id, side: Side.yes),
      );
      await pumpEventQueue();
      expect(repo.topRequests, 1);

      // Calling on its market opens the split gate: the strip is read again.
      await provider.createCall(
        CreateCallInput(marketId: seed.market.id, side: Side.yes),
      );
      await pumpEventQueue();
      expect(repo.topRequests, 2);
    });
  });

  group('trader profile', () {
    testWidgets('credibility strip, follow counts, Open and Settled', (
      tester,
    ) async {
      final repo =
          PeopleFake()
            ..personRecord = record(correct: 3, incorrect: 1, pending: 2)
            ..followers = 12
            ..followingCount = 3;
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const CallPersonScreen(personRef: 'user_ada')),
        width: 390,
        scale: 1,
      );
      expect(find.text('12 followers · 3 following'), findsOneWidget);
      expect(find.text('3/4'), findsOneWidget);
      // Four decided is below the sample: no percentage, and it says why.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('accuracy after 10 decided'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CredibilityStrip),
          matching: find.textContaining('%'),
        ),
        findsNothing,
      );

      final detail = provider.personDetail('user_ada')!;
      final open = detail.calls.where((e) => !e.outcome.isSettled).length;
      final settled = detail.calls.where((e) => e.outcome.isSettled).length;
      expect(find.text('Open · $open'), findsOneWidget);
      await revealPeopleText(tester, 'Settled · $settled');
      await tester.tap(find.text('Settled · $settled'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      final repo =
          PeopleFake()
            ..personRecord = record(correct: 9, incorrect: 3, accuracy: 0.75)
            ..followers = 1
            ..followingCount = 0;
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const CallPersonScreen(personRef: 'user_ada')),
      );
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('1 follower · 0 following'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('thesis thread', () {
    testWidgets('the author appends; the original reason stays as locked', (
      tester,
    ) async {
      final repo = PeopleFake();
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        const CallDetailScreen(callId: 'call_you_fed'),
        wrap: (app) => withCalls(provider, app),
        width: 390,
        scale: 1,
      );
      final original = provider.callDetail('call_you_fed')!.entry.call.thesis;
      await revealPeopleText(tester, 'Add an update');
      await tester.tap(find.text('Add an update'));
      await tester.pumpAndSettle();
      expect(find.byType(ThesisUpdateSheet), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Dot plot moved my way.');
      await tester.pump();
      await tester.tap(find.text('Post update'));
      await tester.pumpAndSettle();

      expect(repo.posted, ['Dot plot moved my way.']);
      expect(find.byType(ThesisUpdateSheet), findsNothing);
      expect(find.text('Dot plot moved my way.'), findsOneWidget);
      expect(find.textContaining('after locking'), findsOneWidget);
      final after = provider.callDetail('call_you_fed')!;
      expect(after.entry.call.thesis, original);
      expect(after.updates.single.body, 'Dot plot moved my way.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('readers see the thread but cannot add to it', (tester) async {
      final repo = PeopleFake();
      repo.updates['call_ada_btc'] = [
        ThesisUpdate(
          id: 'u1',
          callId: 'call_ada_btc',
          authorUserId: 'user_ada',
          body: 'ETF flows still accelerating.',
          createdAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      ];
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        const CallDetailScreen(callId: 'call_ada_btc'),
        wrap: (app) => withCalls(provider, app),
      );
      await revealPeopleText(tester, 'ETF flows still accelerating.');
      expect(find.text('Add an update'), findsNothing);
      expect(find.text('Add another update'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no action when the server cannot take updates', (
      tester,
    ) async {
      final repo = PeopleFake()..updatesAvailable = false;
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        const CallDetailScreen(callId: 'call_you_fed'),
        wrap: (app) => withCalls(provider, app),
      );
      expect(find.text('Add an update'), findsNothing);
      expect(find.text('Thesis updates'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('an update after the venue result says so', () {
      final locked = DateTime.utc(2026, 10, 1, 12);
      final resolved = DateTime.utc(2026, 10, 3, 12);
      expect(
        ThesisThread.caption(locked, null, DateTime.utc(2026, 10, 1, 14)),
        '2h after locking',
      );
      expect(
        ThesisThread.caption(locked, resolved, DateTime.utc(2026, 10, 2, 12)),
        '24h after locking',
      );
      expect(
        ThesisThread.caption(locked, resolved, DateTime.utc(2026, 10, 5, 12)),
        '4d after locking · after the result',
      );
    });

    testWidgets('an unreadable reply keeps the draft and warns, not retries', (
      tester,
    ) async {
      final repo = _UnreadableUpdateFake();
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        const CallDetailScreen(callId: 'call_you_fed'),
        wrap: (app) => withCalls(provider, app),
        width: 390,
        scale: 1,
      );
      await revealPeopleText(tester, 'Add an update');
      await tester.tap(find.text('Add an update'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Dot plot moved my way.');
      await tester.pump();
      await tester.tap(find.text('Post update'));
      await tester.pumpAndSettle();

      // The sheet stays, the draft stays, and the reason says the server may
      // already have it — never a silent no-op that invites a duplicate.
      expect(find.byType(ThesisUpdateSheet), findsOneWidget);
      expect(find.text('Dot plot moved my way.'), findsWidgets);
      expect(
        find.textContaining('couldn’t confirm that update'),
        findsOneWidget,
      );
      expect(provider.isSubmitting, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('search', () {
    testWidgets('people from the directory and markets from the catalog', (
      tester,
    ) async {
      final repo =
          PeopleFake()..directory = [card('user_ada', 'Ada Okafor', record())];
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const PeopleSearchScreen(debounce: Duration.zero)),
        width: 390,
        scale: 1,
      );
      // Idle: the search scene and one line, not instructions.
      expect(find.text('Find people and markets'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ada');
      await tester.pumpAndSettle();
      expect(find.text('Ada Okafor'), findsOneWidget);

      final market = provider.openMarkets.first;
      final word = market.question.split(' ').firstWhere((w) => w.length > 3);
      await tester.enterText(find.byType(TextField), word);
      await tester.pumpAndSettle();
      expect(find.text('Markets'), findsOneWidget);
      expect(find.textContaining('No open market asks'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits 320dp at 2x text', (tester) async {
      final repo =
          PeopleFake()..directory = [card('user_ada', 'Ada Okafor', record())];
      final provider = await signedIn(repo);
      await mountPeople(
        tester,
        withCalls(provider, const PeopleSearchScreen(debounce: Duration.zero)),
      );
      await tester.enterText(find.byType(TextField), 'ada');
      await tester.pumpAndSettle();
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

/// A viewer who follows nobody yet: the Following feed is empty.
class _EmptyFollowingFake extends PeopleFake {
  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) async {
    if (mode == CallFeedMode.following) {
      return const CallFeedPage(entries: [], servedAt: 0);
    }
    return super.fetchFeed(
      mode: mode,
      viewerUserId: viewerUserId,
      cursor: cursor,
      limit: limit,
    );
  }
}

/// The server accepts the update but answers with something the app cannot
/// read (here, the client's own vocabulary guard).
class _UnreadableUpdateFake extends PeopleFake {
  @override
  Future<ThesisUpdate> appendThesisUpdate({
    required String callId,
    required String body,
  }) async {
    await super.appendThesisUpdate(callId: callId, body: body);
    throw const CallVocabularyException(
      'The update was recorded against a different call.',
    );
  }
}

/// A Following read that answers only when the test says so.
class _SlowFollowingFake extends PeopleFake {
  final gate = Completer<List<PersonCard>>();

  @override
  Future<List<PersonCard>> fetchFollowing() => gate.future;
}
