/// `ChumbucketSession` — the state machine, end to end, with no network and no
/// Supabase.
///
/// The five [SessionStatus] values are each reached here by a separate test, and
/// the transitions between them are asserted on the sequence a listener
/// actually observes rather than only on the final value — a screen that never
/// sees `identityPending` cannot show a spinner, and a screen that never sees
/// `signingIn` cannot disable the button.
library;

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart'
    show CallsBffAuthTokenProvider;
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

/// A session wired to injected fakes, torn down after the test.
class Harness {
  Harness({
    FakeBffServer? bff,
    SupabaseSessionSnapshot? restored,
    Duration oauthTimeout = const Duration(milliseconds: 50),
  }) : server = bff ?? happyBff(),
       auth = FakeSupabaseAuthPort(restored: restored) {
    session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
      oauthTimeout: oauthTimeout,
    );
    session.addListener(() => observed.add(session.status));
  }

  final FakeBffServer server;
  final FakeSupabaseAuthPort auth;
  late final ChumbucketSession session;

  /// Every status a listener saw, in order.
  final List<SessionStatus> observed = <SessionStatus>[];

  int get requestCount => server.received.length;

  Future<void> dispose() async {
    session.dispose();
    await auth.close();
  }
}

/// Lets queued microtasks and the fake's scheduled callback run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  group('signed out — the state a person browses in', () {
    test('a fresh session is signed out and holds no credential', () async {
      final h = Harness();
      addTearDown(h.dispose);

      expect(h.session.status, SessionStatus.signedOut);
      expect(h.session.userId, isNull);
      expect(h.session.accessToken, isNull);
      expect(h.session.isReady, isFalse);
      expect(h.session.error, isNull);
    });

    test('restore with nothing stored stays signed out and asks the BFF '
        'nothing — reading never needs a session', () async {
      final h = Harness();
      addTearDown(h.dispose);

      await h.session.restore();

      expect(h.session.status, SessionStatus.signedOut);
      expect(await h.session.bffAuthToken(), isNull);
      expect(h.requestCount, 0);
    });
  });

  group('signing in', () {
    test('signingIn is observed before the callback comes back', () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.auth.deliverOnSignIn = snapshot();

      final pending = h.session.signInWithGoogle();
      expect(h.session.status, SessionStatus.signingIn);
      expect(h.session.isBusy, isTrue);
      await pending;

      expect(h.observed.first, SessionStatus.signingIn);
      expect(h.auth.startCount, 1);
      expect(h.auth.lastRedirectTo, kChumbucketOAuthRedirect);
    });

    test('a browser that will not open is a refusal, not a hang', () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.auth.launchSucceeds = false;

      await h.session.signInWithGoogle();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.kind, SessionErrorKind.refused);
      expect(h.session.error!.code, SessionErrorCode.oauthCancelled);
      expect(h.requestCount, 0);
    });

    test('a callback that never arrives times out instead of spinning forever',
        () async {
      final h = Harness(oauthTimeout: const Duration(milliseconds: 20));
      addTearDown(h.dispose);
      // deliverOnSignIn stays null: the browser opened and nothing came back.

      await h.session.signInWithGoogle();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.code, SessionErrorCode.oauthCancelled);
    });

    test('a platform error while launching is a network failure, and nothing '
        'from it escapes', () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.auth.startThrows = StateError('redirect=$kAccessToken');

      await h.session.signInWithGoogle();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.kind, SessionErrorKind.network);
      // The thrown object carried a token-looking string. It must not survive.
      expect(h.session.error!.message, isNot(contains(kAccessToken)));
    });

    test('a second sign-in while one is in flight is ignored', () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.auth.deliverOnSignIn = snapshot();

      final first = h.session.signInWithGoogle();
      await h.session.signInWithGoogle();
      await first;

      expect(h.auth.startCount, 1);
    });
  });

  group('signed in, not yet resolved → signed in and resolved', () {
    test('a full sign-in walks signingIn → identityPending → ready', () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.auth.deliverOnSignIn = snapshot();

      await h.session.signInWithGoogle();

      expect(h.observed, [
        SessionStatus.signingIn,
        SessionStatus.identityPending,
        SessionStatus.ready,
      ]);
      expect(h.session.isReady, isTrue);
      expect(h.session.userId, kCanonicalUserId);
      expect(h.session.error, isNull);
    });

    test('restore adopts a stored session and resolves it', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);

      await h.session.restore();

      expect(h.observed, [SessionStatus.identityPending, SessionStatus.ready]);
      expect(h.session.userId, kCanonicalUserId);
      expect(h.session.accessToken, kAccessToken);
    });

    test('identityPending holds a usable bearer but no viewer yet', () async {
      // A BFF that answers slowly, so the pending state is observable.
      final slow = happyBff()
        ..simulateLatency = const Duration(milliseconds: 60);
      final h = Harness(bff: slow, restored: snapshot());
      addTearDown(h.dispose);

      final pending = h.session.restore();
      await settle();

      expect(h.session.status, SessionStatus.identityPending);
      expect(h.session.hasSupabaseSession, isTrue);
      expect(await h.session.bffAuthToken(), kAccessToken);
      // The viewer is NOT known yet — setViewer must not be called with a guess.
      expect(h.session.userId, isNull);
      expect(h.session.isReady, isFalse);

      await pending;
      expect(h.session.status, SessionStatus.ready);
    });

    test('userId is the canonical public.users.id, never auth.uid()', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);

      await h.session.restore();

      expect(h.session.userId, kCanonicalUserId);
      expect(h.session.authUserId, kAuthUserId);
      expect(h.session.userId, isNot(h.session.authUserId));
    });
  });

  group('failed — network versus refused', () {
    test('an unreachable BFF is a network failure and stays retryable',
        () async {
      final dead = happyBff()..simulateTransportFailure = true;
      final h = Harness(bff: dead, restored: snapshot());
      addTearDown(h.dispose);

      await h.session.restore();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.isNetwork, isTrue);
      expect(h.session.userId, isNull);
      // The credential is still held: the session did not evict a good token
      // because a router dropped a packet.
      expect(h.session.hasSupabaseSession, isTrue);

      dead.simulateTransportFailure = false;
      await h.session.retryIdentity();
      expect(h.session.status, SessionStatus.ready);
      expect(h.session.userId, kCanonicalUserId);
      expect(h.session.error, isNull);
    });

    test('an unlinked account is a refusal with its own remedy', () async {
      final h = Harness(
        bff: refusingBff(SessionErrorCode.userUnlinked, 403),
        restored: snapshot(),
      );
      addTearDown(h.dispose);

      await h.session.restore();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.isRefused, isTrue);
      expect(h.session.error!.isUnlinked, isTrue);
    });

    test('the deployed query/mutation mismatch is refused and named', () async {
      final h = Harness(bff: methodNotSupportedBff(), restored: snapshot());
      addTearDown(h.dispose);

      await h.session.restore();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.code, SessionErrorCode.whoamiMethodNotSupported);
      expect(h.session.error!.isRefused, isTrue);
    });

    test('a stale token is refreshed once and retried, and only once',
        () async {
      final server = sequencedWhoamiBff(
        firstStatus: 401,
        firstMessage: SessionErrorCode.tokenInvalid,
      );
      final h = Harness(bff: server, restored: snapshot());
      addTearDown(h.dispose);
      h.auth.refreshResult = snapshot(accessToken: kRefreshedAccessToken);

      await h.session.restore();

      expect(h.session.status, SessionStatus.ready);
      expect(h.session.userId, kCanonicalUserId);
      expect(h.auth.refreshCount, 1);
      expect(h.requestCount, 2);
      // The retry used the NEW credential, not the stale one.
      expect(server.received.last.input, {
        'supabaseAccessToken': kRefreshedAccessToken,
      });
    });

    test('a refresh that cannot help leaves a single honest refusal', () async {
      final server = sequencedWhoamiBff(
        firstStatus: 401,
        firstMessage: SessionErrorCode.tokenInvalid,
      );
      final h = Harness(bff: server, restored: snapshot());
      addTearDown(h.dispose);
      h.auth.refreshResult = null;

      await h.session.restore();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.code, SessionErrorCode.tokenInvalid);
      expect(h.requestCount, 1);
    });

    test('a refresh that throws does not become its own crash', () async {
      final server = sequencedWhoamiBff(
        firstStatus: 401,
        firstMessage: SessionErrorCode.tokenInvalid,
      );
      final h = Harness(bff: server, restored: snapshot());
      addTearDown(h.dispose);
      h.auth.refreshThrows = StateError('refresh_token=$kAccessToken');

      await h.session.restore();

      expect(h.session.status, SessionStatus.failed);
      expect(h.session.error!.message, isNot(contains(kAccessToken)));
    });

    test('a refusal is not retried behind the user back', () async {
      final h = Harness(
        bff: refusingBff(SessionErrorCode.userUnlinked, 403),
        restored: snapshot(),
      );
      addTearDown(h.dispose);
      h.auth.refreshResult = snapshot(accessToken: kRefreshedAccessToken);

      await h.session.restore();

      expect(h.requestCount, 1);
      expect(h.auth.refreshCount, 0);
    });
  });

  group('signing out', () {
    test('clears the viewer and the credential', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();
      expect(h.session.isReady, isTrue);

      h.observed.clear();
      await h.session.signOut();

      expect(h.observed, [SessionStatus.signedOut]);
      expect(h.session.userId, isNull);
      expect(h.session.accessToken, isNull);
      expect(h.session.hasSupabaseSession, isFalse);
      expect(await h.session.bffAuthToken(), isNull);
      expect(h.auth.signOutCount, 1);
    });

    test('a provider that fails still signs the person out locally', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();
      h.auth.signOutThrows = StateError('network down');

      await h.session.signOut();

      expect(h.session.status, SessionStatus.signedOut);
      expect(h.session.userId, isNull);
    });

    test('a sign-out from elsewhere is adopted', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();

      h.auth.emit(SupabaseAuthEventKind.signedOut);
      await settle();

      expect(h.session.status, SessionStatus.signedOut);
      expect(h.session.userId, isNull);
    });
  });

  group('the auth stream, after sign-in', () {
    test('a token refresh keeps the viewer and swaps the bearer', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();
      final requestsBefore = h.requestCount;

      h.auth.emit(
        SupabaseAuthEventKind.tokenRefreshed,
        snapshot(accessToken: kRefreshedAccessToken),
      );
      await settle();

      expect(h.session.status, SessionStatus.ready);
      expect(h.session.userId, kCanonicalUserId);
      expect(h.session.accessToken, kRefreshedAccessToken);
      // The same person does not need resolving again.
      expect(h.requestCount, requestsBefore);
    });

    test('a different person is resolved again rather than inherited',
        () async {
      final server = FakeBffServer((request) {
        final token = request.input['supabaseAccessToken'];
        return okResponse({
          'userId': token == kAccessToken ? kCanonicalUserId : 'usr_someone_else',
          'authUserId': kAuthUserId,
        });
      });
      final h = Harness(bff: server, restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();
      expect(h.session.userId, kCanonicalUserId);

      h.auth.emit(
        SupabaseAuthEventKind.signedIn,
        snapshot(
          accessToken: kRefreshedAccessToken,
          authUserId: 'a-different-auth-uid',
        ),
      );
      await settle();

      expect(h.session.userId, 'usr_someone_else');
      expect(h.requestCount, 2);
    });

    test('an initialSession delivered by the stream is adopted', () async {
      final h = Harness();
      addTearDown(h.dispose);
      await h.session.restore();
      expect(h.session.status, SessionStatus.signedOut);

      h.auth.emit(SupabaseAuthEventKind.initialSession, snapshot());
      await settle();

      expect(h.session.status, SessionStatus.ready);
      expect(h.session.userId, kCanonicalUserId);
    });

    test('an event this session does not model changes nothing', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();
      h.observed.clear();

      h.auth.emit(SupabaseAuthEventKind.other, snapshot());
      await settle();

      expect(h.observed, isEmpty);
      expect(h.session.status, SessionStatus.ready);
    });
  });

  group('bffAuthToken — what the calls repository is handed', () {
    test('is null when signed out, which is not an error', () async {
      final h = Harness();
      addTearDown(h.dispose);
      expect(await h.session.bffAuthToken(), isNull);
    });

    test('returns the held token while it is fresh', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();

      expect(await h.session.bffAuthToken(), kAccessToken);
      expect(h.auth.refreshCount, 0);
    });

    test('refreshes before expiry rather than letting a write 401', () async {
      final h = Harness(restored: expiringSnapshot());
      addTearDown(h.dispose);
      await h.session.restore();
      h.auth.refreshResult = snapshot(accessToken: kRefreshedAccessToken);

      expect(await h.session.bffAuthToken(), kRefreshedAccessToken);
      expect(h.auth.refreshCount, 1);
      expect(h.session.accessToken, kRefreshedAccessToken);
    });

    test('falls back to the held token when the refresh fails — the server is '
        'the authority, not a local guess', () async {
      final h = Harness(restored: expiringSnapshot());
      addTearDown(h.dispose);
      await h.session.restore();
      h.auth.refreshResult = null;

      expect(await h.session.bffAuthToken(), kAccessToken);
    });

    test('matches CallsBffAuthTokenProvider', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);
      await h.session.restore();

      // The tear-off is what `buildCallsRepository(authToken:)` is given.
      final CallsBffAuthTokenProvider provider = h.session.bffAuthToken;
      expect(await provider(), kAccessToken);
    });
  });

  group('lifecycle', () {
    test('disposing stops the session reacting to a late auth event', () async {
      final h = Harness(restored: snapshot());
      await h.session.restore();
      h.session.dispose();

      // Would throw "used after being disposed" if the listener still notified.
      h.auth.emit(SupabaseAuthEventKind.signedOut);
      await settle();

      await h.auth.close();
    });

    test('restore is safe to call twice', () async {
      final h = Harness(restored: snapshot());
      addTearDown(h.dispose);

      await h.session.restore();
      await h.session.restore();

      expect(h.session.status, SessionStatus.ready);
      expect(h.requestCount, 2);
    });
  });

  group('identityStatus', () {
    test('reports a configured deployment without sending a credential',
        () async {
      final h = Harness();
      addTearDown(h.dispose);

      final status = await h.session.checkIdentityStatus();

      expect(status!.enabled, isTrue);
      expect(h.server.lastRequest.headers.containsKey('authorization'), isFalse);
    });

    test('an unreachable BFF is null, never a false "configured"', () async {
      final dead = happyBff()..simulateTransportFailure = true;
      final h = Harness(bff: dead);
      addTearDown(h.dispose);

      expect(await h.session.checkIdentityStatus(), isNull);
    });
  });
}
