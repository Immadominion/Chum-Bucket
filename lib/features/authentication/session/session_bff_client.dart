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
import 'existing_account_proof.dart';
import 'wallet_link_proof.dart';
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
    return _identityFrom(data);
  }

  Future<ExistingAccountProof> requestExistingAccountProof(
    String accessToken, {
    required String address,
    required String network,
  }) async => ExistingAccountProof.parse(
    await _send(
      'auth.requestExistingAccountProof',
      method: 'POST',
      bearer: accessToken,
      input: {
        'supabaseAccessToken': accessToken,
        'address': address,
        'domain': accountClaimDomain,
        'uri': accountClaimUri,
      },
    ),
    address: address,
    network: network,
  );

  Future<SessionIdentity> claimExistingAccount(
    String accessToken, {
    required String address,
    required ExistingAccountProof proof,
    required String signature,
  }) async {
    proof.checkFresh();
    final data = await _send(
      'auth.claimExistingAccount',
      method: 'POST',
      bearer: accessToken,
      input: {
        'supabaseAccessToken': accessToken,
        'address': address,
        'message': proof.message,
        'signature': signature,
      },
    );
    if (data is! Map ||
        !['claimed', 'already_claimed'].contains(data['outcome'])) {
      throw const SessionException(
        SessionError.network(
          'The server could not confirm the account link. Retry from Settings.',
          code: SessionErrorCode.unreadable,
        ),
      );
    }
    return _identityFrom(data);
  }

  /// Explicitly creates a person for the VERIFIED session; no wallet or
  /// client-supplied user id is sent. Credentials remain outside the URL.
  Future<SessionIdentity> completeProfile(
    String accessToken, {
    required String displayName,
    String? handle,
  }) async {
    final data = await _send(
      'auth.completeProfile',
      method: 'POST',
      input: {
        'supabaseAccessToken': accessToken,
        'displayName': displayName.trim(),
        if (handle != null) 'handle': handle.trim().toLowerCase(),
      },
      bearer: accessToken,
    );
    return _identityFrom(data);
  }

  /// An existing account without a @username claims one: the caller's own
  /// account only, and only while it has none (`auth.claimUsername`). The
  /// answer is the identity with its new handle.
  Future<SessionIdentity> claimUsername(
    String accessToken, {
    required String handle,
  }) async {
    final data = await _send(
      'auth.claimUsername',
      method: 'POST',
      input: {
        'supabaseAccessToken': accessToken,
        'handle': handle.trim().toLowerCase(),
      },
      bearer: accessToken,
    );
    final identity = _identityFrom(data);
    final claimed = data is Map ? data['handle'] : null;
    if (claimed is! String || claimed.isEmpty) {
      throw const SessionException(
        SessionError.network(
          'The server did not confirm your username.',
          code: SessionErrorCode.unreadable,
        ),
      );
    }
    return identity.withHandle(claimed);
  }

  /// Asks for the exact message that links [address] to the signed-in
  /// account (`auth.requestWalletNonce`, purpose `link_wallet`), checked
  /// before anything may sign it.
  Future<WalletLinkProof> requestWalletLink(
    String accessToken, {
    required String address,
  }) async => WalletLinkProof.parse(
    await _send(
      'auth.requestWalletNonce',
      method: 'POST',
      bearer: accessToken,
      input: {
        'supabaseAccessToken': accessToken,
        'address': address,
        'domain': accountClaimDomain,
        'uri': accountClaimUri,
        'purpose': 'link_wallet',
      },
    ),
    address: address,
  );

  /// Sends the signed link message back (`auth.linkWallet`). [signature] is
  /// base58. [walletType] "embedded" labels a key this app made on the phone.
  /// Answers "linked" or "reaffirmed".
  Future<String> linkWallet(
    String accessToken, {
    required String address,
    required WalletLinkProof proof,
    required String signature,
    String walletType = 'mwa',
  }) async {
    proof.checkFresh();
    final data = await _send(
      'auth.linkWallet',
      method: 'POST',
      bearer: accessToken,
      input: {
        'supabaseAccessToken': accessToken,
        'address': address,
        'message': proof.message,
        'signature': signature,
        'purpose': 'link_wallet',
        'walletType': walletType,
      },
    );
    final outcome = data is Map ? data['outcome'] : null;
    if (data is! Map ||
        data['address'] != address ||
        (outcome != 'linked' && outcome != 'reaffirmed')) {
      throw const SessionException(
        SessionError.network(
          'The server did not confirm the wallet link. Try again.',
          code: SessionErrorCode.unreadable,
        ),
      );
    }
    return outcome as String;
  }

  /// Whether [handle] can be claimed. Public and credential-free: usernames
  /// are public, and the answer carries no profile field.
  Future<UsernameStatus> usernameStatus(String handle) async {
    final data = await _send(
      'auth.usernameStatus',
      method: 'GET',
      input: {'handle': handle.trim().toLowerCase()},
    );
    final status = data is Map ? data['status'] : null;
    return switch (status) {
      'available' => UsernameStatus.available,
      'reserved' => UsernameStatus.reserved,
      'taken' => UsernameStatus.taken,
      'invalid' => UsernameStatus.invalid,
      _ =>
        throw const SessionException(
          SessionError.network(
            'We couldn’t check that username.',
            code: SessionErrorCode.unreadable,
          ),
        ),
    };
  }

  SessionIdentity _identityFrom(Object? data) {
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
    // `handle` present (even null) means the server read the stored value;
    // absent means it could not, which must never read as "no username".
    final handle = map['handle'];
    return SessionIdentity(
      userId: userId,
      // Absent rather than wrong is survivable: the canonical id is the one
      // that matters, and authUserId is only ever used for diagnostics.
      authUserId: authUserId is String ? authUserId : '',
      handle: handle is String && handle.isNotEmpty ? handle : null,
      handleKnown:
          map.containsKey('handle') && (handle == null || handle is String),
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
      existingAccountClaimsEnabled: map['existingAccountClaimsEnabled'] == true,
      walletSignIn: map['walletSignIn'] == true,
      walletProfileCarry: map['walletProfileCarry'] == true,
      allowedDomains: _strings(map['allowedDomains']),
      allowedUris: _strings(map['allowedUris']),
    );
  }

  static List<String> _strings(Object? value) =>
      value is List && value.every((v) => v is String)
          ? List<String>.unmodifiable(value.cast<String>())
          : const [];

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
    // A GET carries its input in the query string, so only public,
    // credential-free input may ever be sent that way.
    final uri =
        method == 'GET' && input != null
            ? Uri.parse('$baseUrl/$procedurePath').replace(
              queryParameters: {
                'input': jsonEncode({'json': input}),
              },
            )
            : Uri.parse('$baseUrl/$procedurePath');
    final headers = <String, String>{'content-type': 'application/json'};
    if (bearer != null && bearer.isNotEmpty) {
      headers['authorization'] = 'Bearer $bearer';
    }

    final http.Response response;
    try {
      // A redirect must never forward the credential/proof body to a new host.
      final request =
          http.Request(method, uri)
            ..followRedirects = false
            ..headers.addAll(headers);
      if (method != 'GET') {
        request.body = jsonEncode({'json': input ?? const {}});
      }
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
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
    case 'USERNAME_TAKEN':
      return const SessionError.refused(
        'That username is taken. Try another.',
        code: 'USERNAME_TAKEN',
      );
    case 'USERNAME_RESERVED':
      return const SessionError.refused(
        'That username is reserved. Try another.',
        code: 'USERNAME_RESERVED',
      );
    case 'USERNAME_INVALID':
      return const SessionError.refused(
        'Use 3–20 letters, numbers or underscores.',
        code: 'USERNAME_INVALID',
      );
    case 'HANDLE_ALREADY_SET':
      return const SessionError.refused(
        'Your account already has a username.',
        code: 'HANDLE_ALREADY_SET',
      );
    case 'WALLET_OWNED_BY_ANOTHER_USER':
    case 'WALLET_REQUIRES_TRANSFER':
      return SessionError.refused(
        'That wallet already belongs to another Chumbucket account. Nothing '
        'was linked.',
        code: detail,
      );
    case 'WALLET_LINK_FAILED':
      return const SessionError.network(
        'We couldn’t link the wallet. Try again shortly.',
        code: 'WALLET_LINK_FAILED',
      );
    case 'SIWS_BAD_SIGNATURE':
    case 'SIWS_ADDRESS_MISMATCH':
    case 'SIWS_MALFORMED_MESSAGE':
    case 'SIWS_STATEMENT_MISMATCH':
    case 'SIWS_DOMAIN_MISMATCH':
    case 'SIWS_URI_MISMATCH':
    case 'SIWS_NETWORK_MISMATCH':
    case 'SIWS_PURPOSE_MISMATCH':
      return SessionError.refused(
        'The wallet signature wasn’t accepted. Nothing was linked.',
        code: detail,
      );
    case 'PROFILE_NAME_INVALID':
      return const SessionError.refused(
        'Use a name of 1–60 characters.',
        code: 'PROFILE_NAME_INVALID',
      );
    case 'WALLET_HAS_PROFILE':
      return const SessionError.refused(
        'This wallet already has a Chumbucket profile. Bringing it over to '
        'wallet sign-in is being switched on; your profile is unchanged.',
        code: 'WALLET_HAS_PROFILE',
      );
    case 'ACCOUNT_CLAIMS_DISABLED':
      return const SessionError.refused(
        'Linking Google to an existing profile isn’t open yet. Your existing account is unchanged.',
        code: 'ACCOUNT_CLAIMS_DISABLED',
      );
    case 'ACCOUNT_CLAIM_UNAVAILABLE':
      return const SessionError.refused(
        'This account needs an ownership review before Google can be linked. Contact support; do not create another profile.',
        code: 'ACCOUNT_CLAIM_UNAVAILABLE',
      );
    case 'ACCOUNT_CLAIM_CONFLICT':
      return const SessionError.refused(
        'These sign-ins belong to different accounts. Nothing was merged. Contact support.',
        code: 'ACCOUNT_CLAIM_CONFLICT',
      );
    case 'ACCOUNT_CLAIM_RATE_LIMITED':
      return const SessionError.refused(
        'Too many linking attempts. Wait a minute before trying again.',
        code: 'ACCOUNT_CLAIM_RATE_LIMITED',
      );
    case 'NONCE_EXPIRED':
    case 'NONCE_REUSED':
    case 'NONCE_UNKNOWN':
      return SessionError.refused(
        'This wallet proof is no longer valid. Try linking Google again.',
        code: detail,
      );
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
