/// The token the app hands Privy for the Chumbucket wallet: the BFF's own
/// ten-minute JWT whose `sub` is the ACCOUNT (`wallet.privyToken`), never a
/// Supabase token. An account reached through a wallet sign-in and through X
/// therefore opens the same wallet.
///
/// It is held for exactly one account ([bind]) and fetched again a minute
/// before it expires. Privy calls [current] whenever it needs a token; it
/// never throws (Privy treats a failure as "signed out").
library;

import 'dart:convert';

import 'package:chumbucket/features/authentication/session/session_bff_client.dart';

class ChumbucketPrivyTokens {
  ChumbucketPrivyTokens({
    required SessionBffClient bff,
    required Future<String?> Function() authToken,
    DateTime Function()? now,
  }) : _bff = bff,
       _authToken = authToken,
       _now = now ?? DateTime.now;

  final SessionBffClient _bff;
  final Future<String?> Function() _authToken;
  final DateTime Function() _now;

  /// A token this close to expiry is fetched again.
  static const skew = Duration(minutes: 1);

  String? _account;
  ({String token, DateTime expiresAt})? _held;
  Future<String?>? _fetching;

  /// The account tokens are for; another account (or none) drops the held one.
  void bind(String? account) {
    if (account == _account) return;
    _account = account;
    _held = null;
    _fetching = null;
  }

  Future<String?> current() {
    final account = _account;
    if (account == null) return Future.value(null);
    final held = _held;
    if (held != null && held.expiresAt.subtract(skew).isAfter(_now())) {
      return Future.value(held.token);
    }
    return _fetching ??= _fetch(account).whenComplete(() => _fetching = null);
  }

  Future<String?> _fetch(String account) async {
    try {
      final session = await _authToken();
      if (session == null || _account != account) return null;
      final minted = await _bff.chumbucketPrivyToken(session);
      // Only a token for exactly this account is ever handed to Privy.
      if (_account != account || subjectOf(minted.token) != account) {
        return null;
      }
      _held = minted;
      return minted.token;
    } catch (_) {
      return null;
    }
  }

  /// The JWT's `sub`, read without verification (Privy verifies it).
  static String? subjectOf(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final sub = payload is Map ? payload['sub'] : null;
      return sub is String ? sub : null;
    } catch (_) {
      return null;
    }
  }
}
