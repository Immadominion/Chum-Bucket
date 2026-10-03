import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/onboarding/onboarding_controller.dart';
// MWA Auth replaces Privy Auth for Solana Mobile compatibility
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
// MWA Wallet Provider for Pinocchio program integration
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
// MWA Splash Screen handles wallet-based auth flow
import 'package:chumbucket/shared/screens/splash/mwa_splash_screen.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/core/crash/crash_reporting.dart';
import 'package:chumbucket/core/utils/app_logger.dart';
import 'package:chumbucket/core/navigation/deep_link_host.dart';
import 'package:chumbucket/features/authentication/continuity/session_continuity.dart';
import 'package:chumbucket/features/authentication/continuity/supabase_session_adopter.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:chumbucket/features/authentication/session/app_session_persistence.dart';
import 'package:chumbucket/features/authentication/session/app_sign_out.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/account_session_host.dart';
import 'package:chumbucket/features/calls/data/calls_repository_factory.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:chumbucket/features/notifications/data/bff_notifications_repository.dart';
import 'package:chumbucket/features/notifications/data/mock_notifications_repository.dart';
import 'package:chumbucket/features/notifications/providers/notifications_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Firebase & Push notifications
import 'package:firebase_core/firebase_core.dart';
import 'package:chumbucket/firebase_options.dart';
import 'package:chumbucket/core/services/notification_service.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds drop debugPrint output: it carried wallet and challenge
  // details into logcat. Errors still reach crash reporting (opt-in).
  AppLogger.installReleaseLogPolicy();
  // unawaited(RiveFile.initialize());

  // Public configuration only, supplied at build time via --dart-define.
  // The app deliberately no longer bundles a .env asset: doing so shipped
  // every local secret inside the APK. See lib/core/config/app_config.dart.
  AppConfig.initialize();

  // Staying signed in across reinstall (Android Block Store). Process-wide,
  // like Supabase: it outlives the account tree that sign-out rebuilds.
  final continuity = SessionContinuity(
    adopt: adoptBackedUpSession,
    localSession: () async {
      final persistence = AppSessionPersistence.current;
      if (persistence == null || persistence.isLocked) return null;
      return persistence.accessToken();
    },
  );

  // Initialize Supabase
  try {
    final config = AppConfig.values;
    final supabaseUrl = config['SUPABASE_URL'] ?? '';
    final supabaseAnonKey = config['SUPABASE_ANON_KEY'] ?? '';

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          'Warning: Supabase config missing. '
          'SUPABASE_URL length=${supabaseUrl.length}, '
          'SUPABASE_ANON_KEY length=${supabaseAnonKey.length}',
        );
      }
    }

    final persistence = AppSessionPersistence.forProject(supabaseUrl);
    AppSessionPersistence.current = persistence;
    // Before initialize: every session the SDK saves, from the first, is
    // mirrored into Block Store, and every removal clears it there.
    persistence.onPersisted = continuity.sessionPersisted;
    persistence.onRemoved = continuity.sessionRemoved;
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(localStorage: persistence),
    );
    persistence.discardLateAuthSession =
        () => Supabase.instance.client.auth.signOut();
    if (kDebugMode) debugPrint("Supabase initialized successfully");

    // Configure UnifiedDatabaseService with the Supabase client
    UnifiedDatabaseService.configure(supabase: Supabase.instance.client);
    if (kDebugMode) {
      debugPrint("UnifiedDatabaseService configured successfully");
    }
  } catch (e) {
    if (kDebugMode) debugPrint("Warning: Failed to initialize Supabase: $e");
  }

  // Initialize Firebase first (required for FCM)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    if (kDebugMode) debugPrint("Firebase initialized successfully");
  } catch (e) {
    if (kDebugMode) debugPrint("Warning: Failed to initialize Firebase: $e");
  }

  // Opt-in crash reporting. Reads the stored answer (off by default) and
  // installs the error hooks; never throws.
  await CrashReporting.instance.initialize();

  // Push setup no longer holds the first frame: it includes the notification
  // permission prompt and a network token fetch, which used to put a system
  // dialog (or an offline stall) in front of any UI.
  unawaited(_initializePush());

  runApp(
    AccountSessionHost(
      builder:
          (_) => MultiProvider(
            providers: [
              Provider(create: (_) => AppSignOutEffects()),
              Provider<SessionContinuity>.value(value: continuity),
              // MWA Wallet Provider for Pinocchio escrow transactions
              ChangeNotifierProvider(create: (_) => MwaWalletProvider()),
              // Onboarding's per-install memory: status, topics, and the
              // follows and draft call waiting on a sign-in.
              ChangeNotifierProvider(create: (_) => OnboardingController()),
              // MWA Auth Provider for wallet-based authentication (replaces Privy)
              ChangeNotifierProvider(create: (_) => MwaAuthProvider()),
              ChangeNotifierProvider(create: (_) => ProfileProvider()),
              ChangeNotifierProvider(create: (_) => ArenaProvider()),
              // Preview identity: Google -> Supabase session -> canonical
              // public.users.id. restore() adopts a session already in storage and
              // subscribes to auth changes for the life of the app. It sits ABOVE
              // CallsProvider on purpose: the repository below reads its token
              // provider at construction.
              ChangeNotifierProvider<ChumbucketSession>(
                create: (_) {
                  final session = ChumbucketSession();
                  if (AppConfig.callReceiptExperienceEnabled) session.restore();
                  return session;
                },
              ),
              // The account's on-phone wallet (Google/X accounts without a
              // wallet app). Bound to the canonical account; signed out = none.
              ChangeNotifierProxyProvider<
                ChumbucketSession,
                EmbeddedWalletController
              >(
                create:
                    (context) => EmbeddedWalletController(
                      vault: EmbeddedWalletVault(continuity: continuity),
                      bff: SessionBffClient(),
                      ownsBff: true,
                      authToken: context.read<ChumbucketSession>().bffAuthToken,
                    ),
                update: (_, session, wallet) {
                  wallet!.bind(session.isReady ? session.userId : null);
                  return wallet;
                },
              ),
              // The call/receipt slice. Which repository backs it is a build flag:
              //   --dart-define=CALLS_BACKEND=mock  for the seeded offline catalog.
              // Default is the deployed BFF on real Polymarket markets.
              ChangeNotifierProxyProvider<ChumbucketSession, CallsProvider>(
                create:
                    (context) => CallsProvider(
                      repository: buildCallsRepository(
                        // FutureOr<String?> Function(). Null is not an error — it is
                        // what signed out looks like, and reading never needs a
                        // session. A token near expiry is refreshed before use.
                        authToken:
                            context.read<ChumbucketSession>().bffAuthToken,
                      ),
                    ),
                // The CANONICAL public.users.id — never authUserId, never a wallet
                // (contracts §0 invariant 3). Null while signed out or while whoami
                // is still in flight; setViewer early-returns when unchanged.
                update:
                    (_, session, calls) => calls!..setViewer(session.userId),
              ),
              // The calls inbox (`inbox.*` on the same BFF, same session token).
              // The recipient is the session, never a wallet. The mock is only
              // ever the explicit CALLS_BACKEND=mock build, as for calls.
              ChangeNotifierProxyProvider<
                ChumbucketSession,
                NotificationsProvider
              >(
                create:
                    (context) => NotificationsProvider(
                      repository:
                          resolveCallsBackend() == CallsBackend.mock
                              ? MockNotificationsRepository()
                              : BffNotificationsRepository(
                                authToken:
                                    context
                                        .read<ChumbucketSession>()
                                        .bffAuthToken,
                              ),
                    ),
                update: (_, session, inbox) {
                  final changed = inbox!.viewerUserId != session.userId;
                  inbox.setViewer(session.userId);
                  if (changed && session.userId != null) {
                    inbox.refreshUnreadCount();
                  }
                  return inbox;
                },
              ),
              ChangeNotifierProvider.value(
                value: ChallengeStateProvider.instance,
              ),
            ],
            child: const MyApp(),
          ),
    ),
  );
}

