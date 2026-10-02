// Run ONLY in the separately-packaged Android test host documented in
// docs/checkpoints/2026-09-29-local-device-flow.md. Never install over Chumbucket.
// Real ProfileScreen -> Settings -> IdentityLinkSheet -> BFF -> PostgREST -> PG.
// Google and wallet approval are synthetic. No funds or production data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/arena/data/arena_models.dart';
import 'package:chumbucket/features/arena/providers/arena_provider.dart';
import 'package:chumbucket/features/authentication/providers/mwa_auth_provider.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:chumbucket/features/profile/presentation/screens/profile_screen.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/identity_link_sheet.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/profile_settings_sheet.dart';
import 'package:chumbucket/features/profile/providers/profile_provider.dart';
import 'package:chumbucket/features/wallet/providers/mwa_wallet_provider.dart';
import 'package:chumbucket/shared/providers/challenge_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _LocalOnlyHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.scheme != 'http' ||
          uri.host != '127.0.0.1' ||
          proxyHost != null) {
        throw const SocketException('Device test refuses non-loopback traffic');
      }
      return Socket.startConnect(uri.host, uri.port);
    };
    return client;
  }
}

class _SyntheticGoogle implements SupabaseAuthPort {
  _SyntheticGoogle(this.candidate);
  final SupabaseSessionSnapshot candidate;
  final events = StreamController<SupabaseAuthEvent>.broadcast();
  @override
  SupabaseSessionSnapshot? currentSession;
  @override
  Stream<SupabaseAuthEvent> get authEvents => events.stream;
  @override
  Future<bool> startGoogleSignIn({String? redirectTo}) async {
    scheduleMicrotask(() {
      currentSession = candidate;
      events.add(SupabaseAuthEvent(SupabaseAuthEventKind.signedIn, candidate));
    });
    return true;
  }

  @override
  Future<bool> startXSignIn({String? redirectTo}) async => false;
  @override
  Future<SupabaseSessionSnapshot> signInWithSolana({
    required String message,
    required String signature,
  }) async => throw const SolanaSignInException(SolanaSignInException.disabled);
  @override
  Future<Set<String>> enabledProviders() async => const {'google'};
  @override
  Future<SupabaseSessionSnapshot?> refreshSession() async => currentSession;
  @override
  Future<void> signOut() async => currentSession = null;
}

class _SyntheticSigning implements MwaSigningSession {
  _SyntheticSigning(this.key);
  final Ed25519HDKeyPair key;
  @override
  Future<SignMessagesResult> signMessages({
    required List<Uint8List> messages,
    required List<Uint8List> addresses,
  }) async => SignMessagesResult(
    signedMessages: [
      SignedMessage(
        message: messages.single,
        addresses: addresses,
        signatures: [
          Uint8List.fromList(
            base58decode((await key.sign(messages.single)).toBase58()),
          ),
        ],
      ),
    ],
  );
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Messages only');
}

class _ExistingWallet extends MwaAuthProvider {
  _ExistingWallet(this.key, {required this.cancel});
  final Ed25519HDKeyPair key;
  final bool cancel;
  @override
  bool get isAuthenticated => true;
  @override
  String get walletAddress => key.address;
  @override
  Uint8List get publicKeyBytes => Uint8List.fromList(base58decode(key.address));
  @override
  Future<Map<String, dynamic>?> getUserProfile() =>
      Supabase.instance.client
          .from('users')
          .select()
          .eq('wallet_address', walletAddress)
          .single();
  @override
  Future<MwaSigningSession?> createSigningSession({String? cluster}) async =>
      cancel ? null : _SyntheticSigning(key);
}

// Prevent unrelated balances / old Arena services from reaching a real chain.
// Their existing widgets still render in ProfileScreen, under the test banner.
class _NoFunds extends MwaWalletProvider {
  @override
  Future<void> refreshWalletBalance() async {}
}

