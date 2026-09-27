import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/calls/data/mock_calls_repository.dart';
import 'package:chumbucket/features/calls/presentation/screens/call_home_screen.dart';
import 'package:chumbucket/features/calls/presentation/screens/market_detail_screen.dart';
import 'package:chumbucket/features/calls/providers/calls_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'session_fakes.dart';

void main() {
  late FakeSupabaseAuthPort auth;
  late ChumbucketSession session;
  late CallsProvider calls;

  setUp(() {
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
    session.dispose();
    calls.dispose();
    await auth.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    Widget? home,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
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
                home: home ?? const CallHomeScreen(),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cold social home needs no wallet provider or session', (
    tester,
  ) async {
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
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(calls.openMarkets, isNotEmpty);
    final question = calls.openMarkets.first.question;
    await tester.enterText(find.byType(TextField), question);
    await tester.pumpAndSettle();
    await tester.tap(find.text(question).last);
    await tester.pumpAndSettle();
    expect(find.byType(MarketDetailScreen), findsOneWidget);
    expect(auth.startCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Call it has a real sign-in action and Google finishes', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Call it'));
    await tester.pumpAndSettle();
    expect(find.byType(CallSessionPanel).hitTestable(), findsOneWidget);
    await tester.tap(find.text('Continue with Google').hitTestable());
    await tester.pumpAndSettle();
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

  testWidgets('account is readable with large text and retains legacy access', (
    tester,
  ) async {
    await mount(tester, scale: 1.6);
    await tester.tap(find.byTooltip('Your account'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Legacy wallet and challenges'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
