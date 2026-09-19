/// `SupabaseFlutterAuthPort` — the two pure mappings inside the one class that
/// touches `Supabase.instance`.
///
/// Everything else in this packet is driven through the port's *interface*, so
/// these two translations are the only Supabase-shaped code a fake cannot
/// cover. They are worth pinning:
///
/// * `Session.expiresAt` is unix **seconds** (it is the JWT's `exp` claim).
///   `DateTime.fromMillisecondsSinceEpoch` wants milliseconds. An off-by-1000
///   here makes every token look either permanently expired — refreshing on
///   every single request — or eternally fresh, so `bffAuthToken` never
///   refreshes and writes start failing after an hour. Neither shows up in a
///   test that only ever sees a fake snapshot.
/// * `AuthChangeEvent` has eight values and this app models four. The other
///   four must map to `other` rather than being guessed at.
///
/// Constructing the port is also asserted to be inert: it must not reach for
/// the `Supabase.instance` singleton until a member is actually called, or
/// `ChumbucketSession()` could not be built before `Supabase.initialize()`.
library;

import 'dart:convert';

import 'package:chumbucket/features/authentication/session/supabase_auth_port.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_fakes.dart';

/// A structurally valid JWT carrying an `exp` claim, which is where
/// `Session.expiresAt` actually comes from. The signature is not checked by
/// anything on this path.
String jwtExpiringAt(int expUnixSeconds, {String subject = kAuthUserId}) {
  String segment(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  return '${segment({'alg': 'HS256', 'typ': 'JWT'})}'
      '.${segment({'sub': subject, 'exp': expUnixSeconds})}'
      '.not-a-real-signature';
}

Session sessionWith(String accessToken, {String userId = kAuthUserId}) =>
    Session.fromJson({
      'access_token': accessToken,
      'token_type': 'bearer',
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-09-19T00:00:00Z',
      },
    })!;

void main() {
  group('snapshotOf', () {
    test('no session is no snapshot', () {
      expect(SupabaseFlutterAuthPort.snapshotOf(null), isNull);
    });

    test('carries the token and the caller own auth.uid()', () {
      final token = jwtExpiringAt(1789214400);
      final mapped = SupabaseFlutterAuthPort.snapshotOf(sessionWith(token))!;

      expect(mapped.accessToken, token);
      expect(mapped.authUserId, kAuthUserId);
    });

    test('reads expiry as unix SECONDS, not milliseconds', () {
      // 12 September 2026, 12:00:00 UTC, as unix seconds.
      const exp = 1789214400;
      final mapped =
          SupabaseFlutterAuthPort.snapshotOf(sessionWith(jwtExpiringAt(exp)))!;

      expect(mapped.expiresAt, DateTime.utc(2026, 9, 12, 12));
      // Reading it as milliseconds would land in January 1970 — which, being
      // in the past, would make every token look permanently expired.
      expect(
        mapped.expiresAt,
        isNot(DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true)),
      );
      expect(mapped.expiresAt!.isAfter(DateTime.utc(2026)), isTrue);
    });

    test('a token with no readable exp has no expiry rather than a wrong one',
        () {
      final mapped = SupabaseFlutterAuthPort.snapshotOf(
        sessionWith('not.a.jwt'),
      )!;
      expect(mapped.expiresAt, isNull);
      // Unknown expiry must never read as "expiring", or every request would
      // trigger a refresh.
      expect(mapped.isExpiring(), isFalse);
    });

    test('isExpiring fires inside the skew and not before', () {
      final now = DateTime.utc(2026, 9, 13, 12);
      final expiry = now.add(const Duration(minutes: 5));
      final mapped = SupabaseFlutterAuthPort.snapshotOf(
        sessionWith(
          jwtExpiringAt(expiry.millisecondsSinceEpoch ~/ 1000),
        ),
      )!;

      expect(mapped.isExpiring(now: now), isFalse);
      expect(
        mapped.isExpiring(now: expiry.subtract(const Duration(seconds: 31))),
        isFalse,
      );
      expect(
        mapped.isExpiring(now: expiry.subtract(const Duration(seconds: 29))),
        isTrue,
      );
      expect(mapped.isExpiring(now: expiry), isTrue);
    });
  });

  group('kindOf', () {
    test('maps the four events this app acts on', () {
      expect(
        SupabaseFlutterAuthPort.kindOf(AuthChangeEvent.initialSession),
        SupabaseAuthEventKind.initialSession,
      );
      expect(
        SupabaseFlutterAuthPort.kindOf(AuthChangeEvent.signedIn),
        SupabaseAuthEventKind.signedIn,
      );
      expect(
        SupabaseFlutterAuthPort.kindOf(AuthChangeEvent.tokenRefreshed),
        SupabaseAuthEventKind.tokenRefreshed,
      );
      expect(
        SupabaseFlutterAuthPort.kindOf(AuthChangeEvent.signedOut),
        SupabaseAuthEventKind.signedOut,
      );
    });

    test('maps everything else to "other" rather than guessing', () {
      const modelled = {
        AuthChangeEvent.initialSession,
        AuthChangeEvent.signedIn,
        AuthChangeEvent.tokenRefreshed,
        AuthChangeEvent.signedOut,
      };
      final rest = AuthChangeEvent.values.where((e) => !modelled.contains(e));

      expect(rest, isNotEmpty);
      for (final event in rest) {
        expect(
          SupabaseFlutterAuthPort.kindOf(event),
          SupabaseAuthEventKind.other,
          reason: event.name,
        );
      }
    });
  });

  test('constructing the port does not reach for Supabase.instance', () {
    // `Supabase.initialize()` has not run in this test process. If the port
    // resolved the singleton eagerly this would throw, and `ChumbucketSession()`
    // could not be constructed before Supabase was ready.
    expect(const SupabaseFlutterAuthPort(), isA<SupabaseAuthPort>());
  });

  test('the redirect matches the scheme declared on both platforms', () {
    // android/app/src/main/AndroidManifest.xml: scheme="dev.cleva.chumbucket",
    // host="login-callback". ios/Runner/Info.plist: CFBundleURLSchemes.
    expect(kChumbucketOAuthRedirect, 'dev.cleva.chumbucket://login-callback');
    final uri = Uri.parse(kChumbucketOAuthRedirect);
    expect(uri.scheme, 'dev.cleva.chumbucket');
    expect(uri.host, 'login-callback');
  });
}
