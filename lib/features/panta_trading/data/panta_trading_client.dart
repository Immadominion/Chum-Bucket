import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/panta_wallet_port.dart';
import 'panta_lifecycle_models.dart';
import 'panta_trading_models.dart';

/// The supplied URI is the existing BFF's tRPC base, including its path.
/// No default host, provider credential, identity creation, logs, or broadcast.
class PantaTradingClient {
  PantaTradingClient({
    required Uri baseUri,
    required PantaSessionProvider session,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _baseUri = _validatedBase(baseUri),
       _session = session,
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (timeout <= Duration.zero) throw ArgumentError('A timeout is required.');
  }

  final Uri _baseUri;
  final PantaSessionProvider _session;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  bool _closed = false;

  Future<PantaSession?> currentSession() async {
    try {
      return await Future<PantaSession?>.sync(_session).timeout(timeout);
    } catch (_) {
      throw const PantaException(PantaErrorCode.connection);
    }
  }

  /// Public and deliberately credential-free. All procedures use POST.
  Future<PantaTradingStatus> status() async =>
      PantaTradingStatus.fromJson(await _post('pantaTrading.status', const {}));

  Future<PantaPreparedTrade> prepare(
    PantaPrepareInput input, {
    required String accountId,
  }) async => PantaPreparedTrade.fromJson(
    await _post('pantaTrading.prepare', input.toJson(), accountId: accountId),
  );

  Future<PantaVenueOrder> submit({
    required String orderId,
    required String signedTransaction,
    required String accountId,
  }) async {
    decodePantaTransaction(signedTransaction);
    _validateOrderId(orderId);
    return PantaVenueOrder.fromJson(
      await _post('pantaTrading.submit', {
        'orderId': orderId,
        'signedTransaction': signedTransaction,
      }, accountId: accountId),
    );
  }

  Future<PantaVenueOrder> order({
    required String orderId,
    required String accountId,
  }) async {
    _validateOrderId(orderId);
    return PantaVenueOrder.fromJson(
      await _post('pantaTrading.order', {
        'orderId': orderId,
      }, accountId: accountId),
    );
  }

  Future<PantaVenueOrder?> forCall({
    required String callId,
    required String wallet,
    required String accountId,
  }) async {
    validatePantaWallet(wallet);
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(callId)) {
      throw const PantaException(PantaErrorCode.invalidResponse);
    }
    return PantaForCallResult.fromJson(
      await _post('pantaTrading.forCall', {
        'callId': callId,
        'wallet': wallet,
      }, accountId: accountId),
    ).order;
  }

  /// The person's newest signed order on their own call, any wallet. A ledger
  /// read on the server: it never asks Panta, so it is safe to poll.
  Future<PantaVenueOrder?> callOrder({
    required String callId,
    required String accountId,
  }) async {
    _validateUuid(callId);
    return PantaCallOrder.fromJson(
      await _post(
        'pantaTrading.callOrder',
        {'callId': callId},
        accountId: accountId,
        forbiddenIsUnavailable: true,
      ),
    ).order;
  }

  /// The signed-in person's funded positions. Session-keyed; no identity input.
  Future<PantaPositionsPage> positions({required String accountId}) async =>
      PantaPositionsPage.fromJson(
        await _post(
          'pantaTrading.positions',
          const {},
          accountId: accountId,
          forbiddenIsUnavailable: true,
          // Up to 200 rows; still bounded.
          maxBytes: 524288,
        ),
      );

  /// Reviews a win claim for one of the person's own confirmed positions.
  Future<PantaClaimPrepared> claimPrepare({
    required String orderId,
    required String idempotencyKey,
    required String accountId,
  }) async {
    _validateOrderId(orderId);
    _validateUuid(idempotencyKey);
    return PantaClaimPrepared.fromJson(
      await _post(
        'pantaTrading.claimPrepare',
        {'orderId': orderId, 'idempotencyKey': idempotencyKey},
        accountId: accountId,
        forbiddenIsUnavailable: true,
      ),
    );
  }

