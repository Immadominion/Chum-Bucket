import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sol_topup_models.dart';

typedef TopUpTokenProvider = FutureOr<String?> Function();

/// `solTopUp.*` on the existing BFF. Every call is a POST with the session in
/// the Authorization header. The client never names a recipient: `wallet`
/// only says which of the account's own verified wallets this is, and the
/// server checks it. Jupiter's key never comes near the app.
class SolTopUpClient {
  SolTopUpClient({
    required Uri baseUri,
    required TopUpTokenProvider token,
    http.Client? client,
    this.timeout = const Duration(seconds: 25),
  }) : _baseUri = _validatedBase(baseUri),
       _token = token,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri _baseUri;
  final TopUpTokenProvider _token;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  bool _closed = false;

  Future<TopUpStatus> status() async =>
      TopUpStatus.fromJson(await _post('solTopUp.status', const {}, false));

  Future<TopUpPlan> plan({String? wallet}) async => TopUpPlan.fromJson(
    await _post('solTopUp.plan', {if (wallet != null) 'wallet': wallet}),
  );

  /// A checked, unsigned swap — or a [TopUpException] whose kind says why
  /// none can be offered (needs USDC, enough SOL, below Jupiter's minimum).
  Future<TopUpOrder> order({
    required String wallet,
    required BigInt amountBaseUnits,
  }) async {
    final json = await _post('solTopUp.order', {
      'wallet': wallet,
      'amountBaseUnits': amountBaseUnits.toString(),
    });
    if (json['status'] == 'READY') return TopUpOrder.fromJson(json);
    if (json['status'] != 'REFUSED') {
      throw const TopUpException(TopUpErrorKind.invalidResponse);
    }
    final message = json['message'];
    throw TopUpException(switch (json['reason']) {
      'NEEDS_USDC' => TopUpErrorKind.needsUsdc,
      'ENOUGH_SOL' => TopUpErrorKind.enoughSol,
      'BELOW_GASLESS_MINIMUM' => TopUpErrorKind.belowGaslessMinimum,
      'NOT_GASLESS' => TopUpErrorKind.notGasless,
      _ => TopUpErrorKind.invalidResponse,
    }, message is String && message.length <= 240 ? message : null);
  }

  /// [signedTransaction] is the reviewed message with the person's signature.
  Future<TopUpResult> execute({
    required String requestId,
    required String signedTransaction,
  }) async => TopUpResult.fromJson(
    await _post('solTopUp.execute', {
      'requestId': requestId,
      'signedTransaction': signedTransaction,
    }),
  );

  Future<Map<String, dynamic>> _post(
    String procedure,
    Map<String, Object?> input, [
    bool auth = true,
  ]) async {
    if (_closed) throw const TopUpException(TopUpErrorKind.connection);
    final request =
        http.Request(
            'POST',
            _baseUri.replace(path: '${_baseUri.path}/$procedure'),
          )
          ..followRedirects = false
          ..maxRedirects = 0;
    request.headers.addAll({
      'content-type': 'application/json',
      'accept': 'application/json',
    });
    String? token;
    try {
      token = await Future<String?>.sync(_token).timeout(timeout);
    } catch (_) {
      token = null;
    }
    if (token != null && token.isNotEmpty && !RegExp(r'\s').hasMatch(token)) {
      request.headers['authorization'] = 'Bearer $token';
    } else if (auth) {
      throw const TopUpException(TopUpErrorKind.signedOut);
    }
    request.body = jsonEncode({'json': input});

    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > 65536) {
            throw const TopUpException(TopUpErrorKind.invalidResponse);
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, streamed.statusCode);
      })().timeout(timeout);
    } on TopUpException {
      rethrow;
    } catch (_) {
      throw const TopUpException(TopUpErrorKind.connection);
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw TopUpException(
        response.statusCode >= 500
            ? TopUpErrorKind.provider
            : TopUpErrorKind.invalidResponse,
      );
    }
    if (body is! Map<String, dynamic>) {
      throw const TopUpException(TopUpErrorKind.invalidResponse);
    }
    if (body.containsKey('error')) throw _error(body['error']);
    final result = body['result'];
    if (response.statusCode != 200 ||
        result is! Map ||
        !result.containsKey('data')) {
      throw const TopUpException(TopUpErrorKind.invalidResponse);
    }
    final data = result['data'];
    final json = data is Map && data.containsKey('json') ? data['json'] : data;
    if (json is! Map<String, dynamic>) {
      throw const TopUpException(TopUpErrorKind.invalidResponse);
    }
    return json;
  }

  static TopUpException _error(Object? error) {
    final inner = error is Map ? (error['json'] ?? error) : null;
    final data = inner is Map ? inner['data'] : null;
    final code = data is Map ? data['code'] : null;
    final raw = inner is Map ? inner['message'] : null;
    final message =
        raw is String &&
                raw.length <= 240 &&
                !raw.contains('\n') &&
                !raw.trimLeft().startsWith('[') &&
                !raw.trimLeft().startsWith('{')
            ? raw
            : null;
    // The server's message says which precondition; the kind drives the UI.
    final kind = switch (code) {
      'UNAUTHORIZED' => TopUpErrorKind.signedOut,
      'FORBIDDEN' => TopUpErrorKind.notYours,
      'PRECONDITION_FAILED' => TopUpErrorKind.unavailable,
      'UNPROCESSABLE_CONTENT' => TopUpErrorKind.rejected,
      'BAD_REQUEST' => TopUpErrorKind.rejected,
      'TOO_MANY_REQUESTS' => TopUpErrorKind.rateLimited,
      'CONFLICT' => TopUpErrorKind.expired,
      'NOT_FOUND' => TopUpErrorKind.expired,
      'BAD_GATEWAY' || 'SERVICE_UNAVAILABLE' => TopUpErrorKind.provider,
      _ => TopUpErrorKind.invalidResponse,
    };
    return TopUpException(kind, message);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsClient) _client.close();
  }

  static Uri _validatedBase(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Supply an HTTPS BFF base URI.');
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path);
  }
}
