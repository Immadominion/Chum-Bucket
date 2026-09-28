import 'dart:async';

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_fakes.dart';

class HeldIdentityClient extends SessionBffClient {
  HeldIdentityClient() : super(baseUrl: kSessionBase);
  final requests = <String, Completer<SessionIdentity>>{};
  @override
  Future<SessionIdentity> whoami(String accessToken) =>
      (requests[accessToken] = Completer<SessionIdentity>()).future;
}

class HeldSignOut extends FakeSupabaseAuthPort {
  HeldSignOut() : super(restored: snapshot());
  final finished = Completer<void>();
  @override
  Future<void> signOut() => finished.future;
}

const personA = SessionIdentity(userId: 'person-a', authUserId: kAuthUserId);
const personB = SessionIdentity(userId: 'person-b', authUserId: 'auth-b');
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  test('explicit Google sign-in works after an earlier sign-out', () async {
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: happyBff().client,
      ),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });
    await session.restore();
    await session.signOut();
    auth.deliverOnSignIn = snapshot();
    await session.signInWithGoogle();
    expect(session.isReady, isTrue);
    expect(session.userId, kCanonicalUserId);
  });

  test('local identity clears before a slow sign-out finishes', () async {
    final auth = HeldSignOut();
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: happyBff().client,
      ),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });
    await session.restore();
    final signingOut = session.signOut();
    final visibleDuringSignOut = session.userId;
    final hasBearerDuringSignOut = (await session.bffAuthToken()) != null;
    auth.finished.complete();
    await signingOut;
    expect(visibleDuringSignOut, isNull);
    expect(hasBearerDuringSignOut, isFalse);
  });

  test('late OAuth event cannot undo an explicit sign-out', () async {
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(
        baseUrl: kSessionBase,
        httpClient: happyBff().client,
      ),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });
    await session.restore();
    await session.signOut();
    auth.emit(SupabaseAuthEventKind.signedIn, snapshot());
    await tick();
    expect(session.status, SessionStatus.signedOut);
    expect(session.userId, isNull);
  });

  test(
    'account B resolves without waiting for a held account A lookup',
    () async {
      final auth = FakeSupabaseAuthPort(restored: snapshot());
      final bff = HeldIdentityClient();
      final session = ChumbucketSession(auth: auth, bff: bff);
      addTearDown(() async {
        session.dispose();
        bff.close();
        await auth.close();
      });
      final restoring = session.restore();
      auth.emit(
        SupabaseAuthEventKind.signedIn,
        snapshot(accessToken: 'token-b', authUserId: 'auth-b'),
      );
      await tick();
      final requestedB = bff.requests['token-b'];
      requestedB?.complete(personB);
      await tick();
      bff.requests[kAccessToken]!.complete(personA);
      await restoring;
      expect(requestedB, isNotNull);
      expect(session.userId, 'person-b');
    },
  );

  test(
    'whoami cannot assign a response belonging to another auth subject',
    () async {
      final auth = FakeSupabaseAuthPort(restored: snapshot());
      final session = ChumbucketSession(
        auth: auth,
        bff: SessionBffClient(
          baseUrl: kSessionBase,
          httpClient: happyBff(authUserId: 'other-auth').client,
        ),
      );
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      await session.restore();
      expect(session.isReady, isFalse);
      expect(session.userId, isNull);
      expect(session.error?.code, SessionErrorCode.unreadable);
    },
  );

  test(
    'cancelled OAuth wait cannot replace signed-out state with an error',
    () async {
      final auth = FakeSupabaseAuthPort();
      final session = ChumbucketSession(
        auth: auth,
        oauthTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(() async {
        session.dispose();
        await auth.close();
      });
      final signingIn = session.signInWithGoogle();
      await tick();
      await session.signOut();
      await signingIn;
      expect(session.status, SessionStatus.signedOut);
      expect(session.error, isNull);
    },
  );
}
