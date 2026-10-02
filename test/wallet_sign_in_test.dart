// Wallet sign-in, X sign-in and the @username claim.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

const _address = 'Dom1nionWa11et1111111111111111111111111111';

class _FakeWallet implements SolanaSignInWallet {
  final signed = <String>[];
  bool declines = false;

  @override
  Future<String> connect() async => _address;

  @override
  Future<String> sign(String message) async {
    if (declines) {
      throw const SessionException(
        SessionError.refused('declined', code: 'WALLET_SIGN_IN_CANCELLED'),
      );
    }
    signed.add(message);
    return base64Url.encode(List.filled(64, 7));
  }
}

void main() {
  group('the signed message', () {
    test('is Sign-in-with-Solana, line for line as Supabase builds it', () {
      final text = solanaSignInMessage(
        address: _address,
        issuedAt: DateTime.utc(2026, 10, 2, 9, 30),
      );
      expect(
        text,
        'chumbucket.fun wants you to sign in with your Solana account:\n'
        '$_address\n'
        '\n'
        '$kSolanaSignInStatement\n'
        '\n'
        'Version: 1\n'
        'URI: https://chumbucket.fun\n'
        'Issued At: 2026-10-02T09:30:00.000Z',
      );
      expect(kSolanaSignInStatement, isNot(contains('\n')));
    });

    test('only the one signature over exactly this message is used', () {
      final message = Uint8List.fromList(utf8.encode('hello'));
      final key = Uint8List.fromList(List.filled(32, 1));
      final signature = Uint8List.fromList(List.filled(64, 9));
      SignMessagesResult result(Uint8List m, Uint8List k, Uint8List s) =>
          SignMessagesResult(
            signedMessages: [
              SignedMessage(message: m, addresses: [k], signatures: [s]),
            ],
          );
      expect(
        signInSignature(
          result(message, key, signature),
          message: message,
          address: key,
        ),
        base64Url.encode(signature),
      );
      for (final bad in [
        result(Uint8List.fromList(utf8.encode('other')), key, signature),
        result(message, Uint8List.fromList(List.filled(32, 2)), signature),
        result(message, key, Uint8List.fromList(List.filled(63, 9))),
      ]) {
        expect(
          () => signInSignature(bad, message: message, address: key),
          throwsA(isA<SessionException>()),
        );
      }
    });
  });

  group('signing in', () {
    late FakeSupabaseAuthPort auth;
    late ChumbucketSession session;

    ChumbucketSession build(FakeBffServer server) => ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );

    setUp(() => auth = FakeSupabaseAuthPort());
    tearDown(() async {
      session.dispose();
      await auth.close();
    });

    test('a wallet signs one message and lands on its account', () async {
      auth.solanaSession = snapshot();
      session = build(happyBff());
      final wallet = _FakeWallet();
      await session.signInWithWallet(wallet);
      expect(session.isReady, isTrue);
      expect(session.userId, kCanonicalUserId);
      expect(session.isWalletSession, isTrue);
      expect(wallet.signed, hasLength(1));
      expect(auth.solanaSignIns.single.message, wallet.signed.single);
      expect(wallet.signed.single, contains(_address));
      expect(auth.startCount, 0);
    });

    test(
      'a wallet with no account yet is asked for a username, nothing made',
      () async {
        auth.solanaSession = snapshot();
        session = build(refusingBff('AUTH_USER_UNLINKED', 403));
        await session.signInWithWallet(_FakeWallet());
        expect(session.isReady, isFalse);
        expect(session.needsUsername, isTrue);
      },
    );

    test('wallet sign-in switched off in Supabase says so plainly', () async {
      auth.solanaSession = null;
      auth.solanaRefusal = SolanaSignInException.disabled;
      session = build(happyBff());
      await session.signInWithWallet(_FakeWallet());
      expect(session.isReady, isFalse);
      expect(session.error?.code, 'WALLET_SIGN_IN_DISABLED');
      expect(session.error?.message, contains('isn’t switched on yet'));
    });

    test(
      'a declined signature changes nothing and asks nothing of Supabase',
      () async {
        auth.solanaSession = snapshot();
        session = build(happyBff());
        await session.signInWithWallet(_FakeWallet()..declines = true);
        expect(session.isReady, isFalse);
        expect(auth.solanaSignIns, isEmpty);
      },
    );

    test('X uses its own provider and the same resolution as Google', () async {
      auth.deliverOnSignIn = snapshot();
      session = build(happyBff());
      await session.signInWithX();
      expect(auth.lastProvider, 'x');
      expect(session.isReady, isTrue);
      expect(session.isWalletSession, isFalse);
    });
  });

  testWidgets('a taken username blocks the claim and says why', (tester) async {
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final server = FakeBffServer(
      (r) => switch (r.procedurePath) {
        'auth.usernameStatus' => okResponse({
          'handle': 'ada',
          'status': 'taken',
        }),
        _ => errorResponse(
          code: 'FORBIDDEN',
          httpStatus: 403,
          message: 'AUTH_USER_UNLINKED',
        ),
      },
    );
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });
    await session.restore();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: CallSessionPanel()),
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const ValueKey('claim-username')), 'ada');
    await tester.enterText(find.byKey(const ValueKey('claim-name')), 'Ada');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('@ada is taken'), findsOneWidget);
    await tester.tap(find.text('Claim @ada'));
    await tester.pump();
    expect(
      server.received.where((r) => r.procedurePath == 'auth.completeProfile'),
      isEmpty,
    );
  });
}
