import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/onboarding_provider.dart';
// MWA Auth replaces Privy Auth for Solana Mobile compatibility
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
// MWA Wallet Provider for Pinocchio program integration
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
// MWA Splash Screen handles wallet-based auth flow
import 'package:chumbucket/shared/screens/splash/mwa_splash_screen.dart';
import 'package:chumbucket/shared/services/unified_database_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Firebase & Push notifications
import 'package:firebase_core/firebase_core.dart';
import 'package:chumbucket/firebase_options.dart';
import 'package:chumbucket/core/services/notification_service.dart';
import 'package:chumbucket/core/services/fcm_token_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // unawaited(RiveFile.initialize());

  // Try loading .env file, but continue even if it fails
  try {
    await dotenv.load(fileName: ".env");
    if (kDebugMode) debugPrint("Environment variables loaded successfully");
  } catch (e) {
    if (kDebugMode) debugPrint("Warning: Failed to load .env file: $e");
    if (kDebugMode) debugPrint("The app will continue with fallback values");
  }

  // Initialize Supabase
  try {
    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          'Warning: Supabase config missing. '
          'SUPABASE_URL length=${supabaseUrl.length}, '
          'SUPABASE_ANON_KEY length=${supabaseAnonKey.length}',
        );
      }
    }

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    if (kDebugMode) debugPrint("Supabase initialized successfully");

    // Configure UnifiedDatabaseService with the Supabase client
    UnifiedDatabaseService.configure(supabase: Supabase.instance.client);
    if (kDebugMode)
      debugPrint("UnifiedDatabaseService configured successfully");
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

  // Initialize local notification service
  try {
    await NotificationService.initialize();
    if (kDebugMode) debugPrint("Notification service initialized");
  } catch (e) {
    if (kDebugMode)
      debugPrint("Warning: Failed to initialize notifications: $e");
    // Notifications are optional - app works without them
  }

  // Initialize FCM for push notifications (Firebase required)
  try {
    await FcmTokenService.initialize();
    if (kDebugMode) debugPrint("FCM initialized");
  } catch (e) {
    if (kDebugMode) debugPrint("Warning: FCM initialization failed: $e");
    // FCM is optional - local notifications still work
  }

  runApp(
    MultiProvider(
      providers: [
        // MWA Wallet Provider for Pinocchio escrow transactions
        ChangeNotifierProvider(create: (_) => MwaWalletProvider()),
        ChangeNotifierProvider(create: (_) => OnboardingProvider()),
        // MWA Auth Provider for wallet-based authentication (replaces Privy)
        ChangeNotifierProvider(create: (_) => MwaAuthProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => ArenaProvider()),
        ChangeNotifierProvider.value(value: ChallengeStateProvider.instance),
      ],
      child: const MyApp(),
    ),
  );
}

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
          home: const MwaSplashScreen(), // MWA-based splash screen
        );
      },
    );
  }
}
