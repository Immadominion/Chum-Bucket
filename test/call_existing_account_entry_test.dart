import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/identity_link_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'existing_account_link_fakes.dart';

class ConnectedExistingWallet extends MwaAuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  String get walletAddress => claimAddress;
  @override
  int get authRevision => 1;
}

void main() {
  late ClaimRig rig;
  late ConnectedExistingWallet wallet;

  setUp(() {
    dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet');
    rig = ClaimRig();
    wallet = ConnectedExistingWallet();
  });
  tearDown(() async {
    wallet.dispose();
    await rig.close();
  });

  Future<void> mount(WidgetTester tester, {bool connected = true}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChumbucketSession>.value(value: rig.session),
          if (connected)
            ChangeNotifierProvider<MwaAuthProvider>.value(value: wallet),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                theme: AppTheme.lightTheme,
                home: Scaffold(
                  body: Builder(
                    builder:
                        (context) => Column(
                          children: [
                            const Text('Original call destination'),
                            TextButton(
                              onPressed: () => requestCallSignIn(context),
                              child: const Text('Call entry'),
                            ),
                            TextButton(
                              onPressed:
                                  () => requestCallSignIn(
                                    context,
                                    onRequested:
                                        () => requestCallSignIn(context),
                                  ),
                              child: const Text('Shell call entry'),
                            ),
                          ],
                        ),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final entry in ['Call entry', 'Shell call entry']) {
    testWidgets('$entry opens the one sign-in sheet, wallet first, starting nothing', (
      tester,
    ) async {
      rig.capability['existingAccountClaimsEnabled'] = false;
      await mount(tester);
      await tester.tap(find.text(entry));
      await tester.pumpAndSettle();
      expect(find.byType(ChumbucketSignInSheet), findsOneWidget);
      expect(find.byType(IdentityLinkSheet), findsNothing);
      expect(find.text('Continue with wallet'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      // Opening the sheet signs nothing, opens no browser and claims nothing.
      expect(rig.auth.startCount, 0);
      expect(rig.claimed, false);
      expect(rig.wallet.signed, isEmpty);
      expect(rig.requests, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('chumbucket-sheet-close-target')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Original call destination'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'walletless entry retains normal Google sign-in without requiring MWA',
    (tester) async {
      await mount(tester, connected: false);
      await tester.tap(find.text('Call entry'));
      await tester.pumpAndSettle();
      expect(find.byType(CallSessionPanel), findsOneWidget);
      expect(find.byType(IdentityLinkSheet), findsNothing);
      expect(find.text('Continue with Google'), findsOneWidget);
      // No wallet in this app: no wallet option is offered.
      expect(find.text('Continue with wallet'), findsNothing);
      expect(rig.auth.startCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
