/// Settings → Sign-in methods: what the BFF says, read strictly; the wire
/// (tokens in bodies, the other side's token as its own input); and the
/// controller's flows — link, the move after "already on another account",
/// unlink — with the proof's session always released. No socket, no
/// browser, no Supabase: a fake BFF and a fake port.
library;

import 'dart:convert';

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/sign_in_link_port.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods_controller.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/authentication/session/wallet_link_proof.dart';
import 'package:chumbucket/core/theme/app_theme.dart';
import 'package:chumbucket/features/profile/presentation/screens/widgets/sign_in_methods_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

const _wallet = 'F7rhCwoPyU5H1p48sddDmGb1ax25CwmxiwHL8Xj5RJ3E';
const _signIn = '5a1e0000-0000-4000-8000-000000000001';
final _ticket = 'ab' * 32;

const _chumbucketWallet = '9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin';

/// The owner's account after the fold, as `auth.signInMethods` answers.
/// [chumbucket]: with the account's Chumbucket wallet, a read-only row.
Map<String, Object?> ownerMethods({
  bool linking = true,
  bool chumbucket = false,
}) => {
  'linking': linking,
  'fold': linking,
  'methods': [
    if (chumbucket)
      {
        'id': 'w:$_chumbucketWallet',
        'kind': 'wallet',
        'label': _chumbucketWallet,
        'current': false,
        // Never honoured for the Chumbucket wallet, even if a server sent it.
        'unlink': {'mode': 'server', 'ref': 'w:$_chumbucketWallet'},
        'alsoUnlinks': <String>[],
        'chumbucket': true,
      },
    {
      'id': 'id-web3',
      'kind': 'wallet',
      'label': _wallet,
      'current': true,
      'unlink': null,
      'alsoUnlinks': <String>[],
    },
    {
      'id': 'id-x',
      'kind': 'x',
      'label': 'ownerx',
      'current': false,
      'unlink': {'mode': 'server', 'ref': 's:$_signIn'},
      'alsoUnlinks': ['google'],
    },
    {'id': 'junk', 'kind': 'email', 'label': 'x@y.z'},
    {'kind': 'google'},
  ],
};

Map<String, Object?> foldPreview({String? refusal}) => {
  'outcome': 'fold',
  'proof': {'kind': 'x', 'label': 'ownerx'},
  'otherUserId': 'user-dominion',
  'into': {'userId': 'user-dev', 'handle': 'dev', 'displayName': 'Dev'},
  'from': {'userId': 'user-dominion', 'handle': 'dominion'},
  'refusal': refusal,
};

/// `auth.requestWalletNonce` for link_wallet, built as the BFF builds it.
Map<String, Object?> linkNonce(String address) {
  final issued = DateTime.now().toUtc();
  final at = DateTime.fromMillisecondsSinceEpoch(
    issued.millisecondsSinceEpoch,
    isUtc: true,
  );
  final issuedAt = at.toIso8601String();
  final expiresAt = at.add(const Duration(minutes: 5)).toIso8601String();
  final message = [
    'chumbucket.fun wants you to sign in with your Solana account:',
    address,
    '',
    walletLinkStatement,
    '',
    'URI: https://chumbucket.fun',
    'Version: 1',
    'Chain ID: ${siwsChainId('devnet')}',
    'Nonce: ${'ab' * 32}',
    'Issued At: $issuedAt',
    'Expiration Time: $expiresAt',
    'Resources:',
    '- chumbucket:purpose:link_wallet',
  ].join('\n');
  return {
    'message': message,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'domain': 'chumbucket.fun',
    'uri': 'https://chumbucket.fun',
    'network': 'devnet',
    'purpose': 'link_wallet',
    'proofVersion': 1,
  };
}

class FakeLinkPort implements SignInLinkPort {
  String? providerResult;
  Object? proveError;
  final started = <SignInMethodKind>[];
  final proved = <SignInMethodKind>[];
  final unlinked = <String>[];
  final released = <String>[];

  @override
  Future<void> startProviderLink(SignInMethodKind kind) async =>
      started.add(kind);

  @override
  Future<String?> providerLinkResult({Duration? timeout}) async =>
      providerResult;

  @override
  Future<void> unlinkIdentity(String identityId) async =>
      unlinked.add(identityId);

  @override
  Future<String> proveProvider(
    SignInMethodKind kind, {
    Duration? timeout,
  }) async {
    proved.add(kind);
    if (proveError != null) throw proveError!;
    return 'other-token';
  }

