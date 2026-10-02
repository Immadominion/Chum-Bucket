/// Injected fakes for the `session_*` suite.
///
/// **No test in this suite opens a socket and none touches Supabase.** The
/// Supabase side is [FakeSupabaseAuthPort], a hand-written stand-in for the
/// five-member `SupabaseAuthPort`; the HTTP side is `FakeBffServer` from
/// `bff_calls_fixtures.dart`, the in-memory `http.Client` the calls suite
/// already uses — reused rather than copied so there is one fake tRPC server in
/// this repository, not two that can drift apart.
library;

import 'dart:async';

import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:http/http.dart' as http;

import 'bff_calls_fixtures.dart';

// ---------------------------------------------------------------------------
// Identities
// ---------------------------------------------------------------------------

/// The canonical `public.users.id`. This is the value `setViewer` takes.
const String kCanonicalUserId = 'usr_8f2c1e6a';

/// The caller's own `auth.uid()`. Deliberately a different shape from
/// [kCanonicalUserId] so a test that confuses the two fails loudly.
const String kAuthUserId = '0d4e3c9b-7a21-4f55-9f10-2b6d8c1a4e77';

/// A realistic-looking JWT. Long, three dot-separated segments, and distinctive
/// enough that a substring search proves it did not leak into a URL or a log.
const String kAccessToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJzdWIiOiIwZDRlM2M5Yi03YTIxLTRmNTUtOWYxMC0yYjZkOGMxYTRlNzciLCJyb2xlIjoi'
    'YXV0aGVudGljYXRlZCIsImV4cCI6MTc4OTIxNDQwMH0.'
    'S1gNaTuRe-cHuMbUcKeT-nEvEr-In-A-uRl';

/// A second token, so a refresh is observably a *different* credential.
const String kRefreshedAccessToken =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
    'eyJzdWIiOiIwZDRlM2M5Yi03YTIxLTRmNTUtOWYxMC0yYjZkOGMxYTRlNzciLCJyb2xlIjoi'
    'YXV0aGVudGljYXRlZCIsImV4cCI6MTc4OTIxODAwMH0.'
    'rEfReSheD-cHuMbUcKeT-nEvEr-In-A-uRl';

/// A session snapshot with a far-future expiry unless told otherwise.
SupabaseSessionSnapshot snapshot({
  String accessToken = kAccessToken,
  String authUserId = kAuthUserId,
  DateTime? expiresAt,
}) => SupabaseSessionSnapshot(
  accessToken: accessToken,
  authUserId: authUserId,
  expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
);

/// A snapshot that is inside its refresh skew right now.
SupabaseSessionSnapshot expiringSnapshot({String accessToken = kAccessToken}) =>
    SupabaseSessionSnapshot(
      accessToken: accessToken,
      authUserId: kAuthUserId,
      expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 5)),
    );

// ---------------------------------------------------------------------------
// Supabase
// ---------------------------------------------------------------------------

/// A scriptable `SupabaseAuthPort`.
///
/// Every branch the session can take is reachable from here: a restored
/// session, a browser that refuses to open, a callback that never comes, a
/// refresh that succeeds, a refresh that fails, a sign-out from elsewhere.
class FakeSupabaseAuthPort implements SupabaseAuthPort {
  FakeSupabaseAuthPort({this.restored});

  /// What `currentSession` reports at launch.
  SupabaseSessionSnapshot? restored;

  /// When set, `startGoogleSignIn` emits this as a `signedIn` event, the way
  /// the `login-callback` deep link would. When null, nothing arrives and the
  /// session's OAuth timeout is what ends the wait.
  SupabaseSessionSnapshot? deliverOnSignIn;

  /// False models a browser that could not be opened at all.
  bool launchSucceeds = true;

  /// Thrown out of `startGoogleSignIn`.
  Object? startThrows;

  /// What `refreshSession` returns. Null models "nothing to refresh".
  SupabaseSessionSnapshot? refreshResult;

  /// Thrown out of `refreshSession`.
  Object? refreshThrows;

  /// Thrown out of `signOut`.
  Object? signOutThrows;

  int startCount = 0;
  int refreshCount = 0;
  int signOutCount = 0;
  String? lastRedirectTo;

  final StreamController<SupabaseAuthEvent> _events =
      StreamController<SupabaseAuthEvent>.broadcast();

  @override
  SupabaseSessionSnapshot? get currentSession => restored;

  @override
  Stream<SupabaseAuthEvent> get authEvents => _events.stream;

  @override
  Future<bool> startGoogleSignIn({
    String redirectTo = kChumbucketOAuthRedirect,
  }) async {
    startCount++;
    lastRedirectTo = redirectTo;
    final boom = startThrows;
    if (boom != null) throw boom;
    if (!launchSucceeds) return false;
    final delivered = deliverOnSignIn;
    if (delivered != null) {
      // The callback never arrives in the same turn as the launch.
      scheduleMicrotask(() => emit(SupabaseAuthEventKind.signedIn, delivered));
    }
    return true;
  }

  /// Which provider the last OAuth start was for ("google" or "x").
  String? lastProvider;

