import 'dart:typed_data';

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/deposits/data/device_deposit_wallet_source.dart';
import 'package:chumbucket/features/deposits/data/deposit_order_memory.dart';
import 'package:chumbucket/features/deposits/domain/deposit_wallet_source.dart';
import 'package:chumbucket/features/deposits/presentation/crossmint_checkout_screen.dart';
import 'package:chumbucket/features/deposits/presentation/deposits_dependencies.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'deposits_fakes.dart';

/// A connected wallet app with no network behind it.
class ConnectedWallet extends MwaWalletProvider {
  int refreshes = 0;
  @override
  String? get walletAddress => walletA;
  @override
  bool get isInitialized => true;
  @override
  Future<void> refreshWalletBalance() async => refreshes++;
}

void main() {
  // MwaWalletProvider reads its network from the env; no RPC is ever called.
  setUpAll(() => dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet'));

  group('Profile → My wallet', () {
    testWidgets('Add funds is the wallet sheet\'s first action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final bff = FakeDepositsBff();
      final wallet = ConnectedWallet();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DepositsDependencies?>.value(
              value: DepositsDependencies(
                createClient: bff.newClient,
                accountId: 'user-1',
                memory: InMemoryDepositOrderMemory(),
              ),
            ),
            ChangeNotifierProvider<MwaWalletProvider?>.value(value: wallet),
          ],
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, _) => MaterialApp(
                  theme: AppTheme.lightTheme,
                  home: const Scaffold(body: ProfileWalletCard()),
                ),
          ),
        ),
      );
      await tester.tap(find.text('My wallet'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-add-funds')), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-receive')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('profile-add-funds')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // The wallet sheet's own mainnet balance, and Add funds' above it.
      expect(
        find.byKey(const ValueKey('deposit-balance-card')),
        findsNWidgets(2),
      );
      expect(bff.inputs('status'), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('checkout WebView rules', () {
    test('Android WebView agent reads as Chrome, keeping real versions', () {
      const wv =
          'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A; wv) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Version/4.0 Chrome/126.0.6478.71 Mobile Safari/537.36';
      final agent = browserUserAgent(wv, isIOS: false);
      expect(agent, isNot(contains('; wv')));
      expect(agent, isNot(contains('Version/4.0')));
      expect(agent, contains('Chrome/126.0.6478.71'));
      expect(agent, contains('Android 14'));
    });

    test('WKWebView agent gains the Safari markers Apple Pay looks for', () {
      const wk =
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Mobile/15E148';
      final agent = browserUserAgent(wk, isIOS: true);
      expect(agent, contains('Version/17.5'));
      expect(agent, endsWith('Safari/604.1'));
      expect(browserUserAgent(null, isIOS: true), contains('iPhone'));
      expect(browserUserAgent('', isIOS: false), contains('Android'));
    });

    test('web pages may load; nothing may leave the web', () {
      for (final ok in [
        'https://www.crossmint.com/sdk/2024-03-05/embedded-checkout',
        'https://js.stripe.com/v3',
        'https://inquiry.withpersona.com/verify',
        'about:blank',
      ]) {
        expect(
          checkoutNavigationDecision(ok),
          NavigationDecision.navigate,
          reason: ok,
        );
      }
      for (final blocked in [
        'intent://pay#Intent;end',
        'javascript:alert(1)',
        'file:///etc/hosts',
        'http://crossmint.com',
        'solana:abc',
      ]) {
        expect(
          checkoutNavigationDecision(blocked),
          NavigationDecision.prevent,
          reason: blocked,
        );
      }
    });

    test('camera or microphone requests go to the browser', () {
      expect(
        checkoutPermissionNeedsBrowser({WebViewPermissionResourceType.camera}),
        isTrue,
      );
      expect(
        checkoutPermissionNeedsBrowser({
          WebViewPermissionResourceType.microphone,
        }),
        isTrue,
      );
      expect(checkoutPermissionNeedsBrowser({}), isFalse);
    });
  });

  group('device wallet source (fleet/identity plugs in here)', () {
    test('signs with the key that is current, and only that key', () async {
      var current = walletA;
      final source = DeviceDepositWalletSource(
        address: walletA,
        currentAddress: () => current,
        sign: (m) async => Uint8List(64),
      );
      expect(source.kind, DepositWalletKind.device);
      expect(
        await source.signMessage(Uint8List.fromList([1, 2])),
        hasLength(64),
      );
      current = walletB;
      expect(source.isCurrent, isFalse);
      await expectLater(
        source.signMessage(Uint8List.fromList([1])),
        throwsA(isA<DepositWalletDeclined>()),
      );
    });

    test(
      'key-store errors and malformed signatures become a refusal',
      () async {
        final throwing = DeviceDepositWalletSource(
          address: walletA,
          currentAddress: () => walletA,
          sign: (_) async => throw StateError('secret key material'),
        );
        await expectLater(
          throwing.signMessage(Uint8List(1)),
          throwsA(isA<DepositWalletDeclined>()),
        );
        final short = DeviceDepositWalletSource(
          address: walletA,
          currentAddress: () => walletA,
          sign: (_) async => Uint8List(10),
        );
        await expectLater(
          short.signMessage(Uint8List(1)),
          throwsA(isA<DepositWalletDeclined>()),
        );
      },
    );
  });
}
