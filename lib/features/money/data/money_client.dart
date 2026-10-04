import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'money_models.dart';

/// The Supabase access token for the signed-in person, or null.
typedef MoneyTokenProvider = FutureOr<String?> Function();

/// `money.*` on the existing BFF. Every procedure is a POST mutation with the
/// session in the Authorization header; nothing private lands in a URL. No
/// input ever names a person: a `wallet` only selects among the account's
/// own proven wallets, and the server refuses anything else.
class MoneyClient {
  MoneyClient({
    required Uri baseUri,
    required MoneyTokenProvider token,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUri = _validatedBase(baseUri),
       _token = token,
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri _baseUri;
  final MoneyTokenProvider _token;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  bool _closed = false;

  Future<MoneyStatus> status() async =>
      MoneyStatus.fromJson(await _post('money.status', const {}, auth: false));

  /// One tap of a money call. Reuse [idempotencyKey] on every retry of the
  /// same tap: the server answers the same call, never a second one.
  Future<MoneyPrepareResult> prepareCall({
    required MoneyCallKind kind,
    String? marketId,
    String? targetCallId,
    String? side,
    required BigInt amountBaseUnits,
    required String idempotencyKey,
    String? wallet,
    double? confidence,
    String? thesis,
    String? visibility,
  }) async {
    if ((kind == MoneyCallKind.own) != (marketId != null && side != null) ||
        (kind != MoneyCallKind.own) != (targetCallId != null)) {
      throw ArgumentError('An own call names a market; Tail/Fade a call.');
    }
    return MoneyPrepareResult.fromJson(
      await _post('money.prepareCall', {
        'kind': kind.wire,
        if (kind == MoneyCallKind.own) ...{'marketId': marketId, 'side': side},
        if (kind != MoneyCallKind.own) 'targetCallId': targetCallId,
        'amountBaseUnits': amountBaseUnits.toString(),
        'idempotencyKey': idempotencyKey,
        if (wallet != null) 'wallet': wallet,
        if (confidence != null) 'confidence': confidence,
        if (thesis != null) 'thesis': thesis,
        if (visibility != null) 'visibility': visibility,
      }),
    );
  }

  Future<MoneyCallStatus> callStatus(String callId) async =>
      MoneyCallStatus.fromJson(
        await _post('money.callStatus', {'callId': callId}),
      );

  Future<MoneyPrepareResult> retry(String callId, {String? wallet}) async =>
      MoneyPrepareResult.fromJson(
        await _post('money.retry', {
          'callId': callId,
          if (wallet != null) 'wallet': wallet,
        }),
        allowSettled: false,
      );

  Future<MoneyCallWithEntry> keepFree(String callId) async =>
      MoneyCallWithEntry.fromJson(
        await _post('money.keepFree', {'callId': callId}),
      );

  Future<MoneyCallView> discard(String callId) async => MoneyCallView.fromJson(
    moneyObject(await _post('money.discard', {'callId': callId}))['moneyCall'],
  );

  Future<List<MoneyCallWithEntry>> pending() async {
    final calls = moneyObject(await _post('money.pending', const {}))['calls'];
    if (calls is! List) {
      throw const MoneyException(MoneyErrorKind.invalidResponse);
    }
    return [for (final row in calls) MoneyCallWithEntry.fromJson(row)];
  }

  Future<MoneyWalletInfo> wallet() async =>
      MoneyWalletInfo.fromJson(await _post('money.wallet', const {}));

  Future<List<MoneyActivityItem>> activity({int limit = 20}) async =>
      MoneyActivityItem.listFromJson(
        await _post('money.activity', {'limit': limit}),
      );

  Future<TransferPrepareResult> cashOutPrepare({
    required String destination,
    required BigInt amountBaseUnits,
    required String idempotencyKey,
  }) async => TransferPrepareResult.fromJson(
    await _post('money.cashOutPrepare', {
      'destination': destination,
      'amountBaseUnits': amountBaseUnits.toString(),
      'idempotencyKey': idempotencyKey,
    }),
  );

  Future<TransferPrepareResult> depositFromWalletPrepare({
    required String fromWallet,
    required BigInt amountBaseUnits,
    required String idempotencyKey,
  }) async => TransferPrepareResult.fromJson(
    await _post('money.depositFromWalletPrepare', {
      'fromWallet': fromWallet,
      'amountBaseUnits': amountBaseUnits.toString(),
      'idempotencyKey': idempotencyKey,
    }),
  );

  /// The exact signed bytes; a retried submit re-sends these only.
  Future<TransferView> transferSubmit({
    required String transferId,
    required String signedTransaction,
  }) async => TransferView.fromJson(
    await _post('money.transferSubmit', {
      'transferId': transferId,
      'signedTransaction': signedTransaction,
    }),
  );

  Future<TransferView> transferStatus(String transferId) async =>
      TransferView.fromJson(
        await _post('money.transferStatus', {'transferId': transferId}),
      );

  Future<MoneyWinnings> winnings() async =>
      MoneyWinnings.fromJson(await _post('money.winnings', const {}));

  Future<DepositOptions> depositOptions({BigInt? amountBaseUnits}) async =>
      DepositOptions.fromJson(
        await _post('money.depositOptions', {
          if (amountBaseUnits != null)
            'amountBaseUnits': amountBaseUnits.toString(),
        }),
      );

  Future<Object?> _post(
    String procedure,
    Map<String, Object?> input, {
    bool auth = true,
  }) async {
    if (_closed) throw const MoneyException(MoneyErrorKind.connection);
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
      throw const MoneyException(MoneyErrorKind.signedOut);
    }
    request.body = jsonEncode({'json': input});

    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > 262144) {
            throw const MoneyException(MoneyErrorKind.invalidResponse);
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, streamed.statusCode);
      })().timeout(timeout);
    } on MoneyException {
      rethrow;
    } catch (_) {
      throw const MoneyException(MoneyErrorKind.connection);
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const MoneyException(MoneyErrorKind.invalidResponse);
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw MoneyException(
        response.statusCode >= 500
            ? MoneyErrorKind.provider
            : MoneyErrorKind.invalidResponse,
      );
    }
    if (body is! Map<String, dynamic>) {
      throw const MoneyException(MoneyErrorKind.invalidResponse);
    }
    if (body.containsKey('error')) throw _error(body['error']);
    final result = body['result'];
    if (response.statusCode != 200 ||
        result is! Map ||
        !result.containsKey('data')) {
      throw const MoneyException(MoneyErrorKind.invalidResponse);
    }
    final data = result['data'];
    return data is Map && data.containsKey('json') ? data['json'] : data;
  }

  /// tRPC code to a kind. The message is the server's own short copy (render
  /// it verbatim); anything shaped like a stack or a validator dump is not.
  static MoneyException _error(Object? error) {
    final inner = error is Map ? (error['json'] ?? error) : null;
    final data = inner is Map ? inner['data'] : null;
    final code = data is Map ? data['code'] : null;
    final raw = inner is Map ? inner['message'] : null;
    final message =
        raw is String &&
                raw.isNotEmpty &&
                raw.length <= 240 &&
                !raw.contains('\n') &&
                !raw.trimLeft().startsWith('[') &&
                !raw.trimLeft().startsWith('{')
            ? raw
            : null;
    final rawDetails = data is Map ? data['details'] : null;
    final details =
        rawDetails is Map
            ? {
              for (final entry in rawDetails.entries)
                if (entry.key is String &&
                    entry.value is String &&
                    (entry.value as String).length <= 128)
                  entry.key as String: entry.value as String,
            }
            : null;
    final kind = switch (code) {
      'UNAUTHORIZED' => MoneyErrorKind.signedOut,
      'FORBIDDEN' => MoneyErrorKind.forbidden,
      'PRECONDITION_FAILED' => MoneyErrorKind.unavailable,
      'NOT_FOUND' => MoneyErrorKind.notFound,
      'CONFLICT' => MoneyErrorKind.conflict,
      'BAD_REQUEST' => MoneyErrorKind.invalid,
      'UNPROCESSABLE_CONTENT' => MoneyErrorKind.walletNotLinked,
      'TOO_MANY_REQUESTS' => MoneyErrorKind.rateLimited,
      'SERVICE_UNAVAILABLE' || 'BAD_GATEWAY' => MoneyErrorKind.provider,
      _ => MoneyErrorKind.invalidResponse,
    };
    // A signed-out answer never carries server copy into the app.
    return MoneyException(
      kind,
      kind == MoneyErrorKind.signedOut ||
              kind == MoneyErrorKind.invalidResponse
          ? null
          : message,
      details,
    );
  }

  /// An injected transport remains owned by its caller.
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
