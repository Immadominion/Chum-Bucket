import 'dart:async';

import 'package:chumbucket/features/authentication/presentation/widgets/call_sign_in.dart';
import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

class DelayedProfileClient extends SessionBffClient {
  DelayedProfileClient() : super(baseUrl: kSessionBase);
  final pending = Completer<SessionIdentity>();
  @override
  Future<SessionIdentity> whoami(String token) async =>
      throw const SessionException(
        SessionError.refused(
          'Choose a profile',
          code: SessionErrorCode.userUnlinked,
        ),
      );
  @override
  Future<SessionIdentity> completeProfile(
    String accessToken, {
    required String displayName,
    String? handle,
  }) => pending.future;
}

void main() {
  test(
    'profile request is POST-only; token stays out of URL and no identity hint is sent',
    () async {
      final route = FakeBffServer.replying({
        'userId': kCanonicalUserId,
        'authUserId': kAuthUserId,
      });
      final bff = SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: route.client,
      );
      final result = await bff.completeProfile(
        kAccessToken,
        displayName: ' Test Caller ',
      );
      expect(result.userId, kCanonicalUserId);
      final request = route.received.single;
      expect(request.procedurePath, 'auth.completeProfile');
      expect(request.method, 'POST');
      expect(request.url.hasQuery, isFalse);
      expect(request.url.toString(), isNot(contains(kAccessToken)));
      expect(request.headers['authorization'], 'Bearer $kAccessToken');
      expect(request.input, {
        'supabaseAccessToken': kAccessToken,
        'displayName': 'Test Caller',
      });
      bff.close();
    },
  );

  testWidgets(
    'an unlinked sign-in creates nothing until a username is explicitly claimed',
    (tester) async {
      final auth = FakeSupabaseAuthPort(restored: snapshot());
      final server = FakeBffServer(
        (r) => switch (r.procedurePath) {
          'auth.completeProfile' => okResponse({
            'userId': kCanonicalUserId,
            'authUserId': kAuthUserId,
          }),
          'auth.usernameStatus' => okResponse({
            'handle': 'ada_99',
            'status': 'available',
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
      await tester.pump();
      // Signing in made nothing: only "who am I" was asked.
      expect(session.needsUsername, isTrue);
      expect(server.received.map((r) => r.procedurePath), ['auth.whoami']);
      expect(find.byKey(const ValueKey('claim-username')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('claim-username')),
        'Ada_99',
      );
      await tester.enterText(find.byKey(const ValueKey('claim-name')), 'Ada');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('@ada_99 is yours to claim'), findsOneWidget);
      expect(
        server.received.where((r) => r.procedurePath == 'auth.completeProfile'),
        isEmpty,
      );

      await tester.tap(find.text('Claim @ada_99'));
      await tester.pump();
      await tester.pump();
      final claim = server.received.singleWhere(
        (r) => r.procedurePath == 'auth.completeProfile',
      );
      expect(claim.method, 'POST');
      // The username and name only: no user id, wallet or identity hint.
      expect(claim.input.keys.toSet(), {
        'supabaseAccessToken',
        'displayName',
        'handle',
      });
      expect(claim.input['handle'], 'ada_99');
      expect(session.isReady, isTrue);
      expect(session.userId, kCanonicalUserId);
      expect(auth.startCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test('server refusal stays failed, never invents a local profile', () async {
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: refusingBff('AUTH_USER_UNLINKED', 403).client,
      ),
    );
    await session.restore();
    await session.completeProfile('Caller');
    expect(session.isReady, isFalse);
    expect(session.userId, isNull);
    expect(session.hasSupabaseSession, isTrue);
    session.dispose();
    await auth.close();
  });

  test(
    'sign-out during profile creation cannot restore the previous identity',
    () async {
      final auth = FakeSupabaseAuthPort(restored: snapshot());
      final client = DelayedProfileClient();
      final session = ChumbucketSession(auth: auth, bff: client);
      await session.restore();
      final creating = session.completeProfile('Caller');
      await Future<void>.delayed(Duration.zero);
      await session.signOut();
      client.pending.complete(
        const SessionIdentity(
          userId: kCanonicalUserId,
          authUserId: kAuthUserId,
        ),
      );
      await creating;
      expect(session.status, SessionStatus.signedOut);
      expect(session.userId, isNull);
      session.dispose();
      client.close();
      await auth.close();
    },
  );
}
