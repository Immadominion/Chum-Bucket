// Opt-in captures of the art-led states and the Activity / Friends / Profile
// screens (package ux-states), with the real fonts and synthetic data, at
// 390dp and at 320dp with 2x text. Writes nothing unless asked:
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_UX_STATES=/abs/output/dir \
//   test/ux_states_visual_capture_test.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/core/theme/app_colors.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_person_screen.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:http/testing.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/notifications/data/mock_notifications_repository.dart';
import 'package:chumbucket/features/notifications/data/notifications_repository.dart';
import 'package:chumbucket/features/notifications/presentation/screens/activity_screen.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:chumbucket/features/people/data/people_models.dart';
import 'package:chumbucket/features/people/presentation/search_screen.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/trust/presentation/legacy_history_screen.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';

import 'panta_lifecycle_test.dart' show pageJson, positionJson;
import 'panta_trading_controller_test.dart' show syntheticTime, syntheticWire;
import 'people_layer_ui_test.dart' show PeopleFake, card, record, sampleBoard;
import 'ui_people_layout_continuity_test.dart'
    show ConnectedAuth, ConnectedWallet, ExistingProfile, walletFixture;
import 'ui_people_layout_friends_test.dart' show QuietArena, friendsScreen;

const _viewer = MockCallsRepository.demoViewerUserId;

void _noop() {}

/// Home's tabs sit on the app's grey canvas, not a white Scaffold: draw the
/// capture the way the phone does, so white rows read as rows.
Widget _onCanvas(Widget child) => Theme(
  data: AppTheme.lightTheme.copyWith(
    scaffoldBackgroundColor: AppColors.background,
  ),
  child: child,
);

class _EmptyInbox implements NotificationsRepository {
  @override
  Future<NotificationPage> fetchNotifications({
    required String? viewerUserId,
    NotificationFilter filter = NotificationFilter.all,
    String? cursor,
    int limit = 20,
  }) async => NotificationPage(
    notifications: const [],
    servedAt: DateTime.now().millisecondsSinceEpoch,
    unreadCount: 0,
  );

  @override
  Future<int> unreadCount({required String? viewerUserId}) async => 0;

  @override
  Future<void> markAllRead({required String? viewerUserId}) async {}

  @override
  Future<void> markRead({
    required String? viewerUserId,
    required String notificationId,
  }) async {}
}

class _Account implements AccountApi {
  @override
  Future<AccountProfile> me() async => const AccountProfile(
    userId: _viewer,
    displayName: 'Ada Okafor',
    handle: 'ada',
    avatarId: 2,
    bio: 'Macro nerd. Calls on rates and BTC.',
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoWallet extends MwaAuthProvider {
  @override
  String? get walletAddress => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outDir = String.fromEnvironment('CAPTURE_UX_STATES');
  setUpAll(() async {
    if (outDir.isEmpty) return;
    AppConfig.initialize();
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final (family, paths) in [
      (
        'PPNeueMachina',
        [
          'assets/fonts/PPNeueMachina/PPNeueMachina-Regular.otf',
          'assets/fonts/PPNeueMachina/PPNeueMachina-Ultrabold.otf',
        ],
      ),
      (
        'Montserrat',
        [
          'assets/fonts/Montserrat/Montserrat-Regular.ttf',
          'assets/fonts/Montserrat/Montserrat-Medium.ttf',
        ],
      ),
      (
        'Montserrat_regular',
        ['assets/fonts/Montserrat/Montserrat-Regular.ttf'],
      ),
      ('Montserrat_medium', ['assets/fonts/Montserrat/Montserrat-Medium.ttf']),
      ('Inter_regular', ['assets/fonts/Inter/Inter-Regular.ttf']),
      ('Inter_500', ['assets/fonts/Inter/Inter-Medium.ttf']),
      ('Inter_600', ['assets/fonts/Inter/Inter-SemiBold.ttf']),
      ('Inter_700', ['assets/fonts/Inter/Inter-Bold.ttf']),
      ('Inter_800', ['assets/fonts/Inter/Inter-ExtraBold.ttf']),
    ]) {
      final loader = FontLoader(family);
      for (final path in paths) {
        loader.addFont(rootBundle.load(path));
      }
      await loader.load();
    }
  });

  Future<void> mount(
    WidgetTester tester,
    Widget home, {
    double width = 390,
    double height = 844,
    double scale = 1,
    Widget Function(Widget app)? above,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(Widget child) => above?.call(child) ?? child;
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('ux-states-capture'),
        child: app(
          ScreenUtilInit(
            key: UniqueKey(),
            designSize: const Size(390, 844),
            builder:
                (_, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme,
                  builder:
                      (context, inner) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(textScaler: TextScaler.linear(scale)),
                        child: inner!,
                      ),
                  home: home,
                ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('ux-states-capture')),
      matchesGoldenFile(Uri.file('$outDir/ux-$name.png')),
    );
    expect(tester.takeException(), isNull);
  }

  /// Both sizes the owner reviews: a 390dp phone, and 320dp at 2x text.
  Future<void> both(
    WidgetTester tester,
    String name,
    Widget Function() build, {
    double height = 844,
    Future<void> Function()? then,
    Widget Function(Widget app) Function()? above,
  }) async {
    await mount(tester, build(), height: height, above: above?.call());
    if (then != null) await then();
    await capture(tester, name);
    await mount(
      tester,
      build(),
      width: 320,
      height: height,
      scale: 2,
      above: above?.call(),
    );
    if (then != null) await then();
    await capture(tester, '$name-320-2x');
  }

  Widget withInbox(NotificationsProvider inbox) =>
      ChangeNotifierProvider<NotificationsProvider>.value(
        value: inbox,
        child: const ActivityScreen(),
      );

  PeopleFake people({List<PersonCard> follows = const []}) =>
      PeopleFake()
        ..follows = follows
        ..board = sampleBoard
        ..personRecord = null;

  Widget friendsAbove(CallsProvider calls, QuietArena arena, Widget app) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CallsProvider>.value(value: calls),
          ChangeNotifierProvider<ArenaProvider>.value(value: arena),
          ChangeNotifierProvider<MwaAuthProvider>.value(value: _NoWallet()),
          ChangeNotifierProvider<MwaWalletProvider>(
            create: (_) => ConnectedWallet(),
          ),
        ],
        child: _onCanvas(app),
      );

