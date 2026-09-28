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
import 'package:chumbucket/features/calls/presentation/screens/call_feed_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/challenges/presentation/screens/challenge_history_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/wallet_modal.dart';
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
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_fakes.dart';

class OfflineArena extends ArenaProvider {
  @override
  Future<void> loadMatchday() async {}
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

  setUp(() {
    AppConfig.initialize();
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
          ChangeNotifierProvider<ArenaProvider>(create: (_) => OfflineArena()),
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
    await mount(tester, preview: false);
    await select(tester, 3);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileSettingsSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(ProfileSettingsSheet))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Add SOL'));
    await tester.tap(find.text('Add SOL'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WalletModal), findsOneWidget);
    Navigator.of(tester.element(find.byType(WalletModal))).pop();
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
    await mount(tester, preview: false);
    await select(tester, 3);
    // The app's floating navigation overlays the bottom edge. Scroll the
    // activity rows above it, just as a person does, before tapping them.
    await tester.drag(
      find.byKey(const PageStorageKey('profile-root')),
      const Offset(0, -400),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('Prediction history'));
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
    await select(tester, 1);
    expect(find.text('The first call could be yours'), findsOneWidget);
    expect(find.text('Explore markets'), findsOneWidget);
    expect(auth.startCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty feed leads to real market discovery while signed out', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, 1);
    await tester.tap(find.text('Explore markets'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TextField), findsOneWidget);
    expect(calls.openMarkets, isNotEmpty);
    final question = calls.openMarkets.first.question;
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
    await select(tester, 1);
    await tester.tap(find.text('Call it'));
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
      1,
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
    await tester.tap(find.text('Make my call'));
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