class _NoArena extends ArenaProvider {
  @override
  Future<void> loadMyPots({required String walletAddress}) async {}
  @override
  Future<ArenaSocialProfile?> loadProfile({
    required String targetWallet,
    String? viewerWallet,
  }) async => null;
}

class _LocalProfile extends ProfileProvider {
  @override
  Future<bool> hasInternetConnection() async => true; // USB loopback, not WAN.
}

class _LocalClient extends http.BaseClient {
  _LocalClient(this.base, {required this.loseClaimReply});
  final Uri base;
  final inner = http.Client();
  bool loseClaimReply;
  final paths = <String>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != base.origin ||
        request.followRedirects ||
        request.url.hasQuery) {
      throw StateError('Device identity transport escaped loopback');
    }
    paths.add(request.url.path);
    final response = await inner.send(request);
    if (loseClaimReply && request.url.path == '/auth.claimExistingAccount') {
      loseClaimReply = false;
      await response.stream.drain<void>();
      throw http.ClientException('Synthetic lost reply after commit');
    }
    return response;
  }

  @override
  void close() => inner.close();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 20)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Timed out waiting for the existing screen/HTTP flow',
  );
  expect(tester.takeException(), isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final gateway = Uri.parse(
    const String.fromEnvironment('CHUM_LOCAL_DEVICE_GATEWAY'),
  );
  if (gateway.scheme != 'http' ||
      gateway.host != '127.0.0.1' ||
      gateway.port == 80 ||
      gateway.path.isNotEmpty ||
      gateway.hasQuery ||
      gateway.userInfo.isNotEmpty) {
    throw StateError('Only a runner-owned loopback gateway is allowed');
  }
  HttpOverrides.global = _LocalOnlyHttp();
  late Map<String, dynamic> config;
  setUpAll(() async {
    final documents = await getApplicationDocumentsDirectory();
    if (!documents.path.contains('/dev.cleva.chumbucket.localtest/')) {
      throw StateError('Refused non-isolated Android package');
    }
    final response = await http.get(gateway.resolve('/__local_test/fixture'));
    if (response.statusCode != 200) {
      throw StateError('Local fixture unavailable');
    }
    config = jsonDecode(response.body) as Map<String, dynamic>;
    dotenv.loadFromString(
      envString:
          'SOLANA_NETWORK=devnet\nARENA_BACKEND_URL=${config['bffBase']}\nSOLANA_RPC_URL=$gateway',
    );
    await Supabase.initialize(
      url: config['supabaseBase'] as String,
      anonKey: config['anonToken'] as String,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    HttpOverrides.global = null;
  });

  for (final name in [
    'success',
    'cancel',
    'unavailable',
    'conflict',
    'retry',
  ]) {
    testWidgets(
      'Seeker existing Profile -> Settings -> local account link: $name',
      (tester) async {
        final f = (config['fixtures'] as List)
            .cast<Map<String, dynamic>>()
            .singleWhere((f) => f['name'] == name);
        final key = await Ed25519HDKeyPair.fromPrivateKeyBytes(
          privateKey: List<int>.filled(32, f['seedByte'] as int),
        );
        expect(key.address == f['address'], isTrue);
        final wallet = _ExistingWallet(key, cancel: name == 'cancel');
        final auth = _SyntheticGoogle(
          SupabaseSessionSnapshot(
            accessToken: f['token'] as String,
            authUserId: f['authId'] as String,
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        final client = _LocalClient(
          Uri.parse(config['bffBase'] as String),
          loseClaimReply: name == 'retry',
        );
        final bff = SessionBffClient(
          baseUrl: config['bffBase'] as String,
          httpClient: client,
        );
        final session = ChumbucketSession(auth: auth, bff: bff);
        final profile = _LocalProfile();
        final arena = _NoArena();
        final funds = _NoFunds();
        final challenges = ChallengeStateProvider(
          loadChallenges: (_) async => [],
        );
        Widget app({required int generation}) => MultiProvider(
          providers: [
            ChangeNotifierProvider<MwaAuthProvider>.value(value: wallet),
            ChangeNotifierProvider<ProfileProvider>.value(value: profile),
            ChangeNotifierProvider<ArenaProvider>.value(value: arena),
            ChangeNotifierProvider<MwaWalletProvider>.value(value: funds),
            ChangeNotifierProvider<ChallengeStateProvider>.value(
              value: challenges,
            ),
            ChangeNotifierProvider<ChumbucketSession>.value(value: session),
          ],
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, _) => MaterialApp(
                  key: ValueKey('$name-$generation'),
                  theme: AppTheme.lightTheme,
                  debugShowCheckedModeBanner: false,
                  builder:
                      (_, child) => Banner(
                        message: 'LOCAL TEST',
                        location: BannerLocation.topStart,
                        child: child!,
                      ),
                  home: const ProfileScreen(),
                ),
          ),
        );
        await tester.pumpWidget(app(generation: 0));
        await _until(
          tester,
          () => find.text('Original $name').evaluate().isNotEmpty,
        );

        Future<void> attempt() async {
          await tester.tap(find.byTooltip('Settings'));
          await tester.pumpAndSettle();
          expect(find.byType(ProfileSettingsSheet), findsOneWidget);
          await tester.ensureVisible(find.text('Link Google'));
          await tester.tap(find.text('Link Google'));
          await _until(
            tester,
            () => find.byType(IdentityLinkSheet).evaluate().isNotEmpty,
          );
          await tester.pumpAndSettle();
          expect(find.text('Create my profile'), findsNothing);
          await tester.tap(find.text('Continue with Google'));
          await _until(
            tester,
            () => session.isReady || session.existingLinkError != null,
          );
          await tester.pumpAndSettle();
        }

        await attempt();
        if (name == 'retry') {
          expect(session.isReady, isFalse);
          expect(
            (await bff.whoami(auth.candidate.accessToken)).userId,
            f['userId'],
          );
          await tester.tap(find.byTooltip('Close').last);
          await tester.pumpAndSettle();
          await attempt();
        }
        if (name == 'success' || name == 'retry') {
          expect(session.userId, f['userId']);
          expect(session.userId == session.authUserId, isFalse);
          expect(find.byType(IdentityLinkSheet), findsNothing);
          expect(find.text('Original $name'), findsOneWidget);
        } else {
          expect(session.userId, isNull);
          expect(session.hasSupabaseSession, isFalse);
          expect(session.existingLinkError?.code, switch (name) {
            'cancel' => 'WALLET_PROOF_CANCELLED',
            'unavailable' => 'ACCOUNT_CLAIM_UNAVAILABLE',
            'conflict' => 'ACCOUNT_CLAIM_CONFLICT',
            _ => throw StateError('Unexpected refusal scenario'),
          });
          expect(
            find.byKey(const ValueKey('account-link-error')),
            findsOneWidget,
          );
          await tester.tap(find.byTooltip('Close').last);
          await tester.pumpAndSettle();
          expect(find.text('Original $name'), findsOneWidget);
        }
        expect(client.paths, isNot(contains('/auth.completeProfile')));
        // Re-mount the same production profile and refetch from actual PostgREST.
        await tester.pumpWidget(app(generation: 1));
        await _until(
          tester,
          () => find.text('Original $name').evaluate().isNotEmpty,
        );
        final original = await wallet.getUserProfile();
        expect(original?['id'], f['userId']);
        expect(original?['history'], ['old-history']);
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        wallet.dispose();
        profile.dispose();
        arena.dispose();
        funds.dispose();
        challenges.dispose();
        client.close();
        await auth.events.close();
        final report = await http.post(
          gateway.resolve('/__local_test/report'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'name': name}),
        );
        expect(report.statusCode, 200);
      },
    );
  }
}
