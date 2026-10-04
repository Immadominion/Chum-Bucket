/// The seam between Settings → Sign-in methods and Supabase.
///
/// Two kinds of work, kept apart on purpose:
///
///   * linking X or Google onto THIS app's session — Supabase's own manual
///     identity linking (`linkIdentity`), on the app's client. Needs "Allow
///     manual linking" in Supabase Auth. The answer comes back on the
///     `login-callback` deep link: a code (linked) or an error code
///     (`identity_already_exists` is where a move starts).
///   * proving the OTHER side of a link Supabase can't make — a sign-in made
///     only for that, which never touches the app's session: X/Google through
///     Supabase's implicit grant in the browser (the app's PKCE client ignores
///     a callback that carries tokens), a wallet through the Web3 grant over
///     HTTP. Only the access token is kept, in memory, and it is released
///     (`logout?scope=local`) as soon as the link is done or abandoned.
///
/// Tests inject a fake; the app uses [SupabaseSignInLinkPort].
library;

import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:chumbucket/core/config/app_config.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where a link stopped: a Supabase/BFF code, `cancelled` or `network`.
class SignInLinkStopped implements Exception {
  const SignInLinkStopped(this.code);
  final String code;

  @override
  String toString() => 'SignInLinkStopped($code)';
}

abstract class SignInLinkPort {
  /// Opens the provider to link it onto this app's session. Returns once the
  /// browser is open; the answer is the next [providerLinkResult].
  Future<void> startProviderLink(SignInMethodKind kind);

  /// The answer to [startProviderLink]: null when it linked, else the code.
  Future<String?> providerLinkResult({Duration timeout});

  /// Removes an identity from this app's own sign-in (Supabase keeps at
  /// least one; it refuses the last).
  Future<void> unlinkIdentity(String identityId);

  /// A sign-in with X or Google made only to prove it: its access token.
  Future<String> proveProvider(SignInMethodKind kind, {Duration timeout});

  /// A wallet sign-in made only to prove it: its access token.
  Future<String> proveWallet(SolanaSignInWallet wallet);

  /// Ends a proof's session at Supabase. Best effort.
  Future<void> release(String accessToken);
}

class SupabaseSignInLinkPort implements SignInLinkPort {
  SupabaseSignInLinkPort({AppLinks? links, http.Client? client})
    : _links = links ?? AppLinks(),
      _client = client ?? http.Client();

  final AppLinks _links;
  final http.Client _client;

  static String get _base =>
      (AppConfig.values['SUPABASE_URL'] ?? '').replaceAll(RegExp(r'/+$'), '');
  static String get _anonKey => AppConfig.values['SUPABASE_ANON_KEY'] ?? '';

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// The parameters of a `login-callback` link, query and fragment together.
  static Map<String, String>? _callback(Uri uri) {
    final expected = Uri.parse(kChumbucketOAuthRedirect);
    if (uri.scheme != expected.scheme || uri.host != expected.host) return null;
    return {
      ...uri.queryParameters,
      if (uri.fragment.isNotEmpty) ...Uri.splitQueryString(uri.fragment),
    };
  }

  static String? _errorOf(Map<String, String> params) =>
      params['error_code'] ??
      (params.containsKey('error_description') || params.containsKey('error')
          ? (params['error'] ?? 'cancelled')
          : null);

  @override
  Future<void> startProviderLink(SignInMethodKind kind) async {
    final ok = await _auth.linkIdentity(
      kind == SignInMethodKind.google
          ? OAuthProvider.google
          : OAuthProvider.twitter,
      redirectTo: kChumbucketOAuthRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
      // Supabase's X (OAuth 2.0) provider is `x`; see SupabaseFlutterAuthPort.
      queryParams: kind == SignInMethodKind.x ? const {'provider': 'x'} : null,
    );
    if (!ok) throw const SignInLinkStopped('network');
  }

  @override
  Future<String?> providerLinkResult({
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final params = await _links.uriLinkStream
        .map(_callback)
        .where(
          (p) => p != null && (p.containsKey('code') || _errorOf(p) != null),
        )
        .first
        .timeout(timeout, onTimeout: () => const {'error': 'cancelled'});
    return _errorOf(params!);
  }

  @override
  Future<void> unlinkIdentity(String identityId) async {
    try {
      final identities = await _auth.getUserIdentities();
      final match = identities.where((i) => i.identityId == identityId);
      if (match.isEmpty) throw const SignInLinkStopped('SIGN_IN_NOT_FOUND');
      await _auth.unlinkIdentity(match.first);
      await _auth.refreshSession();
    } on AuthException catch (e) {
      throw SignInLinkStopped(e.code ?? 'network');
    }
  }

  @override
  Future<String> proveProvider(
    SignInMethodKind kind, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    // The implicit grant (no code challenge): the tokens come back in the
    // fragment, which the app's PKCE client leaves alone.
    final authorize = Uri.parse('$_base/auth/v1/authorize').replace(
      queryParameters: {
        'provider': kind == SignInMethodKind.google ? 'google' : 'x',
        'redirect_to': kChumbucketOAuthRedirect,
      },
    );
    final answer = _links.uriLinkStream
        .map(_callback)
        .where(
          (p) =>
              p != null &&
              (p.containsKey('access_token') || _errorOf(p) != null),
        )
        .first
        .timeout(timeout, onTimeout: () => const {'error': 'cancelled'});
    final opened = await launchUrl(
      authorize,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw const SignInLinkStopped('network');
    final params = (await answer)!;
    final token = params['access_token'];
    if (token == null || token.isEmpty) {
      throw SignInLinkStopped(_errorOf(params) ?? 'cancelled');
    }
    return token;
  }

  @override
  Future<String> proveWallet(SolanaSignInWallet wallet) async {
    final address = await wallet.connect();
    final message = solanaSignInMessage(
      address: address,
      issuedAt: DateTime.now(),
    );
    final signature = await wallet.sign(message);
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_base/auth/v1/token?grant_type=web3'),
            headers: {'apikey': _anonKey, 'content-type': 'application/json'},
            body: jsonEncode({
              'chain': 'solana',
              'message': message,
              'signature': signature,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const SignInLinkStopped('network');
    }
    // Only the access token is read; the refresh token is never kept.
    final body = response.statusCode == 200 ? jsonDecode(response.body) : null;
    final token = body is Map ? body['access_token'] : null;
    if (token is! String || token.isEmpty) {
      throw const SignInLinkStopped('cancelled');
    }
    return token;
  }

  @override
  Future<void> release(String accessToken) async {
    try {
      await _client
          .post(
            Uri.parse('$_base/auth/v1/logout?scope=local'),
            headers: {
              'apikey': _anonKey,
              'authorization': 'Bearer $accessToken',
            },
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // It expires on its own.
    }
  }
}
