import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'deposits_models.dart';

/// The Supabase access token for the signed-in person, or null.
typedef DepositsTokenProvider = FutureOr<String?> Function();

/// `deposits.*` on the existing BFF. Every call is a POST: the session token
/// rides in the Authorization header, never a URL. The client never sends a
/// recipient address — only, optionally, which of the account's own verified
/// wallets this device is using, which the server checks.
class DepositsClient {
  DepositsClient({
    required Uri baseUri,
    required DepositsTokenProvider token,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUri = _validatedBase(baseUri),
       _token = token,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri _baseUri;
  final DepositsTokenProvider _token;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  bool _closed = false;

  Future<DepositsStatus> status() async => DepositsStatus.fromJson(
    await _map('deposits.status', const {}, auth: false),
  );

  Future<WalletBalance> balance({String? wallet}) async =>
      WalletBalance.fromJson(
        await _map('deposits.balance', {if (wallet != null) 'wallet': wallet}),
      );

  Future<DepositQuote> quote({
    required UsdAmount amount,
    String? wallet,
    String? receiptEmail,
  }) async => DepositQuote.fromJson(
    await _map('deposits.quote', {
      'amountUsd': amount.wire,
      if (wallet != null) 'wallet': wallet,
      if (receiptEmail != null) 'receiptEmail': receiptEmail,
    }),
  );

  Future<CreatedDeposit> create({
    required UsdAmount amount,
    required String idempotencyKey,
    String? wallet,
    String? receiptEmail,
  }) async => CreatedDeposit.fromJson(
    await _map('deposits.create', {
      'amountUsd': amount.wire,
      'idempotencyKey': idempotencyKey,
      if (wallet != null) 'wallet': wallet,
      if (receiptEmail != null) 'receiptEmail': receiptEmail,
    }),
  );

  Future<DepositOrder> order(String orderId) async =>
      DepositOrder.fromJson(await _map('deposits.order', {'orderId': orderId}));

  /// [signatureBase64] is the wallet's ed25519 signature over the exact
  /// ownership message Crossmint asked for. It is a message signature: it
  /// cannot authorise a transfer.
  Future<DepositOrder> verifyWallet({
    required String orderId,
    required String signatureBase64,
  }) async => DepositOrder.fromJson(
    await _map('deposits.verifyWallet', {
      'orderId': orderId,
      'signature': signatureBase64,
    }),
  );

  Future<Map<String, dynamic>> _map(
    String procedure,
    Map<String, Object?> input, {
    bool auth = true,
  }) async {
    final data = await _post(procedure, input, auth: auth);
    if (data is! Map<String, dynamic>) {
      throw const DepositsException(DepositsErrorKind.invalidResponse);
    }
    return data;
  }

  Future<Object?> _post(
    String procedure,
    Map<String, Object?> input, {
    required bool auth,
  }) async {
    if (_closed) throw const DepositsException(DepositsErrorKind.connection);
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
    final usable =
        token != null && token.isNotEmpty && !RegExp(r'\s').hasMatch(token);
    if (usable) {
      request.headers['authorization'] = 'Bearer $token';
    } else if (auth) {
      throw const DepositsException(DepositsErrorKind.signedOut);
    }
    request.body = jsonEncode({'json': input});

    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > 131072) {
            throw const DepositsException(DepositsErrorKind.invalidResponse);
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, streamed.statusCode);
      })().timeout(timeout);
    } on DepositsException {
      rethrow;
    } catch (_) {
      throw const DepositsException(DepositsErrorKind.connection);
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const DepositsException(DepositsErrorKind.invalidResponse);
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw DepositsException(
        response.statusCode >= 500
            ? DepositsErrorKind.provider
            : DepositsErrorKind.invalidResponse,
      );
    }
    if (body is! Map<String, dynamic>) {
      throw const DepositsException(DepositsErrorKind.invalidResponse);
    }
    if (body.containsKey('error')) throw _error(body['error']);
    final result = body['result'];
    if (response.statusCode != 200 ||
        result is! Map ||
        !result.containsKey('data')) {
      throw const DepositsException(DepositsErrorKind.invalidResponse);
    }
    final data = result['data'];
    return data is Map && data.containsKey('json') ? data['json'] : data;
  }

  static DepositsException _error(Object? error) {
    final inner = error is Map ? (error['json'] ?? error) : null;
    final data = inner is Map ? inner['data'] : null;
    final code = data is Map ? data['code'] : null;
    final raw = inner is Map ? inner['message'] : null;
    // The BFF's deposit errors are its own short copy. Anything that looks
    // like a stack, a JSON blob or a validator dump is not shown.
    final message =
        raw is String &&
                raw.length <= 240 &&
                !raw.contains('\n') &&
                !raw.trimLeft().startsWith('[') &&
                !raw.trimLeft().startsWith('{')
            ? raw
            : null;
    final kind = switch (code) {
      'UNAUTHORIZED' => DepositsErrorKind.signedOut,
      // Which account problem it is comes from deposits.status; the message
      // carries the server's words for this particular refusal.
      'FORBIDDEN' => DepositsErrorKind.forbidden,
      'PRECONDITION_FAILED' => DepositsErrorKind.unavailable,
      'BAD_REQUEST' => DepositsErrorKind.invalid,
      'TOO_MANY_REQUESTS' => DepositsErrorKind.rateLimited,
      'CONFLICT' => DepositsErrorKind.conflict,
      'NOT_FOUND' => DepositsErrorKind.notFound,
      'BAD_GATEWAY' || 'SERVICE_UNAVAILABLE' => DepositsErrorKind.provider,
      _ => DepositsErrorKind.invalidResponse,
    };
    // Zod input errors are BAD_REQUEST with a JSON message: local copy then.
    return DepositsException(kind, message);
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
      throw ArgumentError(
        'Supply an HTTPS BFF base URI without credentials or query.',
      );
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri.replace(path: path);
  }
}
