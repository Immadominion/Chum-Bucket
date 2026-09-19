/// The session's tRPC client: `auth.whoami` and `auth.identityStatus`.
///
/// This is a deliberate **copy** of the envelope handling in
/// `lib/features/calls/data/calls_bff_transport.dart` (itself a copy of
/// `arena_backend_service.dart`'s `_postMutation` / `_decodeTrpcResponse`). A
/// query is `GET $base/$path`, a mutation is `POST $base/$path` with body
/// `{"json": …}`, both unwrap `result.data.json`, both raise on the
/// `{"error":{"json":{…}}}` envelope, and both fall back to the raw `data` when
/// the response was not superjson-wrapped.
///
/// It is a copy rather than a reuse of `CallsBffTransport` for one concrete
/// reason: `CallsBffTransport` collapses every `UNAUTHORIZED` into a single
/// const `CallsSignedOutException` and throws away the tRPC error code. The
/// identity surface answers with *bare codes* as the message
/// (`AUTH_USER_UNLINKED`, `IDENTITY_NOT_CONFIGURED`, `AUTH_TOKEN_INVALID`), and
/// those three need three different sentences on screen. So this client keeps
/// `(code, httpStatus, message)` and maps them itself. What it does **not**
/// copy is the host configuration — `resolveCallsBffBaseUrl()` is imported, so
/// there is exactly one place in the app that decides which BFF we talk to.
///
/// `arena_backend_service.dart` is not imported, per the packet brief.
///
/// ## The credential rule, and the one place it bites
///
/// The access token is a credential: **bearer header and request body only.**
/// Never a URL, never a query string, never a log line, never a file.
///
/// `auth.whoami` takes the token as a procedure *input*
/// (`{ supabaseAccessToken: string }`) because the BFF's tRPC `Context` does
/// not carry it yet. On the deployed server that procedure is declared
/// `publicProcedure.query(...)` (`src/api/authRoutes.ts:124`), and tRPC derives
/// the procedure type from the HTTP method — so reaching a *query* means a GET,
/// and a GET carries its input in `?input=…`. That would put a JWT in a URL,
/// into every proxy and access log between here and Railway.
///
/// This client will not do that. It POSTs the token in the body and sends it
/// again as `Authorization: Bearer`, which is the shape the procedure will have
/// the moment it is declared a `.mutation` (or the moment `Context` carries the
/// bearer). Until one of those lands, the deployed server answers 405
/// `METHOD_NOT_SUPPORTED`, and that is surfaced honestly as
/// [SessionErrorCode.whoamiMethodNotSupported] rather than quietly downgraded
/// into a leaking GET. Both one-line server patches are filed in
/// `docs/contracts/integration-requests/packet-session.md`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:chumbucket/features/authentication/session/session_state.dart';
import 'package:chumbucket/features/calls/data/calls_bff_transport.dart'
    show normalizeCallsBffBaseUrl, resolveCallsBffBaseUrl;

/// `auth.whoami` — Supabase session → canonical `public.users.id`.
const String kWhoamiProcedure = 'auth.whoami';

/// `auth.identityStatus` — public, no input, no credential.
const String kIdentityStatusProcedure = 'auth.identityStatus';

/// The one exception this client throws. It carries a [SessionError] so the
/// session never has to classify anything twice.
class SessionException implements Exception {
  const SessionException(this.error);

  final SessionError error;

  String get message => error.message;

  @override
  String toString() => 'SessionException: $error';
}

/// Talks to the identity surface of the calls BFF. Knows nothing about
/// ChangeNotifier, Supabase, or the widget tree.
class SessionBffClient {
  SessionBffClient({
    String? baseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  }) : baseUrl = normalizeCallsBffBaseUrl(baseUrl ?? resolveCallsBffBaseUrl()),
       _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _timeout = timeout;

  /// Never a hardcoded host — resolved exactly as the calls slice resolves it.
  final String baseUrl;

  final http.Client _client;
  final bool _ownsClient;
  final Duration _timeout;