  Widget friends(
    CallsProvider calls,
    QuietArena arena, {
    MwaAuthProvider? auth,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<CallsProvider>.value(value: calls),
      ChangeNotifierProvider<ArenaProvider>.value(value: arena),
      ChangeNotifierProvider<MwaAuthProvider>.value(value: auth ?? _NoWallet()),
      ChangeNotifierProvider<MwaWalletProvider>(
        create: (_) => ConnectedWallet(),
      ),
    ],
    child: _onCanvas(friendsScreen()),
  );

  testWidgets('captures', (tester) async {
    // --- Activity ---------------------------------------------------------
    await both(tester, 'activity', () {
      final inbox = NotificationsProvider(
        repository: MockNotificationsRepository(),
      )..setViewer(_viewer);
      addTearDown(inbox.dispose);
      return withInbox(inbox);
    });
    await both(tester, 'activity-empty', () {
      final inbox = NotificationsProvider(repository: _EmptyInbox())
        ..setViewer(_viewer);
      addTearDown(inbox.dispose);
      return withInbox(inbox);
    });
    await both(tester, 'activity-signed-out', () {
      final inbox = NotificationsProvider(
        repository: MockNotificationsRepository(),
      )..setViewer(null);
      addTearDown(inbox.dispose);
      return withInbox(inbox);
    });
    await both(tester, 'activity-offline', () {
      final repo = MockNotificationsRepository()..simulateOffline = true;
      final inbox = NotificationsProvider(repository: repo)..setViewer(_viewer);
      addTearDown(inbox.dispose);
      return withInbox(inbox);
    });

    // --- Friends ----------------------------------------------------------
    final arena = QuietArena();
    addTearDown(arena.dispose);
    await both(tester, 'friends-empty', () {
      final calls = CallsProvider(repository: people())..setViewer(_viewer);
      addTearDown(calls.dispose);
      return friends(calls, arena);
    });
    await both(tester, 'friends-signed-out', () {
      final calls = CallsProvider(repository: people());
      addTearDown(calls.dispose);
      return friends(calls, arena);
    });
    final follows = [
      card('user_ace', 'Ace Caller', record(correct: 47, incorrect: 3)),
      card('user_kemi', 'Kemi Balogun', record(correct: 6, incorrect: 2)),
      card('user_zed', 'Zed', record(correct: 1, incorrect: 0, pending: 2)),
    ];
    await both(tester, 'friends-following', () {
      final calls = CallsProvider(repository: people(follows: follows))
        ..setViewer(_viewer);
      addTearDown(calls.dispose);
      return friends(calls, arena);
    });
    await both(
      tester,
      'friends-leaderboard',
      friendsScreen,
      above: () {
        final calls = CallsProvider(repository: people(follows: follows))
          ..setViewer(_viewer);
        addTearDown(calls.dispose);
        return (app) => friendsAbove(calls, arena, app);
      },
      then: () async {
        await tester.tap(find.byTooltip('Leaderboard'));
        await tester.pumpAndSettle();
      },
    );

    // --- Profile ----------------------------------------------------------
    Widget profile(ChallengeStateProvider escrows, {MwaAuthProvider? auth}) {
      final calls = CallsProvider(repository: people())..setViewer(_viewer);
      final wallet = ConnectedWallet();
      final existing = ExistingProfile();
      for (final n in <ChangeNotifier>[calls, wallet, existing]) {
        addTearDown(n.dispose);
      }
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileProvider>.value(value: existing),
          ChangeNotifierProvider<MwaAuthProvider>.value(
            value: auth ?? ConnectedAuth(),
          ),
          ChangeNotifierProvider<MwaWalletProvider>.value(value: wallet),
          ChangeNotifierProvider<CallsProvider>.value(value: calls),
          ChangeNotifierProvider<ChallengeStateProvider>.value(value: escrows),
          ChangeNotifierProvider<ArenaProvider>.value(value: arena),
          Provider<AccountApi>.value(value: _Account()),
        ],
        child: ProfileScreen(embedded: true, onOpenChallenges: () {}),
      );
    }

