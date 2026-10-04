/// The seam between Settings → Sign-in methods and Supabase.
///
/// Two kinds of work, kept apart on purpose:
///
///   * linking X or Google onto THIS app's session — Supabase's own manual
///     identity linking (`linkIdentity`), on the app's client. Needs "Allow
///     manual linking" in Supabase Auth. The answer comes back on the
///     `login-callback` deep link: a code (Settings then re-reads the
///     account to see it) or an error code (`identity_already_exists` is
///     where a move starts — which itself needs a proof).
///   * proving the OTHER side of a link Supabase can't make — a sign-in made
///     only for that, which never touches the app's session:
///       - X/Google: PKCE in an auth session that returns to this caller
///         (ASWebAuthenticationSession on iOS, Custom Tabs / Auth Tab on
///         Android, via flutter_web_auth_2). The code verifier exists only in
///         this object's memory; the return address carries a fresh nonce
///         per attempt; nothing is accepted from a callback that is not this
///         attempt's (wrong or missing nonce, wrong host, no code). The app's
///         deep-link handlers never see it (its own `link-callback` host).
///       - a wallet: the Web3 grant over HTTP, signed by the wallet.
///     Only the access token is kept, in memory, and it is released
///     (`logout?scope=local`) as soon as the link is done or abandoned.
///
/// Tests inject a fake; the app uses [SupabaseSignInLinkPort].
library;

import 'dart:async';
import 'dart:convert';

import 'dart:math';

import 'package:app_links/app_links.dart';
import 'package:chumbucket/core/config/app_config.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:chumbucket/features/authentication/session/sign_in_methods.dart';
import 'package:chumbucket/features/authentication/session/solana_sign_in.dart';
import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Where a proof's auth session returns: the app's scheme on a host of its
/// own, so the app's deep-link handlers (Supabase's `login-callback`, the
/// share links) never see it. Must be on Supabase Auth's redirect allow-list
/// (`dev.cleva.chumbucket://link-callback**`).
const String kSignInProofCallback = 'dev.cleva.chumbucket://link-callback';

/// Opens [url] in an auth session and returns the URL it came back to.
typedef AuthSessionLauncher =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
    });

Future<String> _flutterWebAuth({
  required String url,
  required String callbackUrlScheme,
}) => FlutterWebAuth2.authenticate(
  url: url,
  callbackUrlScheme: callbackUrlScheme,
);

/// One PKCE attempt: a verifier and a nonce that exist only in memory.
class ProofAttempt {
  ProofAttempt._(this.verifier, this.nonce);

  factory ProofAttempt.fresh([Random? random]) {
    final rng = random ?? Random.secure();
    String token(int bytes) => base64UrlEncode(
      List<int>.generate(bytes, (_) => rng.nextInt(256)),
    ).replaceAll('=', '');
    return ProofAttempt._(token(48), token(24));
  }

  final String verifier;
  final String nonce;

  /// S256: base64url(sha256(verifier)), no padding.
  String get challenge => base64UrlEncode(
    sha256.convert(ascii.encode(verifier)).bytes,
  ).replaceAll('=', '');

  String get redirectTo =>
      Uri.parse(
        kSignInProofCallback,
      ).replace(queryParameters: {'n': nonce}).toString();

  /// The code from a callback that is THIS attempt's, or null. Anything else
  /// — another scheme or host, no nonce, another nonce, no code — is refused.
  String? codeFrom(String returned) {
    final uri = Uri.tryParse(returned);
    final expected = Uri.parse(kSignInProofCallback);
    if (uri == null ||
        uri.scheme != expected.scheme ||
        uri.host != expected.host ||
        uri.queryParameters['n'] != nonce) {
      return null;
    }
    final code = uri.queryParameters['code'];
    return code != null && RegExp(r'^[A-Za-z0-9-]{8,128}$').hasMatch(code)
        ? code
        : null;
  }

  @override
  String toString() => 'ProofAttempt(<redacted>)';
}

class SupabaseSignInLinkPort implements SignInLinkPort {
  SupabaseSignInLinkPort({
    AppLinks? links,
    http.Client? client,
    AuthSessionLauncher? launcher,
    String? baseUrl,
    String? anonKey,
  }) : _links = links,
       _client = client ?? http.Client(),
       _launch = launcher ?? _flutterWebAuth,
       _baseOverride = baseUrl,
       _keyOverride = anonKey;

  AppLinks? _links;
  final http.Client _client;
  final AuthSessionLauncher _launch;
  final String? _baseOverride;
  final String? _keyOverride;

  AppLinks get _appLinks => _links ??= AppLinks();

  String get _base => (_baseOverride ?? AppConfig.values['SUPABASE_URL'] ?? '')
      .replaceAll(RegExp(r'/+$'), '');
  String get _anonKey =>
      _keyOverride ?? AppConfig.values['SUPABASE_ANON_KEY'] ?? '';

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
    final params = await _appLinks.uriLinkStream
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
    final attempt = ProofAttempt.fresh();
    final authorize = Uri.parse('$_base/auth/v1/authorize').replace(
      queryParameters: {
        'provider': kind == SignInMethodKind.google ? 'google' : 'x',
        'redirect_to': attempt.redirectTo,
        'code_challenge': attempt.challenge,
        'code_challenge_method': 's256',
      },
    );
    final String returned;
    try {
      returned = await _launch(
        url: authorize.toString(),
        callbackUrlScheme: Uri.parse(kSignInProofCallback).scheme,
      ).timeout(timeout);
    } catch (_) {
      // Closed, cancelled, timed out: nothing was proven.
      throw const SignInLinkStopped('cancelled');
    }
    final code = attempt.codeFrom(returned);
    if (code == null) {
      final error = Uri.tryParse(returned)?.queryParameters['error_code'];
      throw SignInLinkStopped(
        error != null && _sameAttempt(returned, attempt) ? error : 'cancelled',
      );
    }
    return _exchange(code, attempt.verifier);
  }

  static bool _sameAttempt(String returned, ProofAttempt attempt) =>
      Uri.tryParse(returned)?.queryParameters['n'] == attempt.nonce;

  /// The one-time code + this attempt's verifier -> an access token. The
  /// refresh token in the answer is never kept.
  Future<String> _exchange(String code, String verifier) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_base/auth/v1/token?grant_type=pkce'),
            headers: {'apikey': _anonKey, 'content-type': 'application/json'},
            body: jsonEncode({'auth_code': code, 'code_verifier': verifier}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const SignInLinkStopped('network');
    }
    final body = response.statusCode == 200 ? jsonDecode(response.body) : null;
    final token = body is Map ? body['access_token'] : null;
    if (token is! String || token.isEmpty) {
      throw const SignInLinkStopped('cancelled');
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
