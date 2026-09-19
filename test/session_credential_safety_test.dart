/// The credential rule, asserted rather than commented.
///
/// A Supabase access token is a bearer credential: anyone holding it can act as
/// the person until it expires. So it may appear in exactly two places — the
/// `Authorization` header, and the POST body of `auth.whoami`, which is what
/// that procedure takes as its input. Never a URL, never a query string, never
/// a log line, never a `toString`, never a file.
///
/// These tests exist because the deployed `auth.whoami` is declared a tRPC
/// **query**, and reaching a query means a GET, and a GET carries its input in
/// `?input=…`. That is the shape this client refuses to send, and the
/// refusal is only real if something checks it.
library;

import 'package:chumbucket/features/authentication/session/chumbucket_session.dart';
import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

/// Every place a request can carry text, except the two that are allowed.
void expectNoTokenOutsideTheAllowedPlaces(RecordedRequest request) {
  expect(request.url.toString(), isNot(contains(kAccessToken)));
  expect(request.url.query, isNot(contains(kAccessToken)));
  expect(request.url.path, isNot(contains(kAccessToken)));
  expect(request.url.fragment, isNot(contains(kAccessToken)));
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == 'authorization') continue;
    expect(entry.value, isNot(contains(kAccessToken)), reason: entry.key);
  }
}

void main() {
  test('a whole sign-in never puts the token in a URL', () async {
    final server = happyBff();
    final auth = FakeSupabaseAuthPort()..deliverOnSignIn = snapshot();
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });

    await session.signInWithGoogle();
    expect(session.status, SessionStatus.ready);
    expect(server.received, isNotEmpty);

    for (final request in server.received) {
      expectNoTokenOutsideTheAllowedPlaces(request);
    }

    // And it IS present where it is supposed to be, so the assertions above are
    // not passing because nothing was ever sent.
    final whoami = server.requestFor('auth.whoami');
    expect(whoami.headers['authorization'], 'Bearer $kAccessToken');
    expect(whoami.body, contains(kAccessToken));
  });

  test('a token refresh does not leak the new credential into a URL either',
      () async {
    final server = happyBff();
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });

    await session.restore();
    auth.emit(
      SupabaseAuthEventKind.tokenRefreshed,
      snapshot(accessToken: kRefreshedAccessToken),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));

    for (final request in server.received) {
      expect(request.url.toString(), isNot(contains(kAccessToken)));
      expect(request.url.toString(), isNot(contains(kRefreshedAccessToken)));
    }
  });

  test('toString never prints the credential', () async {
    final server = happyBff();
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });

    await session.restore();

    // The session itself — what a debugPrint or an error report would capture.
    expect(session.toString(), isNot(contains(kAccessToken)));
    expect(session.toString(), contains('ready'));
    expect(session.toString(), contains(kCanonicalUserId));

    // The snapshot — what a widget inspector dump would capture.
    final held = snapshot();
    expect(held.toString(), isNot(contains(kAccessToken)));
    expect(held.toString(), contains('redacted'));
    expect(held.toString(), contains(kAuthUserId));

    // The auth event wrapper, which embeds the snapshot.
    final event = SupabaseAuthEvent(SupabaseAuthEventKind.signedIn, held);
    expect(event.toString(), isNot(contains(kAccessToken)));
  });

  test('no error message a person can see carries the credential', () async {
    for (final bff in <FakeBffServer>[
      methodNotSupportedBff(),
      refusingBff(SessionErrorCode.userUnlinked, 403),
      refusingBff(SessionErrorCode.tokenInvalid, 401),
      refusingBff(SessionErrorCode.identityNotConfigured, 412),
      failingBff(),
      happyBff()..simulateTransportFailure = true,
      // A hostile server that echoes the credential back at us.
      FakeBffServer(
        (_) => errorResponse(
          code: 'BAD_REQUEST',
          httpStatus: 400,
          message: 'bad token: $kAccessToken',
          path: 'auth.whoami',
        ),
      ),
    ]) {
      final auth = FakeSupabaseAuthPort(restored: snapshot());
      final session = ChumbucketSession(
        auth: auth,
        bff: SessionBffClient(baseUrl: kSessionBase, httpClient: bff.client),
      );

      await session.restore();

      expect(session.status, SessionStatus.failed);
      final error = session.error!;
      expect(error.message, isNot(contains(kAccessToken)));
      expect(error.toString(), isNot(contains(kAccessToken)));

      session.dispose();
      await auth.close();
    }
  });

  test('the token is never handed out as part of anything but the bearer',
      () async {
    final server = happyBff();
    final auth = FakeSupabaseAuthPort(restored: snapshot());
    final session = ChumbucketSession(
      auth: auth,
      bff: SessionBffClient(baseUrl: kSessionBase, httpClient: server.client),
    );
    addTearDown(() async {
      session.dispose();
      await auth.close();
    });

    await session.restore();

    // The two deliberate exits: the getter the repository reads, and the
    // provider it is handed. Anything else that exposes it is a new leak.
    expect(session.accessToken, kAccessToken);
    expect(await session.bffAuthToken(), kAccessToken);

    // The canonical id is emphatically NOT the credential, and not auth.uid().
    expect(session.userId, kCanonicalUserId);
    expect(session.userId, isNot(contains(kAccessToken)));
    expect(session.userId, isNot(session.authUserId));
  });
}
