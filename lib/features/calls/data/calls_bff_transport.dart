/// tRPC transport for the call slice.
///
/// This is a deliberate **copy** of the procedure-agnostic pattern in
/// `arena_backend_service.dart` (`_postMutation` / `_decodeTrpcResponse`,
/// around line 458): a query is `GET $base/$path?input={"json":…}`, a mutation
/// is `POST $base/$path` with body `{"json": …}`, and both unwrap
/// `result.data.json`, raise on the `{"error":{"json":{…}}}` envelope, and fall
/// back to the raw `data` when the response was not superjson-wrapped.
///
/// It is a copy rather than an import on purpose. `ArenaBackendService` is
/// owned by another packet (contract §6) and throws `ArenaBackendException`,
/// which no call screen knows how to render. This file throws only the four
/// [CallsException] subclasses the UI already has a state for.
///
/// Three rules this file exists to hold:
///
/// * **Never hardcode a host.** The base URL comes from configuration
///   (`CALLS_BFF_URL`, falling back to the already-allowlisted
///   `ARENA_BACKEND_URL`), exactly as `ArenaBackendService` reads its own.
/// * **The HTTP client is injectable** so a test can drive every branch with
///   no network at all.
/// * **Identity is never a request field.** The viewer is carried by the
///   session ([CallsBffAuthTokenProvider]), never as a `userId` or `wallet` in
///   a body — contract §0 invariant 3 and §8 finding 4.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'package:chumbucket/features/calls/data/calls_repository.dart';

/// Supplies the current session token, or null when signed out.
///
/// Returning null is not an error: reading never requires a session. Only
/// writing does, and the repository refuses those locally before a request is
/// ever sent.
typedef CallsBffAuthTokenProvider = FutureOr<String?> Function();

/// Configuration key for the calls BFF base URL.
///
/// Not yet in `AppConfig.publicKeys`, so it resolves to null in a release
/// build today and [kCallsBffFallbackUrlKey] is used instead. See
/// `docs/contracts/integration-requests/packet-e.md`.
const String kCallsBffUrlKey = 'CALLS_BFF_URL';

/// The already-allowlisted BFF base URL (`AppConfig.publicKeys`). The Bun/tRPC
/// server that serves the arena procedures is the same server that will serve
/// `calls.*` and `markets.*`.
const String kCallsBffFallbackUrlKey = 'ARENA_BACKEND_URL';

/// The deployed calls BFF.
///
/// A real host, not localhost, because this is what a build with no
/// --dart-define actually talks to — and a device pointing at localhost fails
/// every request with nothing on screen to explain why. Override per build with
/// --dart-define=CALLS_BFF_URL=... for staging or a local server.
const String kCallsBffDefaultUrl =
    'https://chumbucket-calls-bff-production.up.railway.app';

/// Configuration key for the host shareable links are built against.
const String kCallsLinkHostKey = 'CALLS_LINK_HOST';

/// The owner's live site. `chumbucket.fun` serves the `/c`, `/u` and `/m`
/// landing pages (with an install/open-in-app fallback) and the
/// `/.well-known/assetlinks.json` that lets Android hand these links straight
/// to the app. Matches `kCallDeepLinkHosts` in `call_deep_link.dart`.
///
/// `chumbucket.app` was the old default; that domain does not resolve
/// (NXDOMAIN), so every link built against it was dead for the recipient.
const String kCallsLinkHostDefault = 'https://chumbucket.fun';

