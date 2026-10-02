/// Hands a backed-up refresh token to the Supabase SDK — the one place
/// [SessionContinuity] touches Supabase, kept apart so continuity itself stays
/// testable without the `Supabase.instance` singleton.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_continuity.dart';

/// `setSession` exchanges the refresh token for a fresh session, saves it
/// through `AppSessionPersistence` (which mirrors the new token straight back
/// into Block Store) and announces it on the auth stream, where
/// `ChumbucketSession` resolves the account as for any sign-in.
///
/// Errors are reduced to an outcome; nothing from them (they can carry the
/// request) is logged or kept.
Future<SessionAdoption> adoptBackedUpSession(String refreshToken) async {
  try {
    await Supabase.instance.client.auth.setSession(refreshToken);
    return SessionAdoption.adopted;
  } on AuthRetryableFetchException {
    return SessionAdoption.unreachable;
  } on AuthException catch (e) {
    final status = int.tryParse('${e.statusCode}');
    // The server answered and refused: the token is dead. A 5xx decided
    // nothing about it.
    return status != null && status >= 500
        ? SessionAdoption.unreachable
        : SessionAdoption.rejected;
  } catch (_) {
    return SessionAdoption.unreachable;
  }
}
