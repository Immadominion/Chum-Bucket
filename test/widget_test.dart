import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chumbucket/features/authentication/presentation/screens/mwa_login_screen.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';

void main() {
  testWidgets('MWA login screen renders wallet action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MwaAuthProvider()),
          ChangeNotifierProvider(create: (_) => MwaWalletProvider()),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (context, child) => const MaterialApp(home: MwaLoginScreen()),
        ),
      ),
    );

    await tester.pump();

    expect(
      find.text('Challenge Your Friends, \nMake It Count'),
      findsOneWidget,
    );
    expect(find.text('Connect Wallet'), findsOneWidget);
    expect(find.text('Powered by Solana Mobile'), findsOneWidget);
  });
}
