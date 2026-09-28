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
    'unlinked Google account cannot accidentally create a second profile',
    (tester) async {
      final auth = FakeSupabaseAuthPort(restored: snapshot());
      final server = FakeBffServer(
        (r) =>
            r.procedurePath == 'auth.completeProfile'
                ? okResponse({
                  'userId': kCanonicalUserId,
                  'authUserId': kAuthUserId,
                })
                : errorResponse(
                  code: 'FORBIDDEN',
                  httpStatus: 403,
                  message: 'AUTH_USER_UNLINKED',
                ),
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
      expect(
        find.textContaining('Account linking is not available'),
        findsOneWidget,
      );
      expect(find.text('Public name'), findsNothing);
      expect(find.text('Create my profile'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Retry account setup'), findsNothing);
      expect(server.received, hasLength(1));
      expect(server.received.single.procedurePath, 'auth.whoami');
      expect(session.isReady, isFalse);
      expect(session.userId, isNull);
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
