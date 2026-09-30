import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/core/navigation/deep_link_host.dart';
import 'package:chumbucket/core/services/app_lifecycle_service.dart';
import 'package:chumbucket/features/arena/presentation/screens/calls_screen.dart';
import 'package:chumbucket/features/arena/presentation/screens/my_pots_screen.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/data/bff_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_market_card.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_detail_screen.dart';
import 'package:chumbucket/features/calls/presentation/widgets/call_card.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/challenges/presentation/screens/challenge_history_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/main.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:chumbucket/shared/screens/home/home.dart';
import 'package:chumbucket/shared/screens/home/widgets/chumbucket_bottom_navigation.dart';
import 'package:chumbucket/shared/screens/home/widgets/friends_hub_tab.dart';
import 'package:chumbucket/shared/screens/home/widgets/predictions_home_tab.dart';
import 'package:chumbucket/shared/screens/splash/mwa_splash_screen.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_fakes.dart';
import 'bff_calls_fixtures.dart' as bff;

const homeMarketId = '11111111-1111-5111-8111-111111111111';

class OfflineArena extends ArenaProvider {
  int matchdayLoads = 0;
  @override
  Future<void> loadMatchday() async {
    matchdayLoads++;
  }

  @override
  Future<void> loadHotCallers() async {}
  @override
  Future<void> loadWalletProfiles(List<String> wallets) async {}
  @override
  Future<void> loadActivity({
    String? walletAddress,
    String? matchId,
    ArenaFeedMode? mode,
  }) async {}
}

class SignedOutWalletAuth extends MwaAuthProvider {
  @override
  MwaAuthState get state => MwaAuthState.unauthenticated;
}

class OfflineWallet extends MwaWalletProvider {
  @override
  Future<void> refreshWalletBalance() async {}
}