/// Reads a configuration value without assuming `dotenv` has been loaded.
///
/// `dotenv.env` **throws** `NotInitializedError` before `AppConfig.initialize()`
/// has run — which is the case in every unit test. Guarding here is what lets
/// this transport be constructed in a test with no Flutter bindings at all.
String? readCallsBffConfig(String key) {
  if (!dotenv.isInitialized) return null;
  final value = dotenv.env[key];
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

/// `CALLS_BFF_URL`, else `ARENA_BACKEND_URL`, else the local default.
String resolveCallsBffBaseUrl() =>
    readCallsBffConfig(kCallsBffUrlKey) ??
    readCallsBffConfig(kCallsBffFallbackUrlKey) ??
    kCallsBffDefaultUrl;

/// `CALLS_LINK_HOST`, else the public app host.
String resolveCallsLinkHost() =>
    readCallsBffConfig(kCallsLinkHostKey) ?? kCallsLinkHostDefault;

/// Drops a trailing slash so `'$base/$path'` never doubles up.
String normalizeCallsBffBaseUrl(String url) {
  var trimmed = url.trim();
  while (trimmed.length > 1 && trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

/// Maps a tRPC error envelope onto exactly one of the four [CallsException]
/// classes the UI renders.
///
/// tRPC reports an HTTP-ish code string in `error.json.data.code` and the
/// matching status in `error.json.data.httpStatus`. The mapping is:
///
/// | tRPC code | HTTP | Exception |
/// | --- | --- | --- |
/// | `UNAUTHORIZED` | 401 | [CallsSignedOutException] |
/// | `PARSE_ERROR`, `BAD_REQUEST`, `FORBIDDEN`, `NOT_FOUND`, `METHOD_NOT_SUPPORTED`, `TIMEOUT`, `CONFLICT`, `PRECONDITION_FAILED`, `PAYLOAD_TOO_LARGE`, `UNSUPPORTED_MEDIA_TYPE`, `UNPROCESSABLE_CONTENT`, `TOO_MANY_REQUESTS`, `CLIENT_CLOSED_REQUEST` | 4xx | [CallsRejectedException] |
/// | `INTERNAL_SERVER_ERROR`, `NOT_IMPLEMENTED`, `BAD_GATEWAY`, `SERVICE_UNAVAILABLE`, `GATEWAY_TIMEOUT` | 5xx | [CallsFailure] |
/// | anything unrecognised | — | by status: 401 → signed out, other 4xx → rejected, else [CallsFailure] |
///
/// A 5xx is deliberately **not** [CallsOfflineException]: the server answered,
/// so "you're offline" would be a lie. Only a failure to complete the round
/// trip at all is offline, and that is classified in [CallsBffTransport.send].
CallsException callsExceptionForTrpcError({
  required String procedurePath,
  required int statusCode,
  String? trpcCode,
  int? httpStatus,
  String? message,
}) {
  final detail = (message ?? '').trim();
  final status = httpStatus ?? statusCode;

  switch (trpcCode) {
    case 'UNAUTHORIZED':
      return const CallsSignedOutException();
    case 'PARSE_ERROR':
    case 'BAD_REQUEST':
    case 'FORBIDDEN':
    case 'NOT_FOUND':
    case 'METHOD_NOT_SUPPORTED':
    case 'TIMEOUT':
    case 'CONFLICT':
    case 'PRECONDITION_FAILED':
    case 'PAYLOAD_TOO_LARGE':
    case 'UNSUPPORTED_MEDIA_TYPE':
    case 'UNPROCESSABLE_CONTENT':
    case 'TOO_MANY_REQUESTS':
    case 'CLIENT_CLOSED_REQUEST':
      return CallsRejectedException(
        detail.isEmpty ? 'That request was refused.' : detail,
      );
    case 'INTERNAL_SERVER_ERROR':
    case 'NOT_IMPLEMENTED':
    case 'BAD_GATEWAY':
    case 'SERVICE_UNAVAILABLE':
    case 'GATEWAY_TIMEOUT':
      return detail.isEmpty ? const CallsFailure() : CallsFailure(detail);
  }

  // Unrecognised (or absent) code: fall back to the status the server used.
  if (status == 401) return const CallsSignedOutException();
  if (status >= 400 && status < 500) {
    return CallsRejectedException(
      detail.isEmpty ? 'That request was refused.' : detail,
    );
  }
  return detail.isEmpty
      ? const CallsFailure()
      : CallsFailure('$procedurePath: $detail');
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

/// Procedure-agnostic tRPC client. Knows nothing about calls, markets or
/// people — it only speaks the envelope.
class CallsBffTransport {
  CallsBffTransport({
    String? baseUrl,
    http.Client? httpClient,
    CallsBffAuthTokenProvider? authToken,
    Duration timeout = const Duration(seconds: 15),
    bool verbose = true,
  }) : baseUrl = normalizeCallsBffBaseUrl(baseUrl ?? resolveCallsBffBaseUrl()),
       _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       _authToken = authToken,
       _timeout = timeout,
       _verbose = verbose;

  /// Never a hardcoded host — see [resolveCallsBffBaseUrl].
  final String baseUrl;

  final http.Client _client;
  final bool _ownsClient;
  final CallsBffAuthTokenProvider? _authToken;
  final Duration _timeout;
  final bool _verbose;

  /// tRPC query: `GET $base/$path?input={"json":{…}}`.
  Future<Object?> query(
    String procedurePath, [
    Map<String, dynamic> input = const {},
  ]) => send(procedurePath, input, method: 'GET');

  /// tRPC mutation: `POST $base/$path` with body `{"json":{…}}`.
  Future<Object?> mutate(String procedurePath, Map<String, dynamic> input) =>
      send(procedurePath, input, method: 'POST');

  /// The single round trip. Everything thrown out of here is a
  /// [CallsException]; nothing else escapes.
  Future<Object?> send(
    String procedurePath,
    Map<String, dynamic> input, {
    required String method,
  }) async {
    final envelope = jsonEncode({'json': input});
    final Uri uri;
    if (method == 'GET') {
      uri = Uri.parse(
        '$baseUrl/$procedurePath',
      ).replace(queryParameters: {'input': envelope});
    } else {
      uri = Uri.parse('$baseUrl/$procedurePath');
    }

    final headers = <String, String>{'content-type': 'application/json'};
    final token = await _authToken?.call();
    if (token != null && token.isNotEmpty) {
      headers['authorization'] = 'Bearer $token';
    }

    if (_verbose) {
      developer.log('📣 CallsBff: $method $baseUrl/$procedurePath');
    }

    final http.Response response;
    try {
      response = await (method == 'GET'
              ? _client.get(uri, headers: headers)
              : _client.post(uri, headers: headers, body: envelope))
          .timeout(_timeout);
    } on CallsException {
      rethrow;
    } on TimeoutException {
      // The round trip never completed. This — and only this — is "offline".
      throw const CallsOfflineException();
    } on http.ClientException {
      // `IOClient` wraps SocketException/HandshakeException into this, so DNS
      // failure, refused connection and a dropped socket all land here.
      throw const CallsOfflineException();
    } catch (error) {
      if (_verbose) {
        developer.log(
          '📣 CallsBff: transport failure on $procedurePath: $error',
        );
      }
      throw const CallsOfflineException();
    }

    return decode(response, procedurePath: procedurePath);
  }

  /// Decodes the tRPC envelope. Mirrors `_decodeTrpcResponse`, but every throw
  /// is a [CallsException] rather than an arena-specific one.
  Object? decode(http.Response response, {required String procedurePath}) {
    Map<String, dynamic> body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('envelope is not a JSON object');
      }
      body = decoded;
    } catch (_) {
      // A body we cannot read is not a network failure — bytes arrived. A 401
      // with an empty or HTML body (a proxy, a login wall) is still a session
      // problem, so it keeps its own state; everything else is "unknown".
      if (response.statusCode == 401) throw const CallsSignedOutException();
      throw CallsFailure(
        'The server sent something we could not read ($procedurePath, '
        'status ${response.statusCode}).',
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
      final code = data?['code'] as String?;
      final httpStatus = (data?['httpStatus'] as num?)?.toInt();

      if (_verbose) {
        developer.log(
          '📣 CallsBff: $procedurePath error '
          '${code ?? httpStatus ?? response.statusCode}: ${message ?? ''}',
        );
      }

      throw callsExceptionForTrpcError(
        procedurePath: procedurePath,
        statusCode: response.statusCode,
        trpcCode: code,
        httpStatus: httpStatus,
        message: message,
      );
    }

    if (response.statusCode != 200) {
      throw callsExceptionForTrpcError(
        procedurePath: procedurePath,
        statusCode: response.statusCode,
        message: 'The server returned ${response.statusCode}.',
      );
    }

    if (!body.containsKey('result')) {
      throw CallsFailure(
        'The server sent an empty envelope for $procedurePath.',
      );
    }

    final result = body['result'];
    final data = result is Map<String, dynamic> ? result['data'] : null;
    if (data is Map<String, dynamic> && data.containsKey('json')) {
      return data['json'];
    }
    // Fall back to raw data if the response wasn't superjson-wrapped.
    return data;
  }

  /// Closes the client, but only if this transport created it. A caller that
  /// injected its own client keeps ownership of it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
