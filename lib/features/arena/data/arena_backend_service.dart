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

  Future<List<ArenaActivityEvent>> fetchFollowingFeed({
    required String walletAddress,
    int limit = 50,
  }) async {
    final inputJson = jsonEncode({
      'json': {'wallet': walletAddress, 'limit': limit},
    });
    final uri = Uri.parse(
      '$baseUrl/followingFeed',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'followingFeed');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaActivityEvent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ArenaLeaderboardRow>> fetchSocialLeaderboard({
    String by = 'pnl',
    int limit = 12,
  }) async {
    final inputJson = jsonEncode({
      'json': {'by': by, 'limit': limit},
    });
    final uri = Uri.parse(
      '$baseUrl/socialLeaderboard',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(
      response,
      procedurePath: 'socialLeaderboard',
    );
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaLeaderboardRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ArenaMatchCaller>> fetchMatchCallers({
    required String matchId,
    int limit = 50,
  }) async {
    final inputJson = jsonEncode({
      'json': {'matchId': matchId, 'limit': limit},
    });
    final uri = Uri.parse(
      '$baseUrl/matchCallers',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'matchCallers');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaMatchCaller.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Batch-resolve wallets to their linked-identity profile (X handle, display
  /// name, avatar) — the same `walletProfiles` procedure the web app calls.
  Future<List<ArenaWalletProfile>> fetchWalletProfiles({
    required List<String> wallets,
  }) async {
    if (wallets.isEmpty) return const [];
    final inputJson = jsonEncode({
      'json': {'wallets': wallets},
    });
    final uri = Uri.parse(
      '$baseUrl/walletProfiles',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'walletProfiles');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaWalletProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ArenaSocialProfile> fetchProfile({
    required String walletAddress,
    int limit = 20,
  }) async {
    final inputJson = jsonEncode({
      'json': {'wallet': walletAddress, 'limit': limit},
    });
    final uri = Uri.parse(
      '$baseUrl/profile',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'profile');
    return ArenaSocialProfile.fromJson(json as Map<String, dynamic>);
  }

  Future<List<ArenaServerPosition>> fetchClaimable({
    required String walletAddress,
    int limit = 20,
  }) async {
    final inputJson = jsonEncode({
      'json': {'wallet': walletAddress, 'limit': limit},
    });
    final uri = Uri.parse(
      '$baseUrl/claimable',
    ).replace(queryParameters: {'input': inputJson});
    log('ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'claimable');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaServerPosition.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ArenaNotification>> fetchNotifications({
    required String walletAddress,
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    final inputJson = jsonEncode({
      'json': {
        'wallet': walletAddress,
        'limit': limit,
        'unreadOnly': unreadOnly,
      },
    });
    final uri = Uri.parse(
      '$baseUrl/notifications',
    ).replace(queryParameters: {'input': inputJson});
    log('ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'notifications');
    final list = json as List<dynamic>;
    return list
        .map((e) => ArenaNotification.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> fetchUnreadNotificationCount({
    required String walletAddress,
  }) async {
    final inputJson = jsonEncode({
      'json': {'wallet': walletAddress},
    });
    final uri = Uri.parse(
      '$baseUrl/unreadCount',
    ).replace(queryParameters: {'input': inputJson});
    log('ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'unreadCount');
    return (json as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationsRead({
    required String walletAddress,
    List<String>? notificationIds,
    required int timestamp,
    required String signature,
  }) async {
    await _postMutation('markNotificationsRead', {
      'wallet': walletAddress,
      if (notificationIds != null) 'ids': notificationIds,
      'timestamp': timestamp,
      'signature': signature,
    });
  }

  Future<void> linkIdentity({
    required String walletAddress,
    required String accessToken,
    required int timestamp,
    required String signature,
  }) async {
    await _postMutation('linkIdentity', {
      'wallet': walletAddress,
      'accessToken': accessToken,
      'timestamp': timestamp,
      'signature': signature,
    });
  }

  Future<bool> isFollowing({
    required String viewerWallet,
    required String targetWallet,
  }) async {
    final inputJson = jsonEncode({
      'json': {'viewer': viewerWallet, 'target': targetWallet},
    });
    final uri = Uri.parse(
      '$baseUrl/isFollowing',
    ).replace(queryParameters: {'input': inputJson});
    log('🏟️ ArenaBackendService: GET $uri');

    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    final json = _decodeTrpcResponse(response, procedurePath: 'isFollowing');
    return json == true;
  }

  Future<void> followWallet({
    required String walletAddress,
    required String targetWallet,
    required int timestamp,
    required String signature,
  }) async {
    await _postMutation('follow', {
      'wallet': walletAddress,
      'target': targetWallet,
      'timestamp': timestamp,
      'signature': signature,
    });
  }

  Future<void> unfollowWallet({
    required String walletAddress,
    required String targetWallet,
    required int timestamp,
    required String signature,
  }) async {
    await _postMutation('unfollow', {
      'wallet': walletAddress,
      'target': targetWallet,
      'timestamp': timestamp,
      'signature': signature,
    });
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
    required int timestamp,
    required String signature,
    Map<String, dynamic>? metadata,
  }) async {
    final bucketLabel = ArenaBucketIndex.toLabel(bucket);
    await _postMutation('recordPredictionCall', {
      'wallet': walletAddress,
      'matchId': matchId,
      'marketId': 'RESULT',
      'bucket': bucketLabel,
      'stakeBaseUnits': stakeBaseUnits.toString(),
      'txSignature': txSignature,
      'timestamp': timestamp,
      'signature': signature,
      if (metadata != null) 'metadata': metadata,
    });
  }

  Future<void> _postMutation(
    String procedurePath,
    Map<String, dynamic> input,
  ) async {
    final uri = Uri.parse('$baseUrl/$procedurePath');
    final body = jsonEncode({'json': input});
    log('🏟️ ArenaBackendService: POST $uri $procedurePath');
    final response = await http
        .post(uri, headers: {'content-type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 15));

    _decodeTrpcResponse(response, procedurePath: procedurePath);
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
