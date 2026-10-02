/// A wallet account whose session came back (a restart, or a reinstall through
/// Block Store) without its wallet app connected: the app knows which wallet
/// it signed in with — from the session's own verified `web3` identity, by the
/// BFF's rule — and offers to reconnect that wallet app rather than make a
/// second wallet on the phone. A Google or X account is offered both.
library;

import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/last_sign_in.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_controller.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_key.dart';
import 'package:chumbucket/features/embedded_wallet/embedded_wallet_vault.dart';
import 'package:chumbucket/features/embedded_wallet/presentation/embedded_wallet_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_wallet_card.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserIdentity;

import 'identity_embedded_wallet_test.dart' show LinkServer;
import 'identity_fakes.dart';
import 'session_fakes.dart';

/// A real-shaped Solana address (the BIP-39 test phrase's first account).
const _wallet = 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk';
const _other = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';

UserIdentity _identity({
  required String provider,
  String id = 'identity-row',
  Map<String, dynamic>? data,
}) => UserIdentity(
  id: id,
  userId: kAuthUserId,
  identityData: data,
  identityId: '00000000-0000-4000-8000-00000000000a',
  provider: provider,
  createdAt: null,
  lastSignInAt: null,
);

class _Rig {
  _Rig({String? signInWallet})
    : auth = FakeSupabaseAuthPort(
        restored: SupabaseSessionSnapshot(
          accessToken: kAccessToken,
          authUserId: kAuthUserId,
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          solanaWallet: signInWallet,
        ),
      ) {
    session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: happyBff().client,
      ),
      lastSignIn: MemoryLastSignInStore(),
    );
    wallet = EmbeddedWalletController(
      vault: EmbeddedWalletVault(store: MemorySecretStore()),
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: link.server.client,
      ),
      authToken: session.bffAuthToken,
      generate: () => EmbeddedWalletKey.fromRecoveryPhrase(kTestPhrase),
    );
  }

  final FakeSupabaseAuthPort auth;
  final link = LinkServer();
  late final ChumbucketSession session;
  late final EmbeddedWalletController wallet;
  int connects = 0;
  bool connectSucceeds = true;

  Future<bool> connect(BuildContext _) async {
    connects++;
    return connectSucceeds;
  }

  Future<void> ready(WidgetTester tester) => tester.runAsync(() async {
    await session.restore();
    await wallet.bind(session.userId);
  });

  Future<void> dispose() async {
    wallet.dispose();
    session.dispose();
    await auth.close();
  }

  Widget app(Widget child, {double width = 390, double scale = 1}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MwaAuthProvider()),
          ChangeNotifierProvider(create: (_) => MwaWalletProvider()),
          ChangeNotifierProvider<ChumbucketSession>.value(value: session),
          ChangeNotifierProvider<EmbeddedWalletController>.value(value: wallet),
        ],
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
      );

  /// A button that opens the wallet sheet with this rig's connector.
  Widget opener() => Builder(
    builder:
        (context) => TextButton(
          onPressed:
              () => showEmbeddedWalletSheet(context, connectWalletApp: connect),
          child: const Text('Open wallet'),
        ),
  );
}

