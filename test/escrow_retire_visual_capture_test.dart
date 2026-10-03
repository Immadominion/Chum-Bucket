// Opt-in captures of the escrow-retire surfaces (Settings → History → Escrow
// challenges, the settle sheet in each state, and what a friend tap offers)
// with the real fonts and synthetic data, for design review. Writes nothing
// unless asked:
// flutter test --no-pub --update-goldens \
//   --dart-define=CAPTURE_ESCROW_RETIRE=/abs/output/dir \
//   test/escrow_retire_visual_capture_test.dart
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
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/challenges/presentation/screens/challenge_history_screen.dart';
import 'package:chumbucket/features/profile/data/account_api.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/trust/presentation/legacy_history_screen.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/models/models.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/screens/home/widgets/friend_actions.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_grid.dart';
import 'package:chumbucket/shared/screens/home/widgets/resolve_challenge_sheet.dart';
import 'package:chumbucket/shared/screens/home/widgets/view_more_friends_sheet.dart';

import 'ui_people_layout_continuity_test.dart'
    show ConnectedAuth, ConnectedWallet, ExistingProfile, walletFixture;
import 'ui_people_layout_friends_test.dart'
    show FriendsRepository, QuietArena, friendsScreen, hub;

const _challenger = 'CHaLLenGer1111111111111111111111111111111111';
const _otherWitness = 'W1tness11111111111111111111111111111111111';

Challenge _escrow(
  String id,
  ChallengeStatus status, {
  required String description,
  String witness = walletFixture,
  String initiator = _challenger,
  double amount = .05,
  DateTime? created,
  DateTime? due,
}) => Challenge(
  id: id,
  creatorId: initiator,
  member1Address: initiator,
  witnessAddress: witness,
  witnessDisplayName: witness == walletFixture ? null : 'tolu.sol',
  title: description,
  description: description,
  amount: amount,
  platformFee: amount * .025,
  winnerAmount: amount * .975,
  createdAt: created ?? DateTime.utc(2026, 1, 3),
  expiresAt: due ?? DateTime.utc(2026, 2, 3, 12),
  status: status,
  escrowAddress: '8aoA32Bx1111111111111111111111111111111111',
);

