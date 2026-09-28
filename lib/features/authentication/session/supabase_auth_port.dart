/// The seam between `ChumbucketSession` and Supabase.
///
/// Why a port at all: `Supabase.instance` is a process-wide singleton that
/// `main.dart` initialises. A unit test cannot construct one, cannot open a
/// browser, and must never try. Everything the session needs from Supabase is
/// five members, so they are declared here as an interface and a handful of
/// plain value types. Tests inject a fake; the app injects
/// [SupabaseFlutterAuthPort].
///
/// The real implementation is a deliberate reuse of the flow already working in
/// `lib/features/arena/providers/arena_provider.dart` (`linkOAuthIdentity`,
/// ~line 590): subscribe to `onAuthStateChange`, call `signInWithOAuth` with
/// `redirectTo: 'dev.cleva.chumbucket://login-callback'` and
/// `authScreenLaunchMode: LaunchMode.externalApplication`, and let the callback
/// deliver the session. That file is owned by another packet and is not edited
/// here; only its approach is reused.
///
/// The difference: arena signs in to *link* a Google identity onto a wallet
/// account. This port signs in as the **primary** identity, which is the thing
/// the app had no path to before.
library;

import 'dart:async';
import 'package:chumbucket/features/authentication/session/app_session_persistence.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The app's OAuth callback. Declared in
/// `android/app/src/main/AndroidManifest.xml` (`scheme="dev.cleva.chumbucket"`,
/// `host="login-callback"`) and in `ios/Runner/Info.plist`
/// (`CFBundleURLSchemes`), and already the redirect the arena flow uses.
const String kChumbucketOAuthRedirect = 'dev.cleva.chumbucket://login-callback';

/// The only three things the session needs out of a Supabase `Session`.
///
/// [accessToken] is a **credential**. It is never logged, never written to a
/// file, never placed in a URL, and never included in [toString] — see the
/// redacting override below, which exists so that dropping this object into a
/// `debugPrint`, an error report or a widget-inspector dump cannot leak it.
class SupabaseSessionSnapshot {
  const SupabaseSessionSnapshot({
    required this.accessToken,
    required this.authUserId,
    this.expiresAt,
  });

  /// The bearer the BFF verifies. Not identity — the canonical user is what
  /// `auth.whoami` returns for it.
  final String accessToken;

  /// The caller's own `auth.uid()`.
  final String authUserId;

  /// When the access token stops being accepted, if the provider said.
  final DateTime? expiresAt;

  /// True inside [skew] of expiry, so a refresh happens *before* the BFF has
  /// to reject a request.
  bool isExpiring({
    Duration skew = const Duration(seconds: 30),
    DateTime? now,
  }) {
    final deadline = expiresAt;
    if (deadline == null) return false;
    return !(now ?? DateTime.now().toUtc()).isBefore(deadline.subtract(skew));
  }

  /// Redacted on purpose. The token length is safe to show and is the one
  /// thing worth knowing when debugging "is there a token at all".
  @override
  String toString() =>
      'SupabaseSessionSnapshot(authUserId: $authUserId, '
      'accessToken: <redacted ${accessToken.length} chars>, '
      'expiresAt: $expiresAt)';
}

/// The subset of `AuthChangeEvent` that changes what the session must do.
/// Everything else (`userUpdated`, `passwordRecovery`, …) maps to [other] and
/// is ignored rather than guessed at.
enum SupabaseAuthEventKind {
  /// A session was restored at launch.
  initialSession,

  /// A sign-in completed — including the one this app started.
  signedIn,

  /// The same user, a new access token.
  tokenRefreshed,

  /// There is no session any more, wherever that came from.
  signedOut,

  /// Not interesting to this session.
  other,
}

/// One notification from the auth stream.
class SupabaseAuthEvent {
  const SupabaseAuthEvent(this.kind, [this.session]);

  final SupabaseAuthEventKind kind;

  /// Null for [SupabaseAuthEventKind.signedOut], and for any event that
  /// arrived without one.
  final SupabaseSessionSnapshot? session;

