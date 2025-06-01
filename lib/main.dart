import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:recess/config/theme/app_theme.dart';
import 'package:recess/providers/onboarding_provider.dart';
import 'package:recess/providers/wallet_provider.dart';
import 'package:recess/screens/splash/splash_screen.dart';
import 'package:rive/rive.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:recess/providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(RiveFile.initialize());

  // Try loading .env file, but continue even if it fails
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("Environment variables loaded successfully");
  } catch (e) {
    debugPrint("Warning: Failed to load .env file: $e");
    debugPrint("The app will continue with fallback values");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => OnboardingProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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
          title: 'Recess',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const SplashScreen(),
        );
      },
    );
  }
}
