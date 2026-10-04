import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/features/calls/data/calls_repository.dart';
import 'package:chumbucket/features/calls/data/call_models.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_grid.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_hub_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/header.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/data/people_repository.dart'
    as people;
import 'package:chumbucket/shared/widgets/chumbucket_sheet_actions.dart';
import 'package:chumbucket/shared/widgets/chumbucket_state_art.dart';
import 'ui_people_layout_profile_test.dart'
    show mountPeople, PeopleRepository, peopleEntry, revealPeopleText;

class QuietArena extends ChangeNotifier implements ArenaProvider {
  @override
  int get unreadNotificationCount => 0;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int leaderboardLoads = 0;
  @override
  Future<void> loadHotCallers() async {
    leaderboardLoads++;
  }
}

class QuietWallet extends ChangeNotifier implements MwaWalletProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FriendsRepository extends PeopleRepository {
  FriendsRepository() : super([]);
  bool unavailable = false;
  bool invite = false;
  final source = peopleEntry('source', CallOutcome.pending, demo: true);
  @override
  Future<CallFeedPage> fetchFeed({
    required CallFeedMode mode,
    String? viewerUserId,
    String? cursor,
    int limit = 20,
  }) async {
    if (unavailable) throw const CallsOfflineException();
    return CallFeedPage(entries: [source], servedAt: 0);
  }

  @override
  Future<List<ChallengeInvitation>> fetchInvitations({
    required String? viewerUserId,
  }) async {
    if (unavailable) throw const CallsOfflineException();
    return invite
        ? [
          ChallengeInvitation(
            id: 'invitation',
            fromUserId: source.author.id,
            toUserId: viewerUserId!,
            marketId: source.market.id,
            sourceCallId: source.call.id,
            responseId: 'response',
            createdAt: 0,
          ),
        ]
        : [];
  }

  @override
  Future<CallDetail> fetchCall({
    required String callId,
    String? viewerUserId,
  }) async => CallDetail(entry: source);
}

Widget hub(CallsProvider calls, QuietArena arena, Widget child) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: calls),
        ChangeNotifierProvider<ArenaProvider>.value(value: arena),
        ChangeNotifierProvider<MwaAuthProvider>(
          create: (_) => MwaAuthProvider(),
        ),
        ChangeNotifierProvider<MwaWalletProvider>(create: (_) => QuietWallet()),
      ],
      child: child,
    );