    final open = ChallengeStateProvider(
      loadChallenges:
          (_) async => [
            Challenge(
              id: 'escrow-open',
              creatorId: 'CHaLLenGer11111111111111111111111111111111',
              member1Address: 'CHaLLenGer11111111111111111111111111111111',
              witnessAddress: walletFixture,
              title: 'Run 5k every morning',
              description: 'Run 5k every morning',
              amount: .05,
              platformFee: .00125,
              winnerAmount: .04875,
              createdAt: DateTime.utc(2026, 1, 3),
              expiresAt: DateTime.utc(2026, 2, 3),
              status: ChallengeStatus.active,
              escrowAddress: '8aoA32Bx1111111111111111111111111111111111',
            ),
          ],
    );
    addTearDown(open.dispose);
    await open.initialize(walletFixture);
    await both(tester, 'profile', () => profile(open), height: 1500);

    final none = ChallengeStateProvider(loadChallenges: (_) async => []);
    addTearDown(none.dispose);
    await none.initialize(walletFixture);
    await both(
      tester,
      'profile-positions',
      () => profile(none),
      height: 1100,
      then: () async {
        await tester.tap(find.text('Positions'));
        await tester.pumpAndSettle();
      },
    );

    // --- Settings → History, Search ---------------------------------------
    await both(
      tester,
      'history',
      () => LegacyHistoryScreen(onOpenEscrowChallenges: () {}),
    );
    await both(tester, 'search', () {
      final calls = CallsProvider(repository: people());
      addTearDown(calls.dispose);
      return ChangeNotifierProvider<CallsProvider>.value(
        value: calls,
        child: const PeopleSearchScreen(),
      );
    });
  }, skip: outDir.isEmpty);

  testWidgets(
    'captures: positions, offline Home, signed-out Profile, dares',
    (tester) async {
      // --- Positions with money in them -------------------------------------
      // A pending order keeps a refresh timer: dispose inside the test body.
      final disposeAtEnd = <void Function()>[];
      PantaPositionsController positions() {
        final client = PantaTradingClient(
          baseUri: Uri.parse('https://bff.invalid/trpc'),
          session:
              () => const PantaSession(
                accountId: 'acct',
                accessToken: 'synthetic-token',
              ),
          client: MockClient(
            (_) async => syntheticWire(
              pageJson([
                positionJson(),
                positionJson(
                  orderId: 'ord_won',
                  status: 'won_claimable',
                  current: '1',
                  value: '4000000',
                  pnl: '2000000',
                ),
                positionJson(
                  orderId: 'ord_pending',
                  status: 'pending',
                  current: null,
                  value: null,
                  pnl: null,
                ),
              ]),
            ),
          ),
        );
        final controller = PantaPositionsController(
          client: client,
          signerFor: (_, _) => null,
          now: () => DateTime.fromMillisecondsSinceEpoch(syntheticTime),
          refreshEvery: const Duration(hours: 1),
        );
        disposeAtEnd.add(() {
          controller.dispose();
          client.close();
        });
        return controller;
      }

      await both(
        tester,
        'positions-data',
        () => Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: PantaPositionsView(controller: positions()),
          ),
        ),
        height: 1400,
      );

      // --- Home, offline over saved calls -------------------------------------
      await both(
        tester,
        'home-offline',
        () {
          final repo = MockCallsRepository(latency: Duration.zero);
          final calls = CallsProvider(repository: repo)..setViewer(_viewer);
          addTearDown(calls.dispose);
          return ChangeNotifierProvider<CallsProvider>.value(
            value: calls,
            child: const Scaffold(
              backgroundColor: AppColors.background,
              body: CallFeedScreen(showHeader: false, onOpenDares: _noop),
            ),
          );
        },
        then: () async {
          final calls =
              tester.element(find.byType(CallFeedScreen)).read<CallsProvider>();
          (calls.repository as MockCallsRepository).simulateOffline = true;
          await calls.loadFeed(force: true);
          await tester.pumpAndSettle();
        },
      );

      // --- Friends on the seeded build: your people, and a dare -----------------
      final arena = QuietArena();
      addTearDown(arena.dispose);
      await both(tester, 'friends-dares', () {
        final calls = CallsProvider(
          repository: MockCallsRepository(latency: Duration.zero),
        )..setViewer(_viewer);
        addTearDown(calls.dispose);
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<CallsProvider>.value(value: calls),
            ChangeNotifierProvider<ArenaProvider>.value(value: arena),
            ChangeNotifierProvider<MwaAuthProvider>.value(value: _NoWallet()),
            ChangeNotifierProvider<MwaWalletProvider>(
              create: (_) => ConnectedWallet(),
            ),
          ],
          child: Theme(
            data: AppTheme.lightTheme.copyWith(
              scaffoldBackgroundColor: AppColors.background,
            ),
            child: friendsScreen(),
          ),
        );
      });

      // --- Profile, signed out ---------------------------------------------------
      await both(tester, 'profile-signed-out', () {
        final calls = CallsProvider(repository: PeopleFake());
        final wallet = ConnectedWallet();
        final existing = ExistingProfile();
        final none = ChallengeStateProvider(loadChallenges: (_) async => []);
        for (final n in <ChangeNotifier>[calls, wallet, existing, none]) {
          addTearDown(n.dispose);
        }
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<ProfileProvider>.value(value: existing),
            ChangeNotifierProvider<MwaAuthProvider>.value(value: _NoWallet()),
            ChangeNotifierProvider<MwaWalletProvider>.value(value: wallet),
            ChangeNotifierProvider<CallsProvider>.value(value: calls),
            ChangeNotifierProvider<ChallengeStateProvider>.value(value: none),
            ChangeNotifierProvider<ArenaProvider>.value(value: arena),
          ],
          child: ProfileScreen(embedded: true, onOpenChallenges: () {}),
        );
      }, height: 1000);

      await tester.pumpWidget(const SizedBox());
      for (final dispose in disposeAtEnd) {
        dispose();
      }
    },
    skip: outDir.isEmpty,
  );

  testWidgets(
    'captures: someone else\'s profile with the server record',
    (tester) async {
      // The live build: the server sends a public record. It is drawn as the
      // same compact numbers as your own Profile, its scope behind a tap.
      Widget person(PublicRecord record) {
        final repo =
            PeopleFake()
              ..personRecord = record
              ..followers = 128
              ..followingCount = 12;
        final calls = CallsProvider(repository: repo)..setViewer(_viewer);
        addTearDown(calls.dispose);
        return ChangeNotifierProvider<CallsProvider>.value(
          value: calls,
          child: const CallPersonScreen(personRef: 'user_ada'),
        );
      }

      await both(
        tester,
        'person-record',
        () => person(
          const PublicRecord(
            correct: 47,
            incorrect: 3,
            voided: 1,
            decided: 50,
            pending: 2,
            minimumDecided: 10,
            accuracy: 0.94,
          ),
        ),
        height: 1100,
      );
      await both(
        tester,
        'person-record-building',
        () => person(
          const PublicRecord(
            correct: 3,
            incorrect: 1,
            voided: 0,
            decided: 4,
            pending: 2,
            minimumDecided: 10,
          ),
        ),
        height: 1100,
      );
    },
    skip: outDir.isEmpty,
  );
}