  @override
  Future<String> proveWallet(SolanaSignInWallet wallet) async {
    proved.add(SignInMethodKind.wallet);
    return 'wallet-token';
  }

  @override
  Future<void> release(String accessToken) async => released.add(accessToken);
}

class FakeWallet implements SolanaSignInWallet {
  @override
  Future<String> connect() async => _wallet;

  @override
  Future<String> sign(String message) async =>
      base64Url.encode(List<int>.filled(64, 7));
}

/// A BFF that answers the link procedures and records them.
FakeBffServer linkServer({
  Map<String, Object?>? preview,
  String? completeError,
  String? linkWalletError,
  Map<String, Object?>? methods,
}) => FakeBffServer((request) {
  switch (request.procedurePath) {
    case 'auth.signInMethods':
      return okResponse(methods ?? ownerMethods());
    case 'auth.startSignInLink':
      return okResponse({
        'ticket': 'ab' * 32,
        'method': request.input['method'],
        'expiresAt': '2026-10-04T10:10:00.000Z',
      });
    case 'auth.previewSignInLink':
      return okResponse(preview ?? foldPreview());
    case 'auth.completeSignInLink':
      if (completeError != null) {
        return errorResponse(
          code: 'CONFLICT',
          httpStatus: 409,
          message: completeError,
        );
      }
      return okResponse({'outcome': 'folded', 'userId': 'user-dev'});
    case 'auth.unlinkSignIn':
      return okResponse({'signIns': 1, 'wallets': 0});
    case 'auth.requestWalletNonce':
      return okResponse(linkNonce(request.input['address'] as String));
    case 'auth.linkWallet':
      if (linkWalletError != null) {
        return errorResponse(
          code: 'CONFLICT',
          httpStatus: 409,
          message: linkWalletError,
        );
      }
      return okResponse({
        'address': request.input['address'],
        'outcome': 'linked',
      });
  }
  return errorResponse(code: 'NOT_FOUND', httpStatus: 404, message: 'nope');
});

SignInMethodsController controllerFor(
  FakeBffServer server,
  FakeLinkPort port, {
  SolanaSignInWallet? wallet,
}) => SignInMethodsController(
  accessToken: () async => kAccessToken,
  bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
  port: port,
  wallet: wallet,
);

