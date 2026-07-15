import 'dart:convert';
import 'dart:developer';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'package:chumbucket/features/arena/data/arena_models.dart';

/// Thin client for the gaffer-backend's read-only tRPC API.
///
/// This is READ-ONLY - it only lists fixtures and their live/settled pot
/// state so the UI knows which `matchId` to derive on-chain PDAs from. No
/// money moves through this service; all staking/claiming goes straight to
/// the chumbucket_arena Anchor program via [MatchArenaService].
///
/// The base URL is trivially swappable via the `ARENA_BACKEND_URL` env var
/// (see .env / .env.example) - never hardcode a host in Dart code.
class ArenaBackendService {
  final String baseUrl;

  ArenaBackendService({String? baseUrl})
    : baseUrl = _normalize(
        baseUrl ?? dotenv.env['ARENA_BACKEND_URL'] ?? 'http://localhost:8787',
      );

  static String _normalize(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// List of open/live/played fixtures with their pot state.
  Future<List<ArenaMatchEntry>> fetchMatchday() async {
    final uri = Uri.parse('$baseUrl/matchday');
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    final json = _decodeTrpcResponse(response, procedurePath: 'matchday');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaMatchEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Single fixture detail: bucket totals, status, the matchId string used
  /// for PDA derivation, and the TxLINE fixture id.
  Future<ArenaMatchEntry> fetchMatch(String matchId) async {
    final inputJson = jsonEncode({
      'json': {'matchId': matchId},
    });
    final uri = Uri.parse(
      '$baseUrl/match',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

    final json = _decodeTrpcResponse(response, procedurePath: 'match');
    return ArenaMatchEntry.fromJson(json as Map<String, dynamic>);
  }

  Future<List<ArenaServerPosition>> fetchMyPositions({
    required String walletAddress,
    int limit = 100,
  }) async {
    final inputJson = jsonEncode({
      'json': {'wallet': walletAddress, 'limit': limit},
    });
    final uri = Uri.parse(
      '$baseUrl/myPositions',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'myPositions');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaServerPosition.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ArenaActivityEvent>> fetchActivity({
    String? walletAddress,
    String? matchId,
    int limit = 50,
  }) async {
    final input = <String, dynamic>{'limit': limit};
    if (walletAddress != null) input['wallet'] = walletAddress;
    if (matchId != null) input['matchId'] = matchId;

    final inputJson = jsonEncode({'json': input});
    final uri = Uri.parse(
      '$baseUrl/activity',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'activity');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaActivityEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Mirror a wallet-submitted Arena call into the canonical social activity
  /// layer. The on-chain transaction remains the funds source of truth; this is
  /// the product read model that powers feeds, profiles, and "my positions".
  Future<void> recordPredictionCall({
    required String walletAddress,
    required String matchId,
    required int bucket,
    required BigInt stakeBaseUnits,
    required String txSignature,
    Map<String, dynamic>? metadata,
  }) async {
    final uri = Uri.parse('$baseUrl/recordPredictionCall');
    final bucketLabel = ArenaBucketIndex.toLabel(bucket);
    final body = jsonEncode({
      'json': {
        'wallet': walletAddress,
        'matchId': matchId,
        'marketId': 'RESULT',
        'bucket': bucketLabel,
        'stakeBaseUnits': stakeBaseUnits.toString(),
        'txSignature': txSignature,
        if (metadata != null) 'metadata': metadata,
      },
    });

    log('🏟️ ArenaBackendService: POST $uri recordPredictionCall');
    final response = await http
        .post(uri, headers: {'content-type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 15));

    _decodeTrpcResponse(response, procedurePath: 'recordPredictionCall');
  }

  /// Decodes a tRPC GET response envelope: `{"result":{"data":{"json": ... }}}`
  /// on success, or `{"error":{"json":{"message": ...}}}` on failure.
  dynamic _decodeTrpcResponse(
    http.Response response, {
    required String procedurePath,
  }) {
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw ArenaBackendException(
        'Invalid response from arena backend ($procedurePath): '
        'status ${response.statusCode}, body could not be parsed as JSON',
      );
    }

    if (body.containsKey('error')) {
      final error = body['error'] as Map<String, dynamic>?;
      final message =
          (error?['json'] as Map<String, dynamic>?)?['message'] ??
          error?['message'] ??
          'Unknown error';
      throw ArenaBackendException(
        'Arena backend error ($procedurePath): $message',
      );
    }

    if (response.statusCode != 200) {
      throw ArenaBackendException(
        'Arena backend returned ${response.statusCode} for $procedurePath',
      );
    }

    final result = body['result'] as Map<String, dynamic>?;
    final data = result?['data'];
    if (data is Map<String, dynamic> && data.containsKey('json')) {
      return data['json'];
    }
    // Fall back to raw data if the response wasn't superjson-wrapped.
    return data;
  }
}

class ArenaBackendException implements Exception {
  final String message;
  ArenaBackendException(this.message);

  @override
  String toString() => message;
}