/// Local notifications, then FCM. Both optional: the app works without them.
Future<void> _initializePush() async {
  try {
    await NotificationService.initialize();
    if (kDebugMode) debugPrint("Notification service initialized");
  } catch (e) {
    if (kDebugMode) {
      debugPrint("Warning: Failed to initialize notifications: $e");
    }
  }
  try {
    await FcmTokenService.initialize();
    if (kDebugMode) debugPrint("FCM initialized");
  } catch (e) {
    if (kDebugMode) debugPrint("Warning: FCM initialization failed: $e");
  }
}

/// Navigator handle for deep links, which arrive from outside the widget tree
/// and so have no BuildContext of their own.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'chumbucket',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          navigatorKey: rootNavigatorKey,
          // Preview-only until continuity passes device testing. When enabled,
          // shared call/person/market links open cold or warm. Owns delivery: links
          // it does not own — the Supabase OAuth callback among them — are left
          // untouched for their existing handler.
          builder:
              (context, navigatorChild) =>
                  AppConfig.callReceiptExperienceEnabled
                      ? DeepLinkHost(
                        navigatorKey: rootNavigatorKey,
                        child: navigatorChild ?? const SizedBox.shrink(),
                      )
                      : navigatorChild ?? const SizedBox.shrink(),
          home: const MwaSplashScreen(),
        );
      },
    );
  }
}