// No Supabase singleton or network client is constructed by this test double.
class UnusedProfile extends ChangeNotifier implements ProfileProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSupabaseAuthPort auth;
  late ChumbucketSession session;
  late CallsProvider calls;
  late OfflineArena arena;

  setUp(() {
    AppConfig.initialize();
    arena = OfflineArena();
    auth = FakeSupabaseAuthPort()..deliverOnSignIn = snapshot();
    session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: happyBff().client,
      ),
    );
    calls = CallsProvider(
      repository: MockCallsRepository(latency: Duration.zero)
        ..debugClearCalls(),
    );
  });
  tearDown(() async {
    AppLifecycleService.instance.dispose();
    AppLifecycleService.onNavigateToChallenge = null;
    session.dispose();
    calls.dispose();
    arena.dispose();
    await auth.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    Widget? home,
    double scale = 1,
    bool preview = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MwaAuthProvider>(
            create: (_) => SignedOutWalletAuth(),
          ),
          ChangeNotifierProvider<MwaWalletProvider>(
            create: (_) => OfflineWallet(),
          ),
          ChangeNotifierProvider<ArenaProvider>.value(value: arena),
          ChangeNotifierProvider<ProfileProvider>(
            create: (_) => UnusedProfile(),
          ),
          ChangeNotifierProvider.value(value: ChallengeStateProvider.instance),
          ChangeNotifierProvider<ChumbucketSession>.value(value: session),
          ChangeNotifierProvider<CallsProvider>.value(value: calls),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => MaterialApp(
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: home ?? HomeScreen(callReceiptExperienceEnabled: preview),
              ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Future<void> select(WidgetTester tester, int index) async {
    final buttons = find.descendant(
      of: find.byType(ChumbucketBottomNavigation),
      matching: find.byType(InkWell),
    );
    await tester.tap(buttons.at(index));
    await tester.pump(const Duration(milliseconds: 400));
  }

  bff.FakeBffServer usePantaCatalog({
    bool Function()? fail,
    bool empty = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final market = {
      ...bff.marketJson(id: homeMarketId, venue: 'panta'),
      'venueMarketId': 'panta-synthetic-home',
      'closesAt': now + const Duration(days: 1).inMilliseconds,
      'lastSyncedAt': now,
    };
    final price = {
      'id': '22222222-2222-5222-8222-222222222222',
      'marketId': homeMarketId,
      'venue': 'panta',
      'currency': 'USDC',
      'unit': 'per_share',
      'yesPrice': '0.40',
      'noPrice': '0.65',
      'observedAt': now,
      'source': 'venue',
      'attribution': 'Powered by Panta',
      'executable': false,
    };
    final entry = bff.feedEntryJson(
      market: market,
      author: bff.personJson(id: kCanonicalUserId, walletAddress: null),
      call: {
        ...bff.callJson(
          id: 'synthetic-created-call',
          marketId: homeMarketId,
          userId: kCanonicalUserId,
          entryProbability: null,
          snapshotId: null,
        ),
        'createdAt': now,
        'lockedAt': now,
        'entryPrice': price,
      },
      viewerHasCalled: true,
    );
    var created = false;
    final server = bff.FakeBffServer((request) {
      if (request.procedurePath == 'markets.open') {
        if (fail?.call() == true) {
          return bff.errorResponse(
            code: 'SERVICE_UNAVAILABLE',
            httpStatus: 503,
            message: 'Markets are temporarily unavailable.',
          );
        }
        return bff.okResponse(empty ? [] : [market]);
      }
      if (request.procedurePath == 'markets.detail') {
        return bff.okResponse({
          ...bff.marketDetailJson(
            market: market,
            snapshot: null,
            viewerCall: created ? entry : null,
          ),
          'sharePrice': price,
        });
      }
      if (request.procedurePath == 'calls.create') {
        created = true;
        return bff.okResponse(entry);
      }
      if (request.procedurePath == 'calls.get') {
        return bff.okResponse(
          bff.callDetailJson(entry: entry, parent: null, responses: []),
        );
      }
      if (request.procedurePath == 'calls.invitations') {
        return bff.okResponse([]);
      }
      if (request.procedurePath == 'people.get') {
        return bff.okResponse(
          bff.personDetailJson(
            person: bff.personJson(id: kCanonicalUserId, walletAddress: null),
            calls: created ? [entry] : [],
          ),
        );
      }
      return bff.okResponse(
        bff.feedPageJson(entries: created ? [entry] : [], nextCursor: null),
      );
    });
    calls.dispose();
    calls = CallsProvider(
      repository: BffCallsRepository(
        baseUrl: 'https://home-test.invalid',
        httpClient: server.client,
        authToken: () => 'synthetic-test-session',
      ),
    );
    return server;
  }

  for (final preview in [false, true]) {
    testWidgets('shell restores readable system bars (calls=$preview)', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      // Reproduce the light-icon style left behind by the real splash screen.
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      await mount(tester, preview: preview);

      for (var index = 0; index < 4; index++) {
        await select(tester, index);
        expect(
          SystemChrome.latestStyle?.statusBarIconBrightness,
          Brightness.dark,
        );
        expect(
          SystemChrome.latestStyle?.systemNavigationBarIconBrightness,
          Brightness.dark,
        );
      }

      final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
      final route = navigator.push<void>(
        MaterialPageRoute(
          builder:
              (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  systemOverlayStyle: SystemUiOverlayStyle.light,
                ),
              ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.light,
      );
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await route;
      expect(
        SystemChrome.latestStyle?.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Home → Panta market → locked call reaches its optional funding and can reopen from feed',
    (tester) async {
      final server = usePantaCatalog();
      calls.setViewer(kCanonicalUserId);
      await mount(tester);
      await select(tester, 1);
      await tester.tap(find.byType(CallMarketCard));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Make a call'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('YES').hitTestable());
      await tester.pump();
      await tester.tap(find.text('Lock my YES call'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CallDetailScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Review a YES trade'),
        180,
        scrollable:
            find
                .descendant(
                  of: find.byType(CallDetailScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(find.text('Review a YES trade'), findsOneWidget);
      expect(server.requestFor('calls.create').input['marketId'], homeMarketId);
      expect(server.requestFor('calls.create').input['side'], 'YES');
      expect(
        server.received.where(
          (r) => r.procedurePath.startsWith('pantaTrading.'),
        ),
        isEmpty,
      );
      Navigator.of(tester.element(find.byType(CallDetailScreen))).pop();
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(MarketDetailScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await select(tester, 0);
      await tester.tap(find.byType(CallCard));
      await tester.pumpAndSettle();
      expect(find.byType(CallDetailScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Review a YES trade'),
        180,
        scrollable:
            find
                .descendant(
                  of: find.byType(CallDetailScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
      );
      expect(find.text('Review a YES trade'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home opens the exact Panta market without football or sign-in', (
    tester,
  ) async {
    final server = usePantaCatalog();
    await mount(tester);
    await select(tester, 1);
    expect(arena.matchdayLoads, 0);
    expect(find.text("Today's matches"), findsNothing);
    expect(find.textContaining('Powered by Panta'), findsOneWidget);
    expect(find.byType(CallMarketCard), findsOneWidget);
    expect(server.requestFor('markets.open').input, {'category': 'crypto'});
    await tester.tap(find.byType(CallMarketCard));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MarketDetailScreen), findsOneWidget);
    expect(server.requestFor('markets.detail').input['marketId'], homeMarketId);
    expect(auth.startCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Calls market picker opens the newly locked call', (
    tester,
  ) async {
    usePantaCatalog();
    calls.setViewer(kCanonicalUserId);
    await mount(tester);
    await tester.tap(find.text('Call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.text(bff.marketJson()['question'] as String).hitTestable(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('YES').hitTestable());
    await tester.pump();
    await tester.tap(find.text('Lock my YES call'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CallDetailScreen), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Review a YES trade'),
      180,
      scrollable:
          find
              .descendant(
                of: find.byType(CallDetailScreen),
                matching: find.byType(Scrollable),
              )
              .first,
    );
    expect(find.text('Review a YES trade'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Markets catalog error retries the BFF without falling back to matches',
    (tester) async {
      var failing = true;
      usePantaCatalog(fail: () => failing);
      await mount(tester);
      await select(tester, 1);
      expect(find.text('Markets are temporarily unavailable.'), findsOneWidget);
      expect(arena.matchdayLoads, 0);
      failing = false;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Powered by Panta'), findsOneWidget);
      expect(arena.matchdayLoads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markets keeps last catalog visible with a failed refresh notice',
    (tester) async {
      var failing = false;
      usePantaCatalog(fail: () => failing);
      await mount(tester);
      await select(tester, 1);
      failing = true;
      await calls.loadOpenMarkets(force: true);
      await tester.pump();
      expect(find.byType(CallMarketCard), findsOneWidget);
      expect(find.text('Markets are temporarily unavailable.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markets shows an honest empty catalog and keeps calls reachable',
    (tester) async {
      usePantaCatalog(empty: true);
      await mount(tester);
      await select(tester, 1);
      expect(find.text('Nothing open in this window'), findsOneWidget);
      expect(find.byType(CallMarketCard), findsNothing);
      await select(tester, 0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CallFeedScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Panta Markets and its market remain usable at large text size', (
    tester,
  ) async {
    usePantaCatalog();
    await mount(tester, scale: 2);
    await select(tester, 1);
    final question = find.text(bff.marketJson()['question'] as String);
    await tester.ensureVisible(question);
    await tester.pumpAndSettle();
    await tester.tap(question);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MarketDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default entry restores the existing splash and gates new links',
    (tester) async {
      expect(AppConfig.callReceiptExperienceEnabled, isFalse);
      await tester.pumpWidget(const MyApp());
      expect(find.byType(MwaSplashScreen), findsOneWidget);
      expect(find.byType(DeepLinkHost), findsNothing);
      expect(find.byType(CallSessionPanel), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('default shell keeps all four original destinations', (
    tester,
  ) async {
    await mount(tester, preview: false);
    expect(find.byType(PredictionsHomeTab), findsOneWidget);
    expect(arena.matchdayLoads, 1);
    await select(tester, 1);
    expect(find.byType(CallsScreen), findsOneWidget);
    expect(find.byType(CallFeedScreen), findsNothing);
    await select(tester, 2);
    expect(find.byType(FriendsHubTab), findsOneWidget);
    await select(tester, 3);
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byType(ProfileWalletCard), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byType(CallSessionPanel), findsNothing);
    expect(find.text('Create my profile'), findsNothing);
    expect(find.text('Legacy wallet and challenges'), findsNothing);
    expect(auth.startCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile still opens settings and wallet details and returns', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 3);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileSettingsSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(ProfileSettingsSheet))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('My wallet'));
    await tester.tap(find.text('My wallet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileSettingsSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(ProfileSettingsSheet))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<ChumbucketBottomNavigation>(
            find.byType(ChumbucketBottomNavigation),
          )
          .selectedIndex,
      3,
    );
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('both existing history routes remain reachable from profile', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 3);
    // The app's floating navigation overlays the bottom edge. Scroll the
    // activity rows above it, just as a person does, before tapping them.
    await tester.drag(
      find.byKey(const PageStorageKey('profile-root')),
      const Offset(0, -400),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Challenges'));
    await tester.tap(find.text('Challenges'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Prediction history'));
    await tester.drag(
      find.byKey(const PageStorageKey('profile-root')),
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prediction history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(MyPotsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(MyPotsScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Challenge history'));
    await tester.tap(find.text('Challenge history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChallengeHistoryScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(ChallengeHistoryScreen))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<ChumbucketBottomNavigation>(
            find.byType(ChumbucketBottomNavigation),
          )
          .selectedIndex,
      3,
    );
  });

  testWidgets('preview feed stays inside the existing shell', (tester) async {
    await mount(tester);
    expect(find.text('The first call could be yours'), findsOneWidget);
    expect(find.text('Explore markets'), findsOneWidget);
    expect(auth.startCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty feed leads to real market discovery while signed out', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Explore markets'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TextField), findsOneWidget);
    expect(calls.openMarkets, isNotEmpty);
    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    final question =
        calls.openMarkets
            .firstWhere((market) => market.id == 'market_sol_flip')
            .question;
    await tester.enterText(find.byType(TextField), question);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(question).last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MarketDetailScreen), findsOneWidget);
    expect(auth.startCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Call it has a real sign-in action and Google finishes', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Call'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CallSessionPanel).hitTestable(), findsOneWidget);
    expect(find.byType(ChumbucketWavySheet), findsOneWidget);
    expect(
      tester
          .widget<ChumbucketBottomNavigation>(
            find.byType(ChumbucketBottomNavigation),
          )
          .selectedIndex,
      0,
    );
    await tester.tap(find.text('Continue with Google').hitTestable());
    await tester.pump(const Duration(seconds: 1));
    expect(auth.startCount, 1);
    expect(session.userId, kCanonicalUserId);
    expect(find.text('You’re on record').hitTestable(), findsOneWidget);
  });

  testWidgets('deep-linked market can sign in without a supplied callback', (
    tester,
  ) async {
    await calls.loadOpenMarkets();
    await mount(
      tester,
      home: MarketDetailScreen(marketId: calls.openMarkets.first.id),
    );
    // Tap the real detail action: this screen has no shell callback.
    await tester.tap(find.text('Make a call'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile remains the original profile in preview, including large text',
    (tester) async {
      await mount(tester, scale: 1.6);
      await select(tester, 3);
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(CallSessionPanel), findsNothing);
      expect(find.byTooltip('Settings'), findsOneWidget);
    },
  );
}
