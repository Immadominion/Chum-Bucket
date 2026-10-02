/// A Google or X account with no wallet app: Profile offers the wallet that
/// lives on this phone (make it, see its address, back it up, export it), and
/// the trade sheet describes signing with it honestly — no "check the wallet
/// request" for a wallet that has no second screen.
library;

import 'dart:async';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:chumbucket/features/panta_trading/panta_trading.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'identity_embedded_wallet_test.dart' show LinkServer, kTestPhraseAddress;
import 'identity_fakes.dart';
import 'panta_trading_controller_test.dart' show SyntheticPantaRig;
import 'session_fakes.dart';

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  required List<SingleChildWidget> providers,
  double width = 390,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: providers,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              theme: AppTheme.lightTheme,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
              home: Scaffold(body: child),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet');
  });

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'Profile: none yet -> make one -> it lives on this phone, linked (${width}dp, ${scale}x)',
      (tester) async {
        final link = LinkServer();
        final auth = FakeSupabaseAuthPort(restored: snapshot());
        final session = ChumbucketSession(
          auth: auth,
          bff: SessionBffClient(
            baseUrl: kSessionBase,
            httpClient: happyBff().client,
          ),
          lastSignIn: MemoryLastSignInStore(SignInMethod.google),
        );
        final wallet = EmbeddedWalletController(
          vault: EmbeddedWalletVault(store: MemorySecretStore()),
          bff: SessionBffClient(
            baseUrl: kSessionBase,
            httpClient: link.server.client,
          ),
          authToken: session.bffAuthToken,
          generate: () => EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase),
        );
        addTearDown(() async {
          wallet.dispose();
          session.dispose();
          await auth.close();
        });
        await tester.runAsync(() async {
          await session.restore();
          await wallet.bind(session.userId);
        });

        await _mount(
          tester,
          const SingleChildScrollView(child: ProfileWalletCard()),
          width: width,
          scale: scale,
          providers: [
            ChangeNotifierProvider(create: (_) => MwaWalletProvider()),
            ChangeNotifierProvider<ChumbucketSession>.value(value: session),
            ChangeNotifierProvider<EmbeddedWalletController>.value(
              value: wallet,
            ),
          ],
        );
        expect(
          find.text('None yet · make one on this phone to trade'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('profile-embedded-wallet')));
        await tester.pumpAndSettle();
        expect(find.text('Your wallet'), findsOneWidget);
        expect(
          find.textContaining('Chumbucket’s servers never see it'),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Create my wallet'));
        await tester.tap(find.text('Create my wallet'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pumpAndSettle();
        expect(wallet.linked, isTrue);
        expect(
          find.byKey(const ValueKey('embedded-wallet-address')),
          findsOneWidget,
        );
        expect(find.text(kTestPhraseAddress), findsOneWidget);
        expect(find.text('Linked to your Chumbucket account'), findsOneWidget);
        expect(
          find.textContaining('This wallet lives on this phone'),
          findsOneWidget,
        );

        // The phrase only behind an explicit, warned reveal.
        expect(find.textContaining('abandon'), findsNothing);
        await tester.ensureVisible(find.text('Show recovery phrase'));
        await tester.tap(find.text('Show recovery phrase'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Anyone with these 12 words'),
          findsOneWidget,
        );
        expect(find.textContaining('abandon'), findsNothing);
        await tester.ensureVisible(find.text('Show my 12 words'));
        await tester.tap(find.text('Show my 12 words'));
        await tester.pumpAndSettle();
        expect(find.text('1. abandon'), findsOneWidget);
        expect(find.text('12. about'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('the trade sheet with the on-phone wallet', () {
    late SyntheticPantaRig r;
    setUp(() => r = SyntheticPantaRig());
    tearDown(() => r.close());

    testWidgets('says what signing here means, and signs only on the button', (
      tester,
    ) async {
      await _mount(
        tester,
        Builder(
          builder:
              (context) => TextButton(
                onPressed:
                    () => showPantaTradeSheet(
                      context: context,
                      controller: r.controller,
                      marketQuestion: 'Existing call question?',
                      signer: PantaSigner.thisPhone,
                    ),
                child: const Text('Trade'),
              ),
        ),
        providers: [Provider.value(value: 0)],
      );
      await tester.tap(find.text('Trade'));
      await tester.pumpAndSettle();
      final scroll =
          find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .last;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('panta-amount')),
        -200,
        scrollable: scroll,
      );
      await tester.enterText(find.byKey(const ValueKey('panta-amount')), '10');
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Review order'),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.text('Review order'));
      await tester.pumpAndSettle();
      expect(r.controller.phase, PantaTradePhase.review);
      expect(find.text('Approve in wallet'), findsNothing);
      expect(find.textContaining('Check the wallet request'), findsNothing);
      expect(find.textContaining('there is no second screen'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Your wallet on this phone'),
        200,
        scrollable: scroll,
      );
      expect(find.text('Your wallet on this phone'), findsOneWidget);
      expect(r.wallet.signCount, 0);
      await tester.scrollUntilVisible(
        find.text('Sign and buy'),
        200,
        scrollable: scroll,
      );
      await tester.tap(find.text('Sign and buy'));
      await tester.pumpAndSettle();
      expect(r.wallet.signCount, 1);
      await tester.pumpWidget(const SizedBox());
      unawaited(Future<void>.value());
    });
  });
}