Widget friendsScreen() => Scaffold(
  body: FriendsHubTab(
    refreshKey: 0,
    onAddFriend: () {},
    onFriendSelected: (_) {},
    buildViewMoreItem: (_, count) => Text('View $count more'),
    onViewAllChallenges: () {},
    onMarkChallengeCompleted: (_, __) async {},
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
    'friendly grid keeps names, callbacks and view more at narrow 2x',
    (tester) async {
      String? selected;
      var viewMore = false;
      final friends = List.generate(
        7,
        (index) => <String, String>{
          'name': 'Friend $index',
          'xLabel': 'A familiar friend $index',
          'imagePath': 'assets/images/ai_gen/profile_images/1.png',
        },
      );
      await mountPeople(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: FriendsGrid(
              friends: friends,
              onFriendSelected: (friend) => selected = friend['name'],
              buildViewMoreItem:
                  (_, count) =>
                      Text('View $count more', textAlign: TextAlign.center),
              onViewMorePressed: () => viewMore = true,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('A familiar friend 0'));
      expect(selected, 'Friend 0');
      await tester.ensureVisible(find.text('View 2 more'));
      await tester.tap(find.text('View 2 more'));
      expect(viewMore, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty grid has a real add-friend action', (tester) async {
    var added = false;
    await mountPeople(
      tester,
      Scaffold(
        body: FriendsGrid(
          friends: const [],
          onFriendSelected: (_) {},
          buildViewMoreItem: (_, __) => const SizedBox.shrink(),
          onAddFriend: () => added = true,
        ),
      ),
    );
    expect(find.text('Bring your people'), findsOneWidget);
    await tester.tap(find.text('Add a friend'));
    expect(added, isTrue);
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Friends uses a quiet header and one list of people, no wealth rankings',
    (tester) async {
      final repository = FriendsRepository();
      final calls = CallsProvider(repository: repository)..setViewer('viewer');
      final arena = QuietArena();
      addTearDown(calls.dispose);
      addTearDown(arena.dispose);
      await mountPeople(
        tester,
        friendsScreen(),
        wrap: (child) => hub(calls, arena, child),
      );
      expect(
        tester
            .widget<ChumbucketAppHeader>(find.byType(ChumbucketAppHeader))
            .showAccountActions,
        isFalse,
      );
      // No people layer in this build: no ranking, and no second tab that
      // lists the same people under another name.
      expect(find.byTooltip('Leaderboard'), findsNothing);
      expect(find.text('Following'), findsNothing);
      expect(arena.leaderboardLoads, 0);
      // No explanatory paragraphs.
      expect(find.textContaining('Following is separate'), findsNothing);
      expect(find.textContaining('Friends you add'), findsNothing);
      await revealPeopleText(tester, 'Ada Okafor');
      expect(find.textContaining('win rate'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.text('Ada Okafor').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Ada Okafor'));
      await tester.pumpAndSettle();
      expect(find.byType(CallPersonScreen), findsOneWidget);
      expect(repository.requestedPeople.last, 'user_ada');
    },
  );

  testWidgets(
    'real invitation is contextual and clearly free, no invented acceptance',
    (tester) async {
      final repository = FriendsRepository()..invite = true;
      final calls = CallsProvider(repository: repository)..setViewer('viewer');
      final arena = QuietArena();
      addTearDown(calls.dispose);
      addTearDown(arena.dispose);
      await mountPeople(
        tester,
        friendsScreen(),
        wrap: (child) => hub(calls, arena, child),
      );
      expect(find.text('Ada Okafor invited you to call'), findsOneWidget);
      expect(find.textContaining('DEMO DATA · '), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed read stays quiet, never an empty success, and a pull reads again',
    (tester) async {
      final repository = FriendsRepository()..unavailable = true;
      final calls = CallsProvider(repository: repository)..setViewer('viewer');
      final arena = QuietArena();
      addTearDown(calls.dispose);
      addTearDown(arena.dispose);
      await mountPeople(
        tester,
        friendsScreen(),
        wrap: (child) => hub(calls, arena, child),
      );
      // No error card, no retry button, no "nobody yet" scene either.
      expect(find.textContaining('unavailable'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Add friends to see their calls'), findsNothing);
      expect(find.text('Add a friend'), findsOneWidget);
      repository.unavailable = false;
      await tester.fling(
        find.byType(RefreshIndicator).first,
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a Google or X account (no wallet) can add a friend from Friends',
    (tester) async {
      final calls = CallsProvider(repository: FriendsRepository())
        ..setViewer('viewer');
      final arena = QuietArena();
      addTearDown(calls.dispose);
      addTearDown(arena.dispose);
      var adds = 0;
      await mountPeople(
        tester,
        Scaffold(
          body: FriendsHubTab(
            refreshKey: 0,
            onAddFriend: () => adds++,
            onFriendSelected: (_) {},
            buildViewMoreItem: (_, count) => Text('View $count more'),
            onViewAllChallenges: () {},
            onMarkChallengeCompleted: (_, __) async {},
          ),
        ),
        wrap: (child) => hub(calls, arena, child),
      );
      // No wallet is connected, and the action is still there, first.
      await revealPeopleText(tester, 'Add a friend');
      expect(find.text('Add a friend').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Add a friend'));
      expect(adds, 1);
      // Nothing about the old app's wallet friends, and no account link.
      expect(find.textContaining('wallet is connected'), findsNothing);
      expect(find.text('Account settings'), findsNothing);
      // The old add-by-handle queue is gone: nothing promises a join.
      expect(find.text('Waiting to join'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nobody yet: the people scene, one line, one Add a friend button',
    (tester) async {
      final repository = FollowsRepository();
      final calls = CallsProvider(repository: repository)..setViewer('viewer');
      final arena = QuietArena();
      addTearDown(calls.dispose);
      addTearDown(arena.dispose);
      var adds = 0;
      await mountPeople(
        tester,
        Scaffold(
          body: FriendsHubTab(
            refreshKey: 0,
            onAddFriend: () => adds++,
            onFriendSelected: (_) {},
            buildViewMoreItem: (_, count) => Text('View $count more'),
            onViewAllChallenges: () {},
            onMarkChallengeCompleted: (_, __) async {},
          ),
        ),
        wrap: (child) => hub(calls, arena, child),
      );
      expect(find.byTooltip('Leaderboard'), findsOneWidget);
      expect(find.text('Add friends to see their calls'), findsOneWidget);
      expect(find.byType(ChumbucketStateArt), findsOneWidget);
      await tester.tap(
        find.widgetWithText(ChumbucketPrimaryButton, 'Add a friend'),
      );
      expect(adds, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the people you follow are the Friends list, with records', (
    tester,
  ) async {
    final repository =
        FollowsRepository()
          ..follows = [
            PersonCard(
              id: 'user_kemi',
              handle: 'kemi',
              displayName: 'Kemi Balogun',
              record: const PublicRecord(
                correct: 6,
                incorrect: 2,
                voided: 0,
                decided: 8,
                pending: 1,
                minimumDecided: 10,
              ),
            ),
          ];
    final calls = CallsProvider(repository: repository)..setViewer('viewer');
    final arena = QuietArena();
    addTearDown(calls.dispose);
    addTearDown(arena.dispose);
    await mountPeople(
      tester,
      friendsScreen(),
      width: 390,
      scale: 1,
      wrap: (child) => hub(calls, arena, child),
    );
    expect(find.text('Add a friend'), findsOneWidget);
    expect(find.text('Kemi Balogun'), findsOneWidget);
    expect(find.text('Add friends to see their calls'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// The live people layer's follow list, over the seeded mock.
class FollowsRepository extends FriendsRepository
    implements people.PeopleRepository {
  List<PersonCard> follows = const [];

  @override
  Future<List<PersonCard>> fetchFollowing() async => follows;

  @override
  Future<Leaderboard> fetchLeaderboard({
    required LeaderboardWindow window,
    int limit = 50,
  }) async => Leaderboard(
    window: window,
    ranked: const [],
    building: const [],
    viewer: null,
    minimumDecided: 10,
    rule: 'Ranked by accuracy.',
    servedAt: 0,
  );

  @override
  Future<List<PersonCard>> searchPeople(String query, {int limit = 20}) async =>
      const [];

  @override
  Future<List<TopCall>> fetchTopCalls({int limit = 10}) async => const [];

  @override
  Future<ThesisUpdate> appendThesisUpdate({
    required String callId,
    required String body,
  }) => throw UnimplementedError();
}