  @override
  String toString() => 'SupabaseAuthEvent(${kind.name}, session: $session)';
}

/// Everything `ChumbucketSession` is allowed to know about Supabase.
abstract class SupabaseAuthPort {
  /// The session restored from storage at launch, or null.
  SupabaseSessionSnapshot? get currentSession;

  /// Auth changes, for as long as the app runs. Broadcast: the session
  /// subscribes once and never competes with another listener.
  Stream<SupabaseAuthEvent> get authEvents;

  /// Opens the Google consent screen. Returns when the browser has been
  /// *launched*, not when the person has finished — the resulting session
  /// arrives on [authEvents] via the `login-callback` deep link.
  ///
  /// Returns false when the browser could not be opened at all.
  Future<bool> startGoogleSignIn({String redirectTo});

  /// Exchanges the refresh token for a new access token. Returns null when
  /// there is nothing to refresh.
  Future<SupabaseSessionSnapshot?> refreshSession();

  /// Ends the session locally and at the provider.
  Future<void> signOut();
}

/// The real port, over `Supabase.instance.client.auth`.
///
/// Constructing this touches nothing: every member resolves the singleton at
/// call time. That keeps `ChumbucketSession()` safe to build before
/// `Supabase.initialize()` has run, and keeps this class out of every test.
class SupabaseFlutterAuthPort implements SupabaseAuthPort {
  const SupabaseFlutterAuthPort();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  @override
  SupabaseSessionSnapshot? get currentSession =>
      AppSessionPersistence.current?.isLocked == true
          ? null
          : snapshotOf(_auth.currentSession);

  @override
  Stream<SupabaseAuthEvent> get authEvents => eventsOf(_auth.onAuthStateChange);

  /// The account tree is recreated after logout. Its new session must also
  /// ignore a late callback from the previous tree's browser activity.
  static Stream<SupabaseAuthEvent> eventsOf(Stream<AuthState> events) => events
      .where((_) => AppSessionPersistence.current?.isLocked != true)
      .map(
        (state) =>
            SupabaseAuthEvent(kindOf(state.event), snapshotOf(state.session)),
      );

  @override
  Future<bool> startGoogleSignIn({
    String redirectTo = kChumbucketOAuthRedirect,
  }) {
    AppSessionPersistence.current?.beginInteractiveSignIn();
    return _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
      // The system browser, not a webview: Google refuses embedded webviews for
      // OAuth, and this is what the arena link flow already does.
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

  @override
  Future<SupabaseSessionSnapshot?> refreshSession() async {
    if (AppSessionPersistence.current?.isLocked == true) return null;
    final response = await _auth.refreshSession();
    if (AppSessionPersistence.current?.isLocked == true) return null;
    return snapshotOf(response.session);
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// `Session` → [SupabaseSessionSnapshot]. Visible for the port's own tests.
  static SupabaseSessionSnapshot? snapshotOf(Session? session) {
    if (session == null) return null;
    final expiresAt = session.expiresAt;
    return SupabaseSessionSnapshot(
      accessToken: session.accessToken,
      authUserId: session.user.id,
      // `Session.expiresAt` is unix **seconds**, not milliseconds.
      expiresAt:
          expiresAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                expiresAt * 1000,
                isUtc: true,
              ),
    );
  }

  /// `AuthChangeEvent` → [SupabaseAuthEventKind]. Visible for the port's own
  /// tests; unknown events are [SupabaseAuthEventKind.other], never a guess.
  static SupabaseAuthEventKind kindOf(AuthChangeEvent event) {
    switch (event) {
      case AuthChangeEvent.initialSession:
        return SupabaseAuthEventKind.initialSession;
      case AuthChangeEvent.signedIn:
        return SupabaseAuthEventKind.signedIn;
      case AuthChangeEvent.tokenRefreshed:
        return SupabaseAuthEventKind.tokenRefreshed;
      case AuthChangeEvent.signedOut:
        return SupabaseAuthEventKind.signedOut;
      default:
        return SupabaseAuthEventKind.other;
    }
  }
}