  /// Resolve a Supabase access token to exactly one canonical user.
  ///
  /// The token travels in the POST body and in `Authorization: Bearer`, and
  /// nowhere else. Throws [SessionException] for every failure; nothing else
  /// escapes.
  Future<SessionIdentity> whoami(String accessToken) async {
    final data = await _send(
      kWhoamiProcedure,
      method: 'POST',
      input: {'supabaseAccessToken': accessToken},
      bearer: accessToken,
    );
    final map = data is Map ? data : const {};
    final userId = map['userId'];
    final authUserId = map['authUserId'];
    if (userId is! String || userId.isEmpty) {
      throw const SessionException(
        SessionError.network(
          'The server did not say who you are.',
          code: SessionErrorCode.unreadable,
        ),
      );
    }
    return SessionIdentity(
      userId: userId,
      // Absent rather than wrong is survivable: the canonical id is the one
      // that matters, and authUserId is only ever used for diagnostics.
      authUserId: authUserId is String ? authUserId : '',
    );
  }

  /// Whether identity is configured on this deployment at all.
  ///
  /// A query with no input and no credential, so it is a plain GET with no
  /// query string — the only shape of request in this file that is not a POST.
  /// Useful for telling "identity is switched off for this build" apart from
  /// "your account is not linked", and for proving the transport reaches the
  /// BFF without presenting a token.
  Future<SessionIdentityStatus> identityStatus() async {
    final data = await _send(kIdentityStatusProcedure, method: 'GET');
    final map = data is Map ? data : const {};
    return SessionIdentityStatus(
      enabled: map['enabled'] == true,
      network: map['network'] is String ? map['network'] as String : 'unknown',
      proofVersion: (map['proofVersion'] as num?)?.toInt() ?? 0,
    );
  }

  /// Closes the client, but only if this object created it. A caller that
  /// injected its own keeps ownership.
  void close() {
    if (_ownsClient) _client.close();
  }

  // -------------------------------------------------------------------------
  // Wire
  // -------------------------------------------------------------------------

  Future<Object?> _send(
    String procedurePath, {
    required String method,
    Map<String, dynamic>? input,
    String? bearer,
  }) async {
    final uri = Uri.parse('$baseUrl/$procedurePath');
    final headers = <String, String>{'content-type': 'application/json'};
    if (bearer != null && bearer.isNotEmpty) {
      headers['authorization'] = 'Bearer $bearer';
    }

    final http.Response response;
    try {
      response =
          await (method == 'GET'
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                    uri,
                    headers: headers,
                    body: jsonEncode({'json': input ?? const {}}),
                  ))
              .timeout(_timeout);
    } on SessionException {
      rethrow;
    } on TimeoutException {
      throw const SessionException(SessionError.network(_unreachable));
    } on http.ClientException {
      // `IOClient` folds SocketException/HandshakeException into this, so DNS
      // failure, a refused connection and a dropped socket all land here.
      throw const SessionException(SessionError.network(_unreachable));
    } catch (_) {
      // Deliberately swallowed: the object thrown by a transport can hold the
      // request — URL, headers, body — and this one carries a credential.
      // Nothing from it is logged or re-thrown.
      throw const SessionException(SessionError.network(_unreachable));
    }

    return _decode(response, procedurePath: procedurePath);
  }

  static const String _unreachable =
      "We couldn't reach the server. Check your connection and try again.";

  Object? _decode(http.Response response, {required String procedurePath}) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('envelope is not a JSON object');
      }
      body = decoded;
    } catch (_) {
      // Bytes arrived, so this is not a network failure. A 401 with an
      // unreadable body (a proxy, a login wall) is still a credential problem.
      if (response.statusCode == 401) {
        throw const SessionException(
          SessionError.refused(
            'That sign-in was not accepted. Sign in again.',
            code: SessionErrorCode.tokenInvalid,
          ),
        );
      }
      throw const SessionException(
        SessionError.network(
          'The server sent something we could not read.',
          code: SessionErrorCode.unreadable,
        ),
      );
    }

    if (body.containsKey('error')) {
      final error = body['error'];
      final errorMap = error is Map<String, dynamic> ? error : null;
      final inner = errorMap?['json'];
      final innerMap = inner is Map<String, dynamic> ? inner : null;
      final dataRaw = (innerMap ?? errorMap)?['data'];
      final data = dataRaw is Map<String, dynamic> ? dataRaw : null;

      final message =
          (innerMap?['message'] ?? errorMap?['message']) as String? ??
          data?['message'] as String?;
      throw SessionException(
        sessionErrorForTrpcError(
          statusCode: response.statusCode,
          trpcCode: data?['code'] as String?,
          httpStatus: (data?['httpStatus'] as num?)?.toInt(),
          message: message,
        ),
      );
    }

    if (response.statusCode != 200) {
      throw SessionException(
        sessionErrorForTrpcError(
          statusCode: response.statusCode,
          message: 'The server returned ${response.statusCode}.',
        ),
      );
    }

    if (!body.containsKey('result')) {
      throw const SessionException(
        SessionError.network(
          'The server sent an empty envelope.',
          code: SessionErrorCode.unreadable,
        ),
      );
    }

    final result = body['result'];
    final data = result is Map<String, dynamic> ? result['data'] : null;
    if (data is Map<String, dynamic> && data.containsKey('json')) {
      return data['json'];
    }
    // Not superjson-wrapped — fall back to the raw data, as the arena and
    // calls transports both do.
    return data;
  }
}

