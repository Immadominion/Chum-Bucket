/// The first screen: wallet, Google or X into one account, "Last used" on the
/// way this phone last got in, X only when switched on, a first sign-in
/// claiming a @username before anything exists — and the legacy wallet-only
/// door untouched when the calls experience is off.
library;

import 'package:chumbucket/features/authentication/presentation/screens/mwa_login_screen.dart';
import 'package:chumbucket/features/authentication/presentation/screens/widgets/front_door_options.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/onboarding/presentation/widgets/sign_in_panel.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

class _Door {
  _Door({
    Set<String> providers = const {'google', 'x'},
    SignInMethod? last,
    FakeBffServer? bff,
  }) : auth = FakeSupabaseAuthPort()..providers = providers,
       memory = MemoryLastSignInStore(last) {
    session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: (bff ?? happyBff()).client,
      ),
      lastSignIn: memory,
    );
  }

  final FakeSupabaseAuthPort auth;
  final MemoryLastSignInStore memory;
  late final ChumbucketSession session;
  int entered = 0;
  int walletTaps = 0;

  Future<void> dispose() async {
    session.dispose();
    await auth.close();
  }

  Widget app(
    Widget child, {
    double width = 390,
    double scale = 1,
    bool withSession = true,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => MwaAuthProvider()),
      ChangeNotifierProvider(create: (_) => MwaWalletProvider()),
      if (withSession)
        ChangeNotifierProvider<ChumbucketSession>.value(value: session),
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
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
    ),
  );

  Widget options() => FrontDoorOptions(
    onEntered: (_) => entered++,
    connectWallet: (_) async {
      walletTaps++;
      return true;
    },
  );
}

Future<void> _size(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('offers wallet, Google and X; X only when it is switched on', (
    tester,
  ) async {
    await _size(tester, 390);
    final door = _Door();
    addTearDown(door.dispose);
    await tester.pumpWidget(door.app(door.options()));
    await tester.pumpAndSettle();
    expect(find.text('Continue with wallet'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with X'), findsOneWidget);
    expect(find.byKey(const ValueKey('front-door-last-used')), findsNothing);

    final noX = _Door(providers: const {'google'});
    addTearDown(noX.dispose);
    await tester.pumpWidget(noX.app(noX.options()));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with X'), findsNothing);
  });

  for (final last in SignInMethod.values) {
    testWidgets('"Last used" marks ${last.name}', (tester) async {
      await _size(tester, 390);
      final door = _Door(last: last);
      addTearDown(door.dispose);
      await tester.pumpWidget(door.app(door.options()));
      await tester.pumpAndSettle();
      final badge = find.byKey(const ValueKey('front-door-last-used'));
      expect(badge, findsOneWidget);
      expect(find.text('Last used'), findsOneWidget);
      // The pill and the option it marks share one Stack.
      expect(
        find.descendant(
          of: find.ancestor(of: badge, matching: find.byType(Stack)).first,
          matching: find.byKey(ValueKey('front-door-${last.wire}')),
        ),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'Google into an existing account goes straight in, and is remembered',
    (tester) async {
      await _size(tester, 390);
      final door = _Door();
      door.auth.deliverOnSignIn = snapshot();
      addTearDown(door.dispose);
      await tester.pumpWidget(door.app(door.options()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      // Ready shows a spinner while the app navigates in; no settle.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(door.auth.startCount, 1);
      expect(door.session.isReady, isTrue);
      expect(door.entered, 1);
      expect(door.memory.value, SignInMethod.google);
      expect(door.walletTaps, 0, reason: 'no wallet needed');
    },
  );

  testWidgets(
    'a first Google sign-in claims a @username before anything exists',
    (tester) async {
      await _size(tester, 390);
      final door = _Door(bff: refusingBff('AUTH_USER_UNLINKED', 403));
      door.auth.deliverOnSignIn = snapshot();
      addTearDown(door.dispose);
      await tester.pumpWidget(door.app(door.options()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(door.session.needsUsername, isTrue);
      expect(find.text('Claim your username'), findsOneWidget);
      expect(find.byKey(const ValueKey('claim-username')), findsOneWidget);
      expect(door.entered, 0);
      // Backing out returns to the three ways in.
      await tester.tap(find.text('Use a different sign-in'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsOneWidget);
    },
  );

  testWidgets('while the browser is open it says so, and can be abandoned', (
    tester,
  ) async {
    await _size(tester, 390);
    final door = _Door();
    addTearDown(door.dispose);
    await tester.pumpWidget(door.app(door.options()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with X'));
    await tester.pump();
    expect(door.auth.lastProvider, 'x');
    expect(find.byKey(const ValueKey('front-door-waiting')), findsOneWidget);
    await tester.tap(find.text('Use a different way in'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with X'), findsOneWidget);
    expect(door.entered, 0);
  });

  testWidgets('the wallet goes through the wallet door', (tester) async {
    await _size(tester, 390);
    final door = _Door();
    addTearDown(door.dispose);
    await tester.pumpWidget(door.app(door.options()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with wallet'));
    await tester.pumpAndSettle();
    expect(door.walletTaps, 1);
    expect(door.auth.startCount, 0);
  });

  for (final (width, scale) in [(320.0, 2.0), (390.0, 1.0)]) {
    testWidgets(
      'the ways in fit at ${width}dp and ${scale}x text, pill clear of label',
      (tester) async {
        await _size(tester, width);
        final door = _Door(last: SignInMethod.google);
        addTearDown(door.dispose);
        await tester.pumpWidget(
          door.app(
            OnboardingSignInPanel(
              isOnline: () async => true,
              walletAvailable: () async => true,
            ),
            width: width,
            scale: scale,
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.text('Last used'), findsOneWidget);
        for (final option in ['wallet', 'google', 'x']) {
          final size = tester.getSize(
            find.byKey(ValueKey('front-door-$option')),
          );
          expect(size.height, greaterThanOrEqualTo(48));
        }
        // The pill straddles the button's edge but never covers its label.
        final pill = tester.getRect(
          find.byKey(const ValueKey('front-door-last-used')),
        );
        final google = tester.getRect(
          find.byKey(const ValueKey('front-door-google')),
        );
        expect(pill.bottom, greaterThan(google.top));
        for (final line in find.text('Continue with Google').evaluate()) {
          final label = tester.getRect(find.byWidget(line.widget));
          expect(
            pill.overlaps(label),
            isFalse,
            reason: 'at ${width}dp and ${scale}x the pill covers the label',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the legacy build keeps its wallet-only door', (tester) async {
    await _size(tester, 390);
    final door = _Door();
    addTearDown(door.dispose);
    await tester.pumpWidget(
      door.app(
        const SizedBox(height: 1200, child: MwaLoginScreen()),
        withSession: false,
      ),
    );
    await tester.pump();
    expect(find.text('Connect Wallet'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });
}
