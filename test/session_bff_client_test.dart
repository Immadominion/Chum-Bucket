/// `SessionBffClient` — the identity half of the tRPC surface.
///
/// Two things are under test here. The obvious one is that every server answer
/// maps to exactly one [SessionError]. The load-bearing one is the credential
/// rule: **the access token must never appear in a URL.** That is asserted
/// directly against the recorded request, not inferred from the code.
library;

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';
import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'bff_calls_fixtures.dart';
import 'session_fakes.dart';

SessionBffClient build(
  FakeBffServer server, {
  String baseUrl = kSessionBase,
  Duration timeout = const Duration(seconds: 15),
}) => SessionBffClient(
  baseUrl: baseUrl,
  httpClient: server.client,
  timeout: timeout,
);

/// The [SessionError] a call failed with.
Future<SessionError> errorFrom(Future<Object?> Function() call) async {
  try {
    await call();
  } on SessionException catch (e) {
    return e.error;
  }
  fail('expected a SessionException');
}

void main() {
  group('auth.whoami — the wire', () {
    test('POSTs the token in the body, never in the URL', () async {
      final server = happyBff();
      await build(server).whoami(kAccessToken);

      final request = server.lastRequest;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$kSessionBase/auth.whoami');

      // The three ways a credential leaks into a URL, all closed.
      expect(request.url.query, isEmpty);
      expect(request.url.queryParameters, isEmpty);
      expect(request.url.toString(), isNot(contains(kAccessToken)));

      // And it is where it belongs.
      expect(request.input, {'supabaseAccessToken': kAccessToken});
      expect(request.headers['authorization'], 'Bearer $kAccessToken');
    });

    test('resolves the canonical user id and the caller own auth uid', () async {
      final identity = await build(happyBff()).whoami(kAccessToken);
      expect(identity.userId, kCanonicalUserId);
      expect(identity.authUserId, kAuthUserId);
      // The two are never interchangeable: only userId may reach setViewer.
      expect(identity.userId, isNot(identity.authUserId));
    });

    test('tolerates a response that was not superjson-wrapped', () async {
      final server = FakeBffServer(
        (_) => okResponseUnwrapped({
          'userId': kCanonicalUserId,
          'authUserId': kAuthUserId,
        }),
      );
      expect((await build(server).whoami(kAccessToken)).userId, kCanonicalUserId);
    });

    test('a trailing slash on the base URL does not double up', () async {
      final server = happyBff();
      await build(server, baseUrl: '$kSessionBase/').whoami(kAccessToken);
      expect(server.lastRequest.url.toString(), '$kSessionBase/auth.whoami');
    });

    test('an answer with no userId is not a silent null viewer', () async {
      final server = FakeBffServer((_) => okResponse({'authUserId': kAuthUserId}));
      final error = await errorFrom(() => build(server).whoami(kAccessToken));
      expect(error.kind, SessionErrorKind.network);
      expect(error.code, SessionErrorCode.unreadable);
    });
  });

  group('auth.whoami — refusals', () {
    test('405 is the deployed query/mutation mismatch, not the person', () async {
      final error = await errorFrom(
        () => build(methodNotSupportedBff()).whoami(kAccessToken),
      );
      expect(error.kind, SessionErrorKind.refused);
      expect(error.code, SessionErrorCode.whoamiMethodNotSupported);
      expect(error.isUnlinked, isFalse);
      expect(error.message, contains('Nothing is wrong with your account'));
    });

    test('AUTH_USER_UNLINKED is its own answer', () async {
      final error = await errorFrom(
        () => build(refusingBff(SessionErrorCode.userUnlinked, 403))
            .whoami(kAccessToken),
      );
      expect(error.kind, SessionErrorKind.refused);
      expect(error.code, SessionErrorCode.userUnlinked);
      expect(error.isUnlinked, isTrue);
    });

    test('IDENTITY_NOT_CONFIGURED is a deployment problem', () async {
      final error = await errorFrom(
        () => build(refusingBff(SessionErrorCode.identityNotConfigured, 412))
            .whoami(kAccessToken),
      );
      expect(error.kind, SessionErrorKind.refused);
      expect(error.code, SessionErrorCode.identityNotConfigured);
    });

    test('AUTH_TOKEN_INVALID asks for a fresh sign-in', () async {
      final error = await errorFrom(
        () => build(refusingBff(SessionErrorCode.tokenInvalid, 401))
            .whoami(kAccessToken),
      );
      expect(error.kind, SessionErrorKind.refused);
      expect(error.code, SessionErrorCode.tokenInvalid);
    });

    test('AUTH_TOKEN_MISSING collapses onto the same remedy', () async {
      final error = await errorFrom(
        () => build(refusingBff(SessionErrorCode.tokenMissing, 401))
            .whoami(kAccessToken),
      );
      expect(error.code, SessionErrorCode.tokenInvalid);
    });

    test('a bare 401 with an unreadable body is still a credential problem',
        () async {
      final server = FakeBffServer(
        (_) => httpResponseOf('<html>login</html>', 401),
      );
      final error = await errorFrom(() => build(server).whoami(kAccessToken));
      expect(error.kind, SessionErrorKind.refused);
      expect(error.code, SessionErrorCode.tokenInvalid);
    });
  });

  group('auth.whoami — the network', () {
    test('a 500 is network, not refused: nothing was decided about you',
        () async {
      final error = await errorFrom(() => build(failingBff()).whoami(kAccessToken));
      expect(error.kind, SessionErrorKind.network);
    });

    test('AUTH_USER_AMBIGUOUS is our bug, so it is retryable', () async {
      final error = await errorFrom(
        () => build(refusingBff(SessionErrorCode.userAmbiguous, 500))
            .whoami(kAccessToken),
      );
      expect(error.kind, SessionErrorKind.network);
      expect(error.code, SessionErrorCode.userAmbiguous);
    });

    test('a dead socket is network', () async {
      final server = happyBff()..simulateTransportFailure = true;
      final error = await errorFrom(() => build(server).whoami(kAccessToken));
      expect(error.kind, SessionErrorKind.network);
      expect(error.code, SessionErrorCode.unreachable);
    });

    test('a round trip that never finishes is network', () async {
      final server = happyBff()
        ..simulateLatency = const Duration(milliseconds: 80);
      final error = await errorFrom(
        () => build(server, timeout: const Duration(milliseconds: 10))
            .whoami(kAccessToken),
      );
      expect(error.kind, SessionErrorKind.network);
      expect(error.code, SessionErrorCode.unreachable);
    });

    test('a body we cannot read on a 200 is network', () async {
      final server = FakeBffServer((_) => httpResponseOf('not json', 200));
      final error = await errorFrom(() => build(server).whoami(kAccessToken));
      expect(error.kind, SessionErrorKind.network);
      expect(error.code, SessionErrorCode.unreadable);
    });

    test('an envelope with neither result nor error is network', () async {
      final server = FakeBffServer((_) => httpResponseOf('{"ok":true}', 200));
      final error = await errorFrom(() => build(server).whoami(kAccessToken));
      expect(error.kind, SessionErrorKind.network);
    });
  });

  group('auth.identityStatus', () {
    test('is a GET with no input and no credential at all', () async {
      final server = happyBff();
      final status = await build(server).identityStatus();

      final request = server.lastRequest;
      expect(request.method, 'GET');
      expect(request.url.toString(), '$kSessionBase/auth.identityStatus');
      expect(request.url.query, isEmpty);
      expect(request.headers.containsKey('authorization'), isFalse);

      expect(status.enabled, isTrue);
      expect(status.network, 'devnet');
      expect(status.proofVersion, 1);
    });

    test('an unreachable BFF raises rather than reporting "configured"',
        () async {
      final server = happyBff()..simulateTransportFailure = true;
      final error = await errorFrom(() => build(server).identityStatus());
      expect(error.kind, SessionErrorKind.network);
    });
  });
}
