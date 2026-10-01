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
    createNewChallenge: () {},
    onFriendSelected: (_, __) {},
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
              onFriendSelected: (name) => selected = name,
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
    'Friends uses quiet header and Following instead of wealth rankings',
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
      expect(find.text('Leaderboard'), findsNothing);
      expect(arena.leaderboardLoads, 0);
      await revealPeopleText(tester, 'Following');
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('People in your Following feed'), findsOneWidget);
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(find.textContaining('win rate'), findsNothing);
      expect(tester.takeException(), isNull);
      await revealPeopleText(tester, 'Ada Okafor');
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
      expect(
        find.textContaining('DEMO DATA · Free invitation · no payment'),
        findsOneWidget,
      );
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invitation and Following failures stay retryable, not empty success',
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
      expect(find.text('Call invitations unavailable'), findsOneWidget);
      await revealPeopleText(tester, 'Following');
      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(find.text('Following unavailable'), findsOneWidget);
      repository.unavailable = false;
      await revealPeopleText(tester, 'Try again');
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Ada Okafor'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
