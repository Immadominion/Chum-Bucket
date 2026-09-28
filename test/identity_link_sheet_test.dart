import 'dart:async';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/identity_link_sheet.dart';
import 'package:chumbucket/shared/widgets/chumbucket_wavy_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'existing_account_link_fakes.dart';
import 'session_fakes.dart';

void main() {
  late ClaimRig r;
  setUp(() {
    r = ClaimRig();
  });
  tearDown(() => r.close());

  Future<void> openSheet(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<ChumbucketSession>.value(
        value: r.session,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                theme: AppTheme.lightTheme,
                builder:
                    (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                home: Scaffold(
                  body: Builder(
                    builder:
                        (context) => Column(
                          children: [
                            const Text('Existing profile and history'),
                            TextButton(
                              onPressed:
                                  () => showChumbucketWavySheet<void>(
                                    context: context,
                                    builder:
                                        (_) =>
                                            IdentityLinkSheet(wallet: r.wallet),
                                  ),
                              child: const Text('Settings link'),
                            ),
                          ],
                        ),
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('Settings link'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'existing wavy sheet explains continuity and no money; no X or create-profile fork',
    (tester) async {
      await openSheet(tester);
      expect(find.byType(ChumbucketWavySheet), findsOneWidget);
      expect(find.text('Link Google'), findsOneWidget);
      expect(
        find.textContaining('No transaction, payment or new profile.'),
        findsOneWidget,
      );
      expect(find.text('X'), findsNothing);
      expect(find.text('Create my profile'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'server-disabled state is visible without opening Google (text scale $scale)',
      (tester) async {
        r.capability['existingAccountClaimsEnabled'] = false;
        await openSheet(tester, scale: scale);
        await tester.ensureVisible(find.text('Continue with Google'));
        await tester.tap(find.text('Continue with Google'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('account-link-error')),
        );
        expect(
          find.textContaining('Google linking is not available'),
          findsOneWidget,
        );
        expect(r.auth.startCount, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'success returns to the same profile screen, no onboarding navigation',
    (tester) async {
      await openSheet(tester);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(find.byType(IdentityLinkSheet), findsNothing);
      expect(find.text('Existing profile and history'), findsOneWidget);
      expect(find.text('Google linked'), findsOneWidget);
      expect(r.session.userId, kCanonicalUserId);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'dismissing Settings during wallet wait discards the eventual signature',
    (tester) async {
      r.wallet.signature = Completer<String>();
      await openSheet(tester);
      await tester.tap(find.text('Continue with Google'));
      // Pump microtasks but not the deliberately pending wallet/OAuth timeout.
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(r.wallet.signed, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      r.wallet.signature!.complete('synthetic-signature');
      await tester.pump();
      await tester.pump();
      expect(r.claimed, isFalse);
      expect(r.session.userId, isNull);
    },
  );
}