void main() {
  group('what the BFF says, read strictly', () {
    test('rows, the current one, and what can be linked', () {
      final methods = SignInMethods.parse(ownerMethods())!;
      expect(methods.rows.map((r) => r.kind), [
        SignInMethodKind.wallet,
        SignInMethodKind.x,
      ]);
      expect(methods.current!.display, 'F7rh…RJ3E');
      expect(methods.rows[1].display, '@ownerx');
      expect(methods.rows[1].unlink!.serverRef, 's:$_signIn');
      expect(methods.rows[1].alsoUnlinks, [SignInMethodKind.google]);
      expect(methods.missing, [SignInMethodKind.google]);
      // Linking off: nothing is offered.
      expect(SignInMethods.parse(ownerMethods(linking: false))!.missing, []);
      expect(SignInMethods.parse({'methods': 'nope'}), isNull);
    });

    test('the Chumbucket wallet is read-only, and Link Wallet stays', () {
      final methods = SignInMethods.parse(ownerMethods(chumbucket: true))!;
      final own = methods.rows.firstWhere((r) => r.chumbucket);
      expect(own.kind, SignInMethodKind.wallet);
      expect(own.display, '9xQe…VFin');
      expect(own.unlink, isNull);
      expect(methods.rows.where((r) => r.chumbucket), hasLength(1));
      // Only a wallet row the BFF marks counts as the Chumbucket wallet.
      expect(methods.current!.chumbucket, isFalse);
      // A wallet app can still be linked beside it.
      final alone =
          SignInMethods.parse({
            'linking': true,
            'methods': [
              (ownerMethods(chumbucket: true)['methods'] as List).first,
            ],
          })!;
      expect(alone.missing, SignInMethodKind.values);
      expect(
        signInLinkCopy('CHUMBUCKET_WALLET_KEPT'),
        'Your Chumbucket wallet stays with your account.',
      );
    });

    test('a preview names both accounts and why not, when not', () {
      final p = LinkPreview.parse(foldPreview(refusal: 'ACCOUNT_HAS_MONEY'))!;
      expect(p.outcome, LinkOutcome.fold);
      expect(p.from!.display, '@dominion');
      expect(p.into.display, '@dev');
      expect(signInLinkCopy(p.refusal!), contains('stays separate'));
      expect(LinkPreview.parse({'outcome': 'merge'}), isNull);
    });
  });

  group('the wire', () {
    test('tokens travel in bodies; the other side is its own input', () async {
      final server = linkServer();
      final bff = SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: server.client,
      );
      await bff.signInMethods(kAccessToken);
      final listed = server.requestFor('auth.signInMethods');
      expect(listed.method, 'POST');
      expect(listed.url.query, isEmpty);
      expect(listed.input, {'supabaseAccessToken': kAccessToken});

      final ticket = await bff.startSignInLink(
        kAccessToken,
        method: SignInMethodKind.x,
      );
      expect(ticket, _ticket);
      await bff.previewSignInLink(
        kAccessToken,
        otherAccessToken: 'other-token',
        ticket: ticket,
      );
      final preview = server.requestFor('auth.previewSignInLink');
      expect(preview.input, {
        'supabaseAccessToken': 'other-token',
        'ticket': _ticket,
      });
      expect(preview.headers['authorization'], 'Bearer $kAccessToken');
    });

    test('a refusal arrives as its code, with one line', () async {
      final server = linkServer(completeError: 'ACCOUNT_HAS_MONEY');
      final bff = SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: server.client,
      );
      try {
        await bff.completeSignInLink(
          kAccessToken,
          otherAccessToken: 'other-token',
          ticket: _ticket,
          preview: LinkPreview.parse(foldPreview())!,
        );
        fail('expected a refusal');
      } on SessionException catch (e) {
        expect(e.error.code, 'ACCOUNT_HAS_MONEY');
        expect(e.error.kind, SessionErrorKind.refused);
      }
    });
  });

  group('the controller', () {
    test('X already on another account: prove it, preview, move', () async {
      final server = linkServer();
      final port = FakeLinkPort()..providerResult = 'identity_already_exists';
      final c = controllerFor(server, port);
      await c.load();
      expect(c.methods!.rows, hasLength(2));

      await c.linkProvider(SignInMethodKind.x);
      expect(port.started, [SignInMethodKind.x]);
      expect(c.move!.stage, MoveStage.conflict);

      await c.prove();
      expect(port.proved, [SignInMethodKind.x]);
      expect(c.move!.stage, MoveStage.preview);
      expect(c.move!.preview!.from!.display, '@dominion');
      // The ticket is issued to this app's account, with its own token.
      expect(server.requestFor('auth.startSignInLink').input, {
        'supabaseAccessToken': kAccessToken,
        'method': 'x',
      });

      await c.confirm();
      // The confirm names exactly what the person was shown.
      expect(server.requestFor('auth.completeSignInLink').input, {
        'supabaseAccessToken': 'other-token',
        'ticket': _ticket,
        'expect': {'outcome': 'fold', 'otherUserId': 'user-dominion'},
      });
      expect(c.move, isNull);
      expect(c.line, '@dominion moved here');
      expect(port.released, ['other-token']);
    });

    test(
      'a refused move changes nothing and still releases the proof',
      () async {
        final port = FakeLinkPort()..providerResult = 'identity_already_exists';
        final c = controllerFor(
          linkServer(preview: foldPreview(refusal: 'ACCOUNT_HAS_MONEY')),
          port,
        );
        await c.linkProvider(SignInMethodKind.google);
        await c.prove();
        expect(c.move!.preview!.refusal, 'ACCOUNT_HAS_MONEY');
        c.cancelMove();
        expect(c.move, isNull);
        expect(port.released, ['other-token']);

        final failing =
            FakeLinkPort()
              ..providerResult = 'identity_already_exists'
              ..proveError = const SignInLinkStopped('cancelled');
        final d = controllerFor(linkServer(), failing);
        await d.linkProvider(SignInMethodKind.x);
        await d.prove();
        expect(d.move, isNull);
        expect(d.line, 'Nothing changed.');
      },
    );

    test(
      'linked without a conflict: says so; Supabase refusals as a line',
      () async {
        // "Linked" only when the account's own sign-ins say so; a callback
        // alone (here, X is on the account) proves nothing.
        final ok = controllerFor(linkServer(), FakeLinkPort());
        await ok.linkProvider(SignInMethodKind.x);
        expect(ok.move, isNull);
        expect(ok.line, 'X linked');
        final unsolicited = controllerFor(linkServer(), FakeLinkPort());
        await unsolicited.linkProvider(SignInMethodKind.google);
        expect(unsolicited.line, isNull);

        final off = controllerFor(
          linkServer(),
          FakeLinkPort()..providerResult = 'manual_linking_disabled',
        );
        await off.linkProvider(SignInMethodKind.x);
        expect(off.line, 'Linking isn’t on yet.');
      },
    );

    test(
      'a wallet on another account starts a move proven by the wallet',
      () async {
        final port = FakeLinkPort();
        final c = controllerFor(
          linkServer(linkWalletError: 'WALLET_OWNED_BY_ANOTHER_USER'),
          port,
          wallet: FakeWallet(),
        );
        await c.linkWallet();
        expect(c.move!.stage, MoveStage.conflict);
        expect(c.move!.method, SignInMethodKind.wallet);
        await c.prove();
        expect(port.proved, [SignInMethodKind.wallet]);
        expect(c.move!.proof, 'wallet-token');
      },
    );

    test('no wallet on this phone: Link is not offered for one', () async {
      final c = controllerFor(linkServer(), FakeLinkPort());
      await c.load();
      expect(c.linkable, [SignInMethodKind.google]);
    });

    test('unlink goes where the row says', () async {
      final server = linkServer();
      final port = FakeLinkPort();
      final c = controllerFor(server, port);
      await c.load();
      await c.unlink(c.methods!.rows[1]);
      expect(server.requestFor('auth.unlinkSignIn').input, {
        'supabaseAccessToken': kAccessToken,
        'ref': 's:$_signIn',
      });
      await c.unlink(
        const SignInMethodRow(
          id: 'id-google',
          kind: SignInMethodKind.google,
          label: 'owner@example.com',
          current: false,
          unlink: SignInUnlink.native('id-google'),
        ),
      );
      expect(port.unlinked, ['id-google']);
      // A row with no route is never sent anywhere.
      await c.unlink(c.methods!.rows[0]);
      expect(
        server.received.where((r) => r.procedurePath == 'auth.unlinkSignIn'),
        hasLength(1),
      );
    });

    test('leaving mid-move releases the proof', () async {
      final port = FakeLinkPort()..providerResult = 'identity_already_exists';
      final c = controllerFor(linkServer(), port);
      await c.linkProvider(SignInMethodKind.x);
      await c.prove();
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(port.released, ['other-token']);
    });
  });

  group('the sheet', () {
    Future<SignInMethodsController> pump(
      WidgetTester tester,
      FakeLinkPort port, {
      Map<String, Object?>? methods,
    }) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = controllerFor(linkServer(methods: methods), port);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, _) => MaterialApp(
                theme: AppTheme.lightTheme,
                home: Scaffold(
                  body: ChangeNotifierProvider<SignInMethodsController>.value(
                    value: c,
                    child: const SignInMethodsSheet(),
                  ),
                ),
              ),
        ),
      );
      await tester.runAsync(c.load);
      await tester.pump();
      return c;
    }

    testWidgets('signed in with, the rows, Link for the rest', (tester) async {
      await pump(tester, FakeLinkPort());
      expect(find.byKey(const ValueKey('signed-in-with')), findsOneWidget);
      expect(find.text('F7rh…RJ3E'), findsNWidgets(2));
      expect(find.text('@ownerx'), findsOneWidget);
      expect(find.byKey(const ValueKey('link-google')), findsOneWidget);
      expect(find.byTooltip('Unlink X'), findsOneWidget);
      // The way in being used has no unlink.
      expect(find.byTooltip('Unlink Wallet'), findsNothing);
    });

    testWidgets(
      'the Chumbucket wallet: icon, short address, label, no unlink',
      (tester) async {
        await pump(
          tester,
          FakeLinkPort(),
          methods: ownerMethods(chumbucket: true),
        );
        final row = find.byKey(const ValueKey('sign-in-w:$_chumbucketWallet'));
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.text('9xQe…VFin')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.text('Chumbucket wallet')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.byType(IconButton)),
          findsNothing,
        );
        // The other rows keep their rules; a wallet app can still be linked.
        expect(find.byTooltip('Unlink X'), findsOneWidget);
        expect(find.byTooltip('Unlink Wallet'), findsNothing);
        expect(find.byKey(const ValueKey('link-wallet')), findsNothing);
        expect(find.byKey(const ValueKey('link-google')), findsOneWidget);
      },
    );

    testWidgets('a move shows both accounts before anything happens', (
      tester,
    ) async {
      final port = FakeLinkPort()..providerResult = 'identity_already_exists';
      final c = await pump(tester, port);
      await tester.runAsync(() => c.linkProvider(SignInMethodKind.x));
      await tester.pump();
      expect(find.byKey(const ValueKey('move-conflict')), findsOneWidget);
      expect(find.text('Continue with X'), findsOneWidget);
      await tester.runAsync(c.prove);
      await tester.pump();
      expect(find.byKey(const ValueKey('move-preview')), findsOneWidget);
      // What was proven, then where it goes: "@ownerx → @dev", from @dominion.
      final proof = find.byKey(const ValueKey('link-proof'));
      expect(
        find.descendant(of: proof, matching: find.text('@ownerx')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: proof, matching: find.text('@dev')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('link-from')), findsOneWidget);
      expect(find.text('@dominion'), findsOneWidget);
      expect(find.text('Move here'), findsOneWidget);
    });
  });

  group('the proof: PKCE in an auth session, this attempt only', () {
    SupabaseSignInLinkPort portWith(
      Future<String> Function(String url) launch,
      List<http.Request> exchanged,
    ) => SupabaseSignInLinkPort(
      baseUrl: 'https://auth.test.invalid',
      anonKey: 'anon-test',
      launcher:
          ({required String url, required String callbackUrlScheme}) =>
              launch(url),
      client: MockClient((request) async {
        exchanged.add(request);
        return http.Response(
          jsonEncode({'access_token': 'proof-token', 'refresh_token': 'drop'}),
          200,
        );
      }),
    );

    test(
      'the right callback is exchanged with this attempt\'s verifier',
      () async {
        final exchanged = <http.Request>[];
        late Uri authorize;
        final port = portWith((url) async {
          authorize = Uri.parse(url);
          final back = Uri.parse(authorize.queryParameters['redirect_to']!);
          return back
              .replace(
                queryParameters: {
                  ...back.queryParameters,
                  'code': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
                },
              )
              .toString();
        }, exchanged);
        expect(await port.proveProvider(SignInMethodKind.x), 'proof-token');
        expect(authorize.queryParameters['provider'], 'x');
        expect(authorize.queryParameters['code_challenge_method'], 's256');
        final back = Uri.parse(authorize.queryParameters['redirect_to']!);
        expect('${back.scheme}://${back.host}', kSignInProofCallback);
        expect(back.queryParameters['n'], isNotEmpty);
        // The verifier never left memory until the exchange, and matches.
        expect(authorize.toString(), isNot(contains('code_verifier')));
        final body = jsonDecode(exchanged.single.body) as Map<String, dynamic>;
        expect(body['auth_code'], 'f47ac10b-58cc-4372-a567-0e02b2c3d479');
        final challenge = base64UrlEncode(
          sha256.convert(ascii.encode(body['code_verifier'] as String)).bytes,
        ).replaceAll('=', '');
        expect(challenge, authorize.queryParameters['code_challenge']);
      },
    );

    test('unsolicited, wrong-nonce and wrong-host callbacks are refused', () async {
      for (final forge in <String Function(Uri back)>[
        (_) =>
            'dev.cleva.chumbucket://link-callback?code=f47ac10b-58cc-4372-a567-0e02b2c3d479',
        (_) =>
            'dev.cleva.chumbucket://link-callback?n=someone-else&code=f47ac10b-58cc-4372-a567-0e02b2c3d479',
        (back) =>
            back
                .replace(
                  host: 'login-callback',
                  queryParameters: {
                    ...back.queryParameters,
                    'code': 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
                  },
                )
                .toString(),
        (back) => back.toString(), // this attempt, but no code
        (back) => '$back#access_token=forged.token.here',
      ]) {
        final exchanged = <http.Request>[];
        final port = portWith((url) async {
          final back = Uri.parse(
            Uri.parse(url).queryParameters['redirect_to']!,
          );
          return forge(back);
        }, exchanged);
        await expectLater(
          port.proveProvider(SignInMethodKind.google),
          throwsA(isA<SignInLinkStopped>()),
        );
        expect(exchanged, isEmpty);
      }
    });

    test('a cancelled session or a refusal proves nothing', () async {
      final exchanged = <http.Request>[];
      final cancelled = portWith(
        (_) async => throw Exception('CANCELED'),
        exchanged,
      );
      await expectLater(
        cancelled.proveProvider(SignInMethodKind.x),
        throwsA(
          isA<SignInLinkStopped>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      final refused = portWith((url) async {
        final back = Uri.parse(Uri.parse(url).queryParameters['redirect_to']!);
        return back
            .replace(
              queryParameters: {
                ...back.queryParameters,
                'error_code': 'access_denied',
              },
            )
            .toString();
      }, exchanged);
      await expectLater(
        refused.proveProvider(SignInMethodKind.x),
        throwsA(
          isA<SignInLinkStopped>().having(
            (e) => e.code,
            'code',
            'access_denied',
          ),
        ),
      );
      expect(exchanged, isEmpty);
    });
  });
}