Future<void> _size(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    dotenv.loadFromString(envString: 'SOLANA_NETWORK=devnet');
  });

  group('verifiedSolanaWallet (the BFF solanaWalletOf rule)', () {
    test('a web3 identity names its address by provider id or claims', () {
      expect(
        verifiedSolanaWallet([
          _identity(provider: 'web3', data: {'sub': 'web3:solana:$_wallet'}),
        ]),
        _wallet,
      );
      expect(
        verifiedSolanaWallet([
          _identity(provider: 'web3', id: 'web3:solana:$_wallet'),
        ]),
        _wallet,
      );
      expect(
        verifiedSolanaWallet([
          _identity(
            provider: 'web3',
            data: {
              'custom_claims': {'chain': 'solana', 'address': _wallet},
            },
          ),
        ]),
        _wallet,
      );
    });

    test('Google, X, a disagreement or a non-address yield nothing', () {
      expect(verifiedSolanaWallet(null), isNull);
      expect(
        verifiedSolanaWallet([
          _identity(provider: 'google', data: {'sub': 'web3:solana:$_wallet'}),
          _identity(provider: 'x'),
        ]),
        isNull,
      );
      // Provider id and claims must agree, or neither is used.
      expect(
        verifiedSolanaWallet([
          _identity(
            provider: 'web3',
            data: {
              'sub': 'web3:solana:$_wallet',
              'custom_claims': {'chain': 'solana', 'address': _other},
            },
          ),
        ]),
        isNull,
      );
      expect(
        verifiedSolanaWallet([
          _identity(provider: 'web3', data: {'sub': 'web3:solana:not-base58!'}),
        ]),
        isNull,
      );
      // Base58, but fewer than 32 bytes.
      expect(
        verifiedSolanaWallet([
          _identity(provider: 'web3', data: {'sub': 'web3:solana:${'2' * 32}'}),
        ]),
        isNull,
      );
      // 32 bytes, but a small-order point (the all-zero key): nobody holds it.
      expect(
        verifiedSolanaWallet([
          _identity(provider: 'web3', data: {'sub': 'web3:solana:${'1' * 32}'}),
        ]),
        isNull,
      );
      expect(
        verifiedSolanaWallet([
          _identity(
            provider: 'web3',
            data: {
              'custom_claims': {'chain': 'ethereum', 'address': _wallet},
            },
          ),
        ]),
        isNull,
      );
    });
  });

  group('the session', () {
    test(
      'a restored wallet session knows the wallet it signed in with',
      () async {
        final r = _Rig(signInWallet: _wallet);
        addTearDown(r.dispose);
        await r.session.restore();
        expect(r.session.isReady, isTrue);
        expect(r.session.isWalletSession, isTrue);
        expect(r.session.signInWallet, _wallet);
        expect(r.session.toString(), isNot(contains(kAccessToken)));
      },
    );

    test('a Google or X session has none', () async {
      final r = _Rig();
      addTearDown(r.dispose);
      await r.session.restore();
      expect(r.session.isReady, isTrue);
      expect(r.session.isWalletSession, isFalse);
      expect(r.session.signInWallet, isNull);
    });
  });

  for (final (width, scale) in [(390.0, 1.0), (320.0, 2.0)]) {
    testWidgets(
      'a wallet account reconnects its wallet app, not a second wallet '
      '(${width}dp, ${scale}x)',
      (tester) async {
        await _size(tester, width);
        final r = _Rig(signInWallet: _wallet);
        addTearDown(r.dispose);
        await r.ready(tester);

        await tester.pumpWidget(
          r.app(
            Column(
              children: [
                const ProfileWalletCard(),
                Expanded(child: Center(child: r.opener())),
              ],
            ),
            width: width,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(shortWalletAddress(_wallet), 'HAgk…Kpqk');
        expect(find.text('HAgk…Kpqk · reconnect to trade'), findsOneWidget);

        await tester.tap(find.text('Open wallet'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('embedded-wallet-reconnect-copy')),
          findsOneWidget,
        );
        expect(find.text('Create my wallet'), findsNothing);

        await tester.ensureVisible(find.text('Reconnect my wallet'));
        await tester.tap(find.text('Reconnect my wallet'));
        await tester.pumpAndSettle();
        expect(r.connects, 1);
        // Connected: the sheet closes; no wallet was made on the phone.
        expect(find.text('Reconnect my wallet'), findsNothing);
        expect(r.wallet.hasWallet, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a failed reconnect keeps the sheet, and making one here stays '
      'possible', (tester) async {
    await _size(tester, 390);
    final r = _Rig(signInWallet: _wallet)..connectSucceeds = false;
    addTearDown(r.dispose);
    await r.ready(tester);
    await tester.pumpWidget(r.app(Center(child: r.opener())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open wallet'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Reconnect my wallet'));
    await tester.tap(find.text('Reconnect my wallet'));
    await tester.pumpAndSettle();
    expect(r.connects, 1);
    expect(find.text('Reconnect my wallet'), findsOneWidget);

    await tester.ensureVisible(
      find.text('Make a wallet on this phone instead'),
    );
    await tester.tap(find.text('Make a wallet on this phone instead'));
    await tester.pumpAndSettle();
    expect(find.text('Create my wallet'), findsOneWidget);
    expect(r.wallet.hasWallet, isFalse);
  });

  testWidgets('a Google or X account may use a wallet app instead', (
    tester,
  ) async {
    await _size(tester, 390);
    final r = _Rig();
    addTearDown(r.dispose);
    await r.ready(tester);
    await tester.pumpWidget(
      r.app(
        Column(
          children: [
            const ProfileWalletCard(),
            Expanded(child: Center(child: r.opener())),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('None yet · make one on this phone to trade'),
      findsOneWidget,
    );
    await tester.tap(find.text('Open wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Create my wallet'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('embedded-wallet-reconnect-copy')),
      findsNothing,
    );
    await tester.ensureVisible(find.text('Use a wallet app instead'));
    await tester.tap(find.text('Use a wallet app instead'));
    await tester.pumpAndSettle();
    expect(r.connects, 1);
    expect(r.wallet.hasWallet, isFalse);
  });
}