  @override
  Future<bool> startXSignIn({
    String redirectTo = kChumbucketOAuthRedirect,
  }) async {
    lastProvider = 'x';
    return startGoogleSignIn(redirectTo: redirectTo).whenComplete(() {
      lastProvider = 'x';
    });
  }

  /// What a wallet sign-in becomes. Null models Supabase refusing it with
  /// [solanaRefusal].
  SupabaseSessionSnapshot? solanaSession;
  String solanaRefusal = SolanaSignInException.refused;
  final List<({String message, String signature})> solanaSignIns = [];

  @override
  Future<SupabaseSessionSnapshot> signInWithSolana({
    required String message,
    required String signature,
  }) async {
    solanaSignIns.add((message: message, signature: signature));
    final session = solanaSession;
    if (session == null) throw SolanaSignInException(solanaRefusal);
    // The SDK announces the adopted session as a refresh.
    scheduleMicrotask(() => emit(SupabaseAuthEventKind.tokenRefreshed, session));
    return session;
  }

  Set<String> providers = const {'google', 'x'};

  @override
  Future<Set<String>> enabledProviders() async => providers;

  @override
  Future<SupabaseSessionSnapshot?> refreshSession() async {
    refreshCount++;
    final boom = refreshThrows;
    if (boom != null) throw boom;
    return refreshResult;
  }

  @override
  Future<void> signOut() async {
    signOutCount++;
    final boom = signOutThrows;
    if (boom != null) throw boom;
    restored = null;
  }

  /// Push an auth change, as Supabase would.
  void emit(SupabaseAuthEventKind kind, [SupabaseSessionSnapshot? session]) {
    if (_events.isClosed) return;
    _events.add(SupabaseAuthEvent(kind, session));
  }

  Future<void> close() => _events.close();
}

// ---------------------------------------------------------------------------
// BFF
// ---------------------------------------------------------------------------

/// Base URL for every session test. `.invalid` is reserved by RFC 2606, so a
/// test that somehow escaped the fake client would fail to resolve rather than
/// reach a real host.
const String kSessionBase = 'https://bff.test.invalid';

/// `auth.whoami` answers with a canonical user; `auth.identityStatus` answers
/// with a configured deployment.
FakeBffServer happyBff({
  String userId = kCanonicalUserId,
  String authUserId = kAuthUserId,
}) => FakeBffServer((request) {
  switch (request.procedurePath) {
    case 'auth.whoami':
      return okResponse({'userId': userId, 'authUserId': authUserId});
    case 'auth.identityStatus':
      return okResponse({
        'enabled': true,
        'network': 'devnet',
        'proofVersion': 1,
      });
    default:
      return errorResponse(
        code: 'NOT_FOUND',
        httpStatus: 404,
        message: 'No procedure "${request.procedurePath}"',
      );
  }
});

/// What the currently deployed BFF answers to a POST at `auth.whoami`: the
/// procedure is declared `publicProcedure.query(...)`, and tRPC derives the
/// procedure type from the HTTP method.
FakeBffServer methodNotSupportedBff() => FakeBffServer(
  (_) => errorResponse(
    code: 'METHOD_NOT_SUPPORTED',
    httpStatus: 405,
    message: 'Unsupported POST-request to query procedure at path "auth.whoami"',
    path: 'auth.whoami',
  ),
);

/// A BFF that refuses `auth.whoami` with one of the bare identity codes the
/// real server sends as the tRPC error *message*.
FakeBffServer refusingBff(String identityCode, int httpStatus) => FakeBffServer(
  (_) => errorResponse(
    code:
        httpStatus == 401
            ? 'UNAUTHORIZED'
            : httpStatus == 403
            ? 'FORBIDDEN'
            : 'PRECONDITION_FAILED',
    httpStatus: httpStatus,
    message: identityCode,
    path: 'auth.whoami',
  ),
);

/// A BFF that is up but broken.
FakeBffServer failingBff() => FakeBffServer(
  (_) => errorResponse(
    code: 'INTERNAL_SERVER_ERROR',
    httpStatus: 500,
    message: 'boom',
    path: 'auth.whoami',
  ),
);

/// Refuses the first `auth.whoami` and answers the second with a canonical
/// user. Proves the refresh-once-and-retry path, and proves it runs once.
FakeBffServer sequencedWhoamiBff({
  required int firstStatus,
  required String firstMessage,
  String userId = kCanonicalUserId,
  String authUserId = kAuthUserId,
}) {
  var served = 0;
  return FakeBffServer((request) {
    if (request.procedurePath != 'auth.whoami') {
      return errorResponse(code: 'NOT_FOUND', httpStatus: 404);
    }
    served++;
    if (served == 1) {
      return errorResponse(
        code: 'UNAUTHORIZED',
        httpStatus: firstStatus,
        message: firstMessage,
        path: 'auth.whoami',
      );
    }
    return okResponse({'userId': userId, 'authUserId': authUserId});
  });
}

/// A raw response, for the shapes a tRPC envelope helper cannot express — an
/// HTML login wall, a truncated body, an envelope with neither key.
http.Response httpResponseOf(String body, int statusCode) =>
    http.Response(body, statusCode, headers: {'content-type': 'application/json'});