/// Maps a tRPC error envelope onto a [SessionError].
///
/// The identity routes set the TRPCError `message` to the bare
/// `AuthIdentityErrorCode` (`src/api/authRoutes.ts`), so the *message* is the
/// machine-readable part and the tRPC `code` is only the transport status. Both
/// are used: the message picks the sentence, the code picks the class.
///
/// | situation | kind | code |
/// | --- | --- | --- |
/// | 405 on `auth.whoami` | refused | [SessionErrorCode.whoamiMethodNotSupported] |
/// | `AUTH_USER_UNLINKED` (403) | refused | [SessionErrorCode.userUnlinked] |
/// | `IDENTITY_NOT_CONFIGURED` (412) | refused | [SessionErrorCode.identityNotConfigured] |
/// | `AUTH_TOKEN_MISSING`/`INVALID` (401) | refused | [SessionErrorCode.tokenInvalid] |
/// | any other 4xx | refused | the tRPC code |
/// | 5xx, or unreadable | network | [SessionErrorCode.unreadable] |
///
/// A 5xx is **network**, not refused: the server did not decide anything about
/// this person, so "try again" is the honest advice. A 4xx is refused: the
/// server answered and said no, and retrying the same request will fail the
/// same way.
SessionError sessionErrorForTrpcError({
  required int statusCode,
  String? trpcCode,
  int? httpStatus,
  String? message,
}) {
  final status = httpStatus ?? statusCode;
  final detail = (message ?? '').trim();

  if (trpcCode == 'METHOD_NOT_SUPPORTED' || status == 405) {
    return const SessionError.refused(
      'This build of the server cannot finish signing you in yet. '
      'Nothing is wrong with your account.',
      code: SessionErrorCode.whoamiMethodNotSupported,
    );
  }

  switch (detail) {
    case SessionErrorCode.userUnlinked:
      return const SessionError.refused(
        "You're signed in, but this account isn't set up yet. "
        'Finish setting it up to make a call.',
        code: SessionErrorCode.userUnlinked,
      );
    case SessionErrorCode.identityNotConfigured:
      return const SessionError.refused(
        'Sign-in is not switched on for this build yet.',
        code: SessionErrorCode.identityNotConfigured,
      );
    case SessionErrorCode.userAmbiguous:
      return const SessionError.network(
        'Something is wrong with this account on our side. Try again shortly.',
        code: SessionErrorCode.userAmbiguous,
      );
    case SessionErrorCode.tokenMissing:
    case SessionErrorCode.tokenInvalid:
      return const SessionError.refused(
        'That sign-in was not accepted. Sign in again.',
        code: SessionErrorCode.tokenInvalid,
      );
  }

  if (status == 401 || status == 403) {
    return const SessionError.refused(
      'That sign-in was not accepted. Sign in again.',
      code: SessionErrorCode.tokenInvalid,
    );
  }
  if (status >= 400 && status < 500) {
    // The server's own prose is deliberately NOT forwarded. The identity
    // surface answers with bare codes, which are mapped above; anything else
    // reaching here came from a proxy, a gateway or a misconfiguration, and
    // such a body can echo the request back — credential included. The tRPC
    // code is kept because it is machine-readable and cannot carry a token.
    return SessionError.refused(
      'That request was refused.',
      code: trpcCode ?? 'BAD_REQUEST',
    );
  }
  return const SessionError.network(
    'The server had a problem signing you in. Try again shortly.',
    code: SessionErrorCode.unreadable,
  );
}