class _Account implements AccountApi {
  @override
  Future<AccountProfile> me() async =>
      const AccountProfile(userId: 'user_ada', displayName: 'Ada Okafor');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoWallet extends MwaAuthProvider {
  @override
  String? get walletAddress => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outDir = String.fromEnvironment('CAPTURE_ESCROW_RETIRE');
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
    double height = 844,
    double scale = 1,
    Widget Function(Widget app)? above,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = ScreenUtilInit(
      // A fresh app per scene: a sheet left open by one scene must not cover
      // the next.
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
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('escrow-retire-capture'),
        child: above?.call(app) ?? app,
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('escrow-retire-capture')),
      matchesGoldenFile(Uri.file('$outDir/escrow-retire-$name.png')),
    );
    expect(tester.takeException(), isNull);
  }

  Widget withEscrows(
    ChallengeStateProvider state,
    MwaAuthProvider auth,
    Widget child,
  ) => MultiProvider(
    providers: [
      ChangeNotifierProvider<ChallengeStateProvider>.value(value: state),
      ChangeNotifierProvider<MwaAuthProvider>.value(value: auth),
    ],
    child: child,
  );

  Future<ChallengeStateProvider> escrows(List<Challenge> rows) async {
    final state = ChallengeStateProvider(loadChallenges: (_) async => rows);
    addTearDown(state.dispose);
    await state.initialize(walletFixture);
    return state;
  }

  final rows = [
    _escrow(
      'witness-open',
      ChallengeStatus.active,
      description: 'Run 5k every morning for a month',
      created: DateTime.utc(2026, 1, 3),
    ),
    _escrow(
      'challenger-open',
      ChallengeStatus.expired,
      description: 'No sugar until the end of April',
      witness: _otherWitness,
      initiator: walletFixture,
      amount: .01,
      created: DateTime.utc(2026, 1, 2),
      due: DateTime.utc(2026, 4, 27, 12),
    ),
    _escrow(
      'completed',
      ChallengeStatus.completed,
      description: 'Read two books in December',
      witness: _otherWitness,
      initiator: walletFixture,
      amount: .1,
      created: DateTime.utc(2025, 12, 1),
    ),
    _escrow(
      'failed',
      ChallengeStatus.failed,
      description: 'Ship the side project by Friday',
      amount: .25,
      created: DateTime.utc(2025, 11, 1),
    ),
  ];

  testWidgets('captures', (tester) async {
    // History list: an open one to settle, one waiting on the witness, and
    // two settled ones.
    final state = await escrows(rows);
    final auth = ConnectedAuth();
    addTearDown(auth.dispose);
    await mount(
      tester,
      withEscrows(
        state,
        auth,
        ChallengeHistoryScreen(
          refreshKey: 0,
          onMarkChallengeCompleted: (_, _) async {},
        ),
      ),
    );
    await capture(tester, 'history-list');

    // Each row's sheet.
    for (final (index, name) in [
      (0, 'sheet-witness'),
      (1, 'sheet-challenger'),
      (2, 'sheet-completed'),
      (3, 'sheet-failed'),
    ]) {
      await tester.tap(find.text(rows[index].description));
      await tester.pumpAndSettle();
      expect(find.byType(ResolveChallengeSheet), findsOneWidget);
      await capture(tester, name);
      Navigator.of(tester.element(find.byType(ResolveChallengeSheet))).pop();
      await tester.pumpAndSettle();
    }

    // Large text on the witness sheet.
    await mount(
      tester,
      withEscrows(
        state,
        auth,
        ChallengeHistoryScreen(
          refreshKey: 1,
          onMarkChallengeCompleted: (_, _) async {},
        ),
      ),
      scale: 1.3,
    );
    await tester.tap(find.text(rows[0].description));
    await tester.pumpAndSettle();
    await capture(tester, 'sheet-witness-large-text');

    // Empty: a wallet with none, and no wallet at all.
    final empty = await escrows(const []);
    await mount(
      tester,
      withEscrows(
        empty,
        auth,
        ChallengeHistoryScreen(
          refreshKey: 2,
          onMarkChallengeCompleted: (_, _) async {},
        ),
      ),
    );
    await capture(tester, 'history-empty');
    final noWallet = _NoWallet();
    addTearDown(noWallet.dispose);
    await mount(
      tester,
      withEscrows(
        empty,
        noWallet,
        ChallengeHistoryScreen(
          refreshKey: 3,
          onMarkChallengeCompleted: (_, _) async {},
        ),
      ),
    );
    await capture(tester, 'history-no-wallet');

    // Settings → History.
    await mount(tester, LegacyHistoryScreen(onOpenEscrowChallenges: () {}));
    await capture(tester, 'legacy-history');

    // A friend with no person id: the call-based sheet.
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed:
                      () => openFriend(context, const {
                        'name': 'Tolu Adebayo',
                        'walletAddress': walletFixture,
                      }, onMakeCall: () {}),
                  child: const Text('open friend'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open friend'));
    await tester.pumpAndSettle();
    await capture(tester, 'friend-actions');

    // All Friends.
    await mount(
      tester,
      Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: TextButton(
                  onPressed:
                      () => showViewMoreFriendsSheet(
                        context,
                        friends: [
                          for (final (i, name)
                              in [
                                'Tolu Adebayo',
                                'Ada Okafor',
                                'Kemi',
                                'Chidi N.',
                                'Bisi',
                                'Femi Ojo',
                              ].indexed)
                            {
                              'name': name,
                              'userId': 'user_$i',
                              'imagePath':
                                  'assets/images/ai_gen/profile_images/${i + 1}.png',
                            },
                        ],
                        onFriendSelected: (_) {},
                      ),
                  child: const Text('all friends'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('all friends'));
    await tester.pumpAndSettle();
    await capture(tester, 'all-friends');

    // The Friends grid itself.
    await mount(
      tester,
      Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: FriendsGrid(
            friends: [
              for (final (i, name)
                  in [
                    'Tolu Adebayo',
                    'Ada Okafor',
                    'Kemi',
                    'Chidi N.',
                    'Bisi',
                    'Femi Ojo',
                  ].indexed)
                {
                  'name': name,
                  'userId': 'user_$i',
                  'imagePath':
                      'assets/images/ai_gen/profile_images/${i + 1}.png',
                },
            ],
            onFriendSelected: (_) {},
            buildViewMoreItem: (_, count) => Text('View $count more'),
            maxVisibleFriends: 5,
          ),
        ),
      ),
    );
    await capture(tester, 'friends-grid');

    // The Friends hub (no wallet friends in a test): its copy.
    final calls = CallsProvider(repository: FriendsRepository());
    final arena = QuietArena();
    addTearDown(calls.dispose);
    addTearDown(arena.dispose);
    await mount(tester, hub(calls, arena, friendsScreen()));
    await capture(tester, 'friends-hub');

    // Profile: the open-escrow row, for the witness and for the challenger.
    for (final (name, row) in [
      ('profile-witness', rows[0]),
      ('profile-challenger', rows[1]),
    ]) {
      final one = await escrows([row]);
      final calls = CallsProvider(repository: FriendsRepository())
        ..setViewer('user_ada');
      final wallet = ConnectedWallet();
      final existing = ExistingProfile();
      for (final n in <ChangeNotifier>[calls, wallet, existing]) {
        addTearDown(n.dispose);
      }
      await mount(
        tester,
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProfileProvider>.value(value: existing),
            ChangeNotifierProvider<MwaAuthProvider>.value(value: auth),
            ChangeNotifierProvider<MwaWalletProvider>.value(value: wallet),
            ChangeNotifierProvider<CallsProvider>.value(value: calls),
            ChangeNotifierProvider<ChallengeStateProvider>.value(value: one),
            ChangeNotifierProvider<ArenaProvider>.value(value: arena),
            Provider<AccountApi>.value(value: _Account()),
          ],
          child: ProfileScreen(embedded: true, onOpenChallenges: () {}),
        ),
        height: 1400,
      );
      await capture(tester, name);
    }
  }, skip: outDir.isEmpty);
}