  Future<PantaClaimView> claimSubmit({
    required String claimId,
    required String signedTransaction,
    required String accountId,
  }) async {
    _validateUuid(claimId);
    decodePantaTransaction(signedTransaction);
    return PantaClaimView.fromJson(
      await _post(
        'pantaTrading.claimSubmit',
        {'claimId': claimId, 'signedTransaction': signedTransaction},
        accountId: accountId,
        forbiddenIsUnavailable: true,
      ),
    );
  }

  Future<PantaClaimView> claim({
    required String claimId,
    required String accountId,
  }) async {
    _validateUuid(claimId);
    return PantaClaimView.fromJson(
      await _post(
        'pantaTrading.claim',
        {'claimId': claimId},
        accountId: accountId,
        forbiddenIsUnavailable: true,
      ),
    );
  }

  Future<Object?> _post(
    String procedure,
    Map<String, Object?> input, {
    String? accountId,
    bool forbiddenIsUnavailable = false,
    int maxBytes = 65536,
  }) async {
    if (_closed) throw const PantaException(PantaErrorCode.connection);
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
    if (accountId != null) {
      final session = await currentSession();
      if (session == null ||
          session.accountId.isEmpty ||
          session.accessToken.isEmpty) {
        throw const PantaException(PantaErrorCode.signedOut);
      }
      if (session.accountId != accountId) {
        throw const PantaException(PantaErrorCode.sessionChanged);
      }
      if (RegExp(r'\s').hasMatch(session.accessToken)) {
        throw const PantaException(PantaErrorCode.signedOut);
      }
      request.headers['authorization'] = 'Bearer ${session.accessToken}';
    }
    request.body = jsonEncode({'json': input});

    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const PantaException(PantaErrorCode.invalidResponse);
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, streamed.statusCode);
      })().timeout(timeout);
    } on PantaException {
      rethrow;
    } catch (_) {
      throw const PantaException(PantaErrorCode.connection);
    }
    if (response.statusCode == 401) {
      throw const PantaException(PantaErrorCode.signedOut);
    }
    // Never decode, follow, or expose a redirect's Location or HTML message.
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const PantaException(PantaErrorCode.rejected);
    }
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic>) {
        throw const PantaException(PantaErrorCode.invalidResponse);
      }
      if (body.containsKey('error')) {
        final error = body['error'];
        final inner = error is Map ? (error['json'] ?? error) : null;
        final data = inner is Map ? inner['data'] : null;
        final code = data is Map ? data['code'] : null;
        if (code == 'UNAUTHORIZED') {
          throw const PantaException(PantaErrorCode.signedOut);
        }
        // The BFF's own code for a signing wallet that is not one of the
        // account's (`WALLET_NOT_LINKED`); nothing else on this path uses it.
        if (code == 'UNPROCESSABLE_CONTENT') {
          throw const PantaException(PantaErrorCode.walletNotLinked);
        }
        if (code == 'PRECONDITION_FAILED' ||
            code == 'NOT_IMPLEMENTED' ||
            (forbiddenIsUnavailable && code == 'FORBIDDEN')) {
          throw const PantaException(PantaErrorCode.unavailable);
        }
        throw const PantaException(PantaErrorCode.rejected);
      }
      if (response.statusCode != 200) {
        throw const PantaException(PantaErrorCode.rejected);
      }
      final result = body['result'];
      if (result is! Map || !result.containsKey('data')) {
        throw const PantaException(PantaErrorCode.invalidResponse);
      }
      final data = result['data'];
      return data is Map && data.containsKey('json') ? data['json'] : data;
    } on PantaException {
      rethrow;
    } catch (_) {
      throw const PantaException(PantaErrorCode.invalidResponse);
    }
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

  void _validateUuid(String value) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value)) {
      throw const PantaException(PantaErrorCode.invalidResponse);
    }
  }

  void _validateOrderId(String orderId) {
    if (orderId.isEmpty || orderId.length > 128) {
      throw const PantaException(PantaErrorCode.invalidResponse);
    }
  }
}
